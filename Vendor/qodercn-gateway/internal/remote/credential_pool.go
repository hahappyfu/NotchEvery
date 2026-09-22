package remote

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The queue payload is JSON nested inside JSON, so the quotes arrive
// backslash-escaped — every field pattern has to allow \\*" between name and colon.
var (
	// retryAfterRe is the upstream's suggested poll interval.
	retryAfterRe = regexp.MustCompile(`retryAfterSeconds\\*":\s*(\d+)`)
	// waitTimeRe is the upstream's own estimate of how long admission will take.
	// It is the honest number: on 2026-09-21 it read 472 while retryAfterSeconds
	// read 30, and the caller's 3×30s budget expired long before admission.
	waitTimeRe = regexp.MustCompile(`waitTime\\*":\s*(\d+)`)
	// queueCountRe is the global backlog depth, for diagnostics only.
	queueCountRe = regexp.MustCompile(`queueCount\\*":\s*(\d+)`)
	// modelKeyRe names the queued model, for diagnostics only.
	modelKeyRe = regexp.MustCompile(`modelKey\\*":\s*\\*"([^\\"]+)`)
)

// queueSignal is the parsed upstream model-queue payload.
type queueSignal struct {
	ModelKey string
	// RetryAfter is how often the upstream wants to be polled.
	RetryAfter time.Duration
	// WaitTime is the upstream's estimate of total admission time; zero when the
	// upstream did not report one.
	WaitTime time.Duration
	// QueueCount is the global backlog depth; zero when not reported.
	QueueCount int
}

// queueRetryDelay reports whether err is the upstream's global model-queue
// signal and what it said. Free-tier models (Qwen3.8-Flash / qfmodel) answer 403
// with {"isQueued":true,"retryAfterSeconds":30,"waitTime":N}. The queue is
// server-wide — every account sees the same backlog, so switching credentials
// cannot help, which is why the caller waits instead of rotating.
func queueRetryDelay(err error) (queueSignal, bool) {
	msg := err.Error()
	if !strings.Contains(msg, "isQueued") {
		return queueSignal{}, false
	}
	sig := queueSignal{RetryAfter: 30 * time.Second}
	if m := retryAfterRe.FindStringSubmatch(msg); m != nil {
		if n, convErr := strconv.Atoi(m[1]); convErr == nil && n > 0 {
			sig.RetryAfter = time.Duration(n) * time.Second
		}
	}
	if m := waitTimeRe.FindStringSubmatch(msg); m != nil {
		if n, convErr := strconv.Atoi(m[1]); convErr == nil && n > 0 {
			sig.WaitTime = time.Duration(n) * time.Second
		}
	}
	if m := queueCountRe.FindStringSubmatch(msg); m != nil {
		if n, convErr := strconv.Atoi(m[1]); convErr == nil && n > 0 {
			sig.QueueCount = n
		}
	}
	if m := modelKeyRe.FindStringSubmatch(msg); m != nil {
		sig.ModelKey = m[1]
	}
	return sig, true
}

// queueDeadline is how long one request will sit in the upstream queue before
// handing the error back. The upstream's retryAfterSeconds is a poll interval,
// not a completion estimate — measured 2026-09-21 it stayed at 30 while waitTime
// climbed past 470 — so waiting budget is driven by waitTime and this ceiling.
const queueDeadline = 10 * time.Minute

var ErrPoolExhausted = errors.New("all credentials in pool are cooled or exhausted")

type PoolVerdict int

const (
	VerdictOK PoolVerdict = iota
	VerdictSwitch
	VerdictPropagate
)

// PoolConfig is the whole pooling knob set. Anything not listed here does not
// exist — an earlier cut carried seven parsed-but-never-read fields
// (AutoProbe, ProbeInterval, ProbePrompt, ProbeTimeout, ProbeModel, PricingPlan,
// ShadowBilling), which made config.example.json advertise settings that did
// nothing.
type PoolConfig struct {
	PoolDir          string
	MaxSwitches      int
	ProbeEnabled     bool
	ProbeQuietMin    int
	ProbeIntervalMin int
	// QuotaCheck reports an account's credit total and whether it is flagged
	// exceeded, keyed by access token. When set, members reporting total==0 &&
	// exceeded are treated as retired (see AccountState.ZeroQuota). nil disables
	// the check entirely — every member is then assumed usable.
	QuotaCheck QuotaCheckFunc
}

// QuotaCheckFunc looks up an account's quota by OAuth access token.
type QuotaCheckFunc func(ctx context.Context, accessToken string) (total float64, exceeded bool, err error)

type AccountState struct {
	Cred           Credential
	Cooled         bool
	CooledUntil    time.Time
	CoolReason     string
	LastUsedAt     time.Time
	LastFailedAt   time.Time
	LastProbeAt    time.Time
	LastProbeOk    bool
	LastProbeError string
	// ZeroQuota marks an account whose /quota reports total==0 and exceeded — a
	// retired free-plan credential that can never serve a chat call. Populated
	// off the request path; see refreshZeroQuotaLocked.
	ZeroQuota          bool
	ZeroQuotaCheckedAt time.Time
}

type AccountStatusDTO struct {
	UserID         string `json:"user_id"`
	Source         string `json:"source"`
	Cooled         bool   `json:"cooled"`
	CooledUntil    string `json:"cooled_until,omitempty"`
	CoolReason     string `json:"cool_reason,omitempty"`
	TokenExpiresAt string `json:"token_expires_at,omitempty"`
	LastUsedAt     string `json:"last_used_at,omitempty"`
	LastProbeAt    string `json:"last_probe_at,omitempty"`
	LastProbeOk    bool   `json:"last_probe_ok"`
}

type PoolStatusDTO struct {
	TotalAccounts   int                `json:"total_accounts"`
	ActiveAccounts  int                `json:"active_accounts"`
	CooledAccounts  int                `json:"cooled_accounts"`
	StickyUserID    string             `json:"sticky_user_id,omitempty"`
	EarliestResetAt string             `json:"earliest_reset_at,omitempty"`
	Accounts        []AccountStatusDTO `json:"accounts"`
}

type CredentialPool struct {
	cfg      PoolConfig
	mu       sync.RWMutex
	accounts map[string]*AccountState
	// retired holds ZeroQuota verdicts for accounts excluded from rotation, so a
	// hot reload does not re-admit and re-classify them every cycle. Keyed by
	// user_id; the value only needs Cred + the two ZeroQuota fields.
	retired    map[string]*AccountState
	stickyUser string
	dirModTime time.Time
	stopCh     chan struct{}
}

func NewCredentialPool(cfg PoolConfig) (*CredentialPool, error) {
	if cfg.MaxSwitches <= 0 {
		cfg.MaxSwitches = 3
	}
	if cfg.ProbeQuietMin <= 0 {
		cfg.ProbeQuietMin = 30
	}
	if cfg.ProbeIntervalMin <= 0 {
		cfg.ProbeIntervalMin = 30
	}
	p := &CredentialPool{
		cfg:      cfg,
		accounts: make(map[string]*AccountState),
		retired:  make(map[string]*AccountState),
		stopCh:   make(chan struct{}),
	}
	if err := p.reloadLocked(); err != nil {
		return nil, err
	}
	return p, nil
}

func (p *CredentialPool) reloadLocked() error {
	dir := expandHome(p.cfg.PoolDir)
	info, err := os.Stat(dir)
	if err != nil {
		return fmt.Errorf("stat pool dir %s: %w", dir, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("pool path %s is not a directory", dir)
	}
	p.dirModTime = info.ModTime()

	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("read pool dir %s: %w", dir, err)
	}

	newAccounts := make(map[string]*AccountState)
	newRetired := make(map[string]*AccountState)
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		cred, err := loadCredentialFile(path)
		if err != nil {
			log.Printf("[pool] skip invalid credential file %s: %v", path, err)
			continue
		}
		if cred.UserID == "" {
			log.Printf("[pool] skip credential with empty user_id in %s", path)
			continue
		}

		state := &AccountState{
			Cred: cred,
		}
		// Reuse a prior verdict whether the account is currently in rotation or
		// parked as retired.
		prev, wasActive := p.accounts[cred.UserID]
		if !wasActive {
			prev = p.retired[cred.UserID]
		}
		if prev != nil {
			state.Cooled = prev.Cooled
			state.CooledUntil = prev.CooledUntil
			state.CoolReason = prev.CoolReason
			state.LastUsedAt = prev.LastUsedAt
			state.LastFailedAt = prev.LastFailedAt
			state.LastProbeAt = prev.LastProbeAt
			state.LastProbeOk = prev.LastProbeOk
			state.LastProbeError = prev.LastProbeError
			// Carry the cached verdict across reloads so a hot-reload does not
			// re-admit a retired account (or drop a healthy one) until the next
			// background check updates it.
			state.ZeroQuota = prev.ZeroQuota
			state.ZeroQuotaCheckedAt = prev.ZeroQuotaCheckedAt
		}
		// A newly-seen member has no verdict yet; admit it optimistically and let
		// refreshZeroQuota classify it off the request path. Never retire on the
		// basis of an absent check.
		if state.ZeroQuota {
			newRetired[cred.UserID] = state
			continue
		}
		newAccounts[cred.UserID] = state
	}

	// Log newly-retired accounts once, not on every reload.
	for uid, st := range newRetired {
		if _, already := p.retired[uid]; !already {
			log.Printf("[pool] skip retired account %s (total quota 0 and exceeded)", maskIdentifier(st.Cred.UserID))
		}
	}

	p.accounts = newAccounts
	p.retired = newRetired
	return nil
}

func (p *CredentialPool) maybeReload() {
	dir := expandHome(p.cfg.PoolDir)
	info, err := os.Stat(dir)
	if err != nil {
		return
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if info.ModTime().After(p.dirModTime) {
		_ = p.reloadLocked()
	}
}

func (p *CredentialPool) Current(attempt int, inFlightExcluded map[string]bool) (Credential, error) {
	p.maybeReload()
	p.mu.Lock()
	defer p.mu.Unlock()

	now := time.Now()
	// Check expiry and cooled timeouts
	for _, acc := range p.accounts {
		if acc.Cooled && now.After(acc.CooledUntil) {
			acc.Cooled = false
			acc.CoolReason = ""
			log.Printf("[pool] account %s cooldown expired; restored to active", maskIdentifier(acc.Cred.UserID))
		}
	}

	// 1. Attempt 0: check sticky user
	if attempt == 0 && p.stickyUser != "" {
		if acc, ok := p.accounts[p.stickyUser]; ok {
			if !acc.Cooled && !isTokenExpired(acc.Cred) && !inFlightExcluded[p.stickyUser] {
				acc.LastUsedAt = now
				return acc.Cred, nil
			}
		}
	}

	// 2. Candidate collection
	var candidates []*AccountState
	for uid, acc := range p.accounts {
		if acc.Cooled {
			continue
		}
		if isTokenExpired(acc.Cred) {
			continue
		}
		if inFlightExcluded != nil && inFlightExcluded[uid] {
			continue
		}
		candidates = append(candidates, acc)
	}

	if len(candidates) == 0 {
		return Credential{}, ErrPoolExhausted
	}

	// 3. Sort by TokenExpireTime descending (furthest expiry first)
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].Cred.TokenExpireTime > candidates[j].Cred.TokenExpireTime
	})

	picked := candidates[0]
	picked.LastUsedAt = now
	p.stickyUser = picked.Cred.UserID
	return picked.Cred, nil
}

func (p *CredentialPool) Inspect(userID string, statusCode int, body []byte) PoolVerdict {
	p.mu.Lock()
	defer p.mu.Unlock()

	acc, exists := p.accounts[userID]
	now := time.Now()

	switch {
	case statusCode >= 200 && statusCode < 300:
		if exists && acc.Cooled {
			acc.Cooled = false
			acc.CoolReason = ""
		}
		return VerdictOK

	case statusCode == 429:
		if exists {
			acc.Cooled = true
			acc.CooledUntil = now.Add(15 * time.Minute)
			acc.CoolReason = "rate_limited"
			acc.LastFailedAt = now
		}
		if p.stickyUser == userID {
			p.stickyUser = ""
		}
		return VerdictSwitch

	case statusCode == 401 || statusCode == 403:
		bodyLower := bytes.ToLower(body)

		// Global model queue: the free tier (e.g. Qwen3.8-Flash / qfmodel) returns
		// {"isQueued":true,"queueCount":N,"retryAfterSeconds":30}. The queue is
		// server-wide, so every account sees the same backlog — switching cannot
		// help, and the account is perfectly healthy. Leave pool state untouched
		// and propagate so the caller reports the real cause.
		if bytes.Contains(bodyLower, []byte("isqueued")) ||
			bytes.Contains(bodyLower, []byte("10605")) {
			return VerdictPropagate
		}

		// Paid-model credits: a model billed per credit (e.g. DeepSeek) answers
		// 403 once the account's credit balance runs out, which is separate from
		// the free daily-request counter that trips isQuota below. This is
		// per-account (unlike the global queue above) and resets on the daily
		// rollover, so cool and rotate. Checked before isQuota so a message that
		// names both (e.g. "quota exceeded: insufficient credits") reports the
		// more specific cause and gets its own reason for the UI.
		isCredits := bytes.Contains(bodyLower, []byte("credit")) ||
			bytes.Contains(bodyLower, []byte("point")) ||
			bytes.Contains(bodyLower, []byte("点数不足")) ||
			bytes.Contains(bodyLower, []byte("余额不足")) ||
			bytes.Contains(bodyLower, []byte("insufficient")) ||
			bytes.Contains(bodyLower, []byte("exhausted"))

		isQuota := bytes.Contains(bodyLower, []byte("exceed")) ||
			bytes.Contains(bodyLower, []byte("quota")) ||
			bytes.Contains(bodyLower, []byte("limit")) ||
			bytes.Contains(bodyLower, []byte("每日")) ||
			bytes.Contains(bodyLower, []byte("额度")) ||
			bytes.Contains(bodyLower, []byte("上限")) ||
			bytes.Contains(bodyLower, []byte("配额"))

		isAuth := bytes.Contains(bodyLower, []byte("invalid token")) ||
			bytes.Contains(bodyLower, []byte("unauthorized")) ||
			bytes.Contains(bodyLower, []byte("未登录")) ||
			bytes.Contains(bodyLower, []byte("expire")) ||
			bytes.Contains(bodyLower, []byte("token is invalid"))

		if isCredits {
			if exists {
				acc.Cooled = true
				acc.CooledUntil = nextLocalMidnight()
				acc.CoolReason = "credits_exhausted"
				acc.LastFailedAt = now
			}
			if p.stickyUser == userID {
				p.stickyUser = ""
			}
			return VerdictSwitch
		}

		if isQuota {
			if exists {
				acc.Cooled = true
				acc.CooledUntil = nextLocalMidnight()
				acc.CoolReason = "daily_limit"
				acc.LastFailedAt = now
			}
			if p.stickyUser == userID {
				p.stickyUser = ""
			}
			return VerdictSwitch
		}

		if isAuth {
			if exists {
				acc.Cooled = true
				acc.CooledUntil = nextLocalMidnight()
				acc.CoolReason = "auth_invalid"
				acc.LastFailedAt = now
			}
			if p.stickyUser == userID {
				p.stickyUser = ""
			}
			return VerdictSwitch
		}

		// 401/403 without specific matching: switch without cool
		if p.stickyUser == userID {
			p.stickyUser = ""
		}
		return VerdictSwitch

	default:
		// 5xx / 400 / 404: propagate without modifying pool state
		return VerdictPropagate
	}
}

func (p *CredentialPool) Summary() string {
	p.mu.RLock()
	defer p.mu.RUnlock()
	total := len(p.accounts)
	cooled := 0
	for _, acc := range p.accounts {
		if acc.Cooled {
			cooled++
		}
	}
	return fmt.Sprintf("total=%d active=%d cooled=%d sticky=%s", total, total-cooled, cooled, maskIdentifier(p.stickyUser))
}

func (p *CredentialPool) Status() PoolStatusDTO {
	return p.StatusDTO()
}

func (p *CredentialPool) StatusDTO() PoolStatusDTO {
	p.mu.RLock()
	defer p.mu.RUnlock()

	var accountsDTO []AccountStatusDTO
	var earliestReset time.Time
	cooledCount := 0

	for _, acc := range p.accounts {
		if acc.Cooled {
			cooledCount++
			if earliestReset.IsZero() || acc.CooledUntil.Before(earliestReset) {
				earliestReset = acc.CooledUntil
			}
		}

		var expStr string
		if acc.Cred.TokenExpireTime > 0 {
			expStr = time.UnixMilli(acc.Cred.TokenExpireTime).Format(time.RFC3339)
		}

		dto := AccountStatusDTO{
			UserID:         maskIdentifier(acc.Cred.UserID),
			Source:         acc.Cred.Source,
			Cooled:         acc.Cooled,
			CoolReason:     acc.CoolReason,
			TokenExpiresAt: expStr,
			LastProbeOk:    acc.LastProbeOk,
		}
		if !acc.LastUsedAt.IsZero() {
			dto.LastUsedAt = acc.LastUsedAt.Format(time.RFC3339)
		}
		if !acc.CooledUntil.IsZero() {
			dto.CooledUntil = acc.CooledUntil.Format(time.RFC3339)
		}
		if !acc.LastProbeAt.IsZero() {
			dto.LastProbeAt = acc.LastProbeAt.Format(time.RFC3339)
		}
		accountsDTO = append(accountsDTO, dto)
	}

	// Stable sort accounts by UserID
	sort.Slice(accountsDTO, func(i, j int) bool {
		return accountsDTO[i].UserID < accountsDTO[j].UserID
	})

	earliestStr := ""
	if !earliestReset.IsZero() {
		earliestStr = earliestReset.Format(time.RFC3339)
	}

	return PoolStatusDTO{
		TotalAccounts:   len(p.accounts),
		ActiveAccounts:  len(p.accounts) - cooledCount,
		CooledAccounts:  cooledCount,
		StickyUserID:    maskIdentifier(p.stickyUser),
		EarliestResetAt: earliestStr,
		Accounts:        accountsDTO,
	}
}

func nextLocalMidnight() time.Time {
	now := time.Now()
	return time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, now.Location())
}

func isTokenExpired(cred Credential) bool {
	if cred.TokenExpireTime <= 0 {
		return false
	}
	// Expired if current time + 5min is after token expire time
	return time.Now().Add(5 * time.Minute).After(time.UnixMilli(cred.TokenExpireTime))
}

type ProbeFunc func(ctx context.Context, cred Credential) error

func (p *CredentialPool) ProbeOnce(ctx context.Context, probe ProbeFunc) bool {
	p.mu.Lock()
	if len(p.accounts) == 0 {
		p.mu.Unlock()
		return false
	}

	var candidate *AccountState
	now := time.Now()

	for _, acc := range p.accounts {
		if !acc.Cooled {
			continue
		}
		// Check quiet period
		if p.cfg.ProbeQuietMin > 0 && now.Sub(acc.LastFailedAt) < time.Duration(p.cfg.ProbeQuietMin)*time.Minute {
			continue
		}
		if candidate == nil || acc.LastFailedAt.Before(candidate.LastFailedAt) {
			candidate = acc
		}
	}

	if candidate == nil {
		p.mu.Unlock()
		return false
	}

	cred := candidate.Cred
	userID := candidate.Cred.UserID
	p.mu.Unlock()

	// Probe with 20s timeout in isolated context
	probeCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	err := probe(probeCtx, cred)

	p.mu.Lock()
	defer p.mu.Unlock()

	target, exists := p.accounts[userID]
	if !exists {
		return false
	}

	target.LastProbeAt = time.Now()
	if err == nil {
		target.Cooled = false
		target.CoolReason = ""
		target.LastProbeError = ""
		target.LastProbeOk = true
		log.Printf("[pool] probe succeeded for %s; restored to active pool", maskIdentifier(cred.UserID))
		return true
	}

	target.LastProbeOk = false
	target.LastProbeError = truncate(err.Error(), 150)
	log.Printf("[pool] probe failed for %s: %s; keeping cooled", maskIdentifier(cred.UserID), target.LastProbeError)
	return false
}

func (p *CredentialPool) StartProbeLoop(ctx context.Context, probe ProbeFunc) {
	if !p.cfg.ProbeEnabled {
		return
	}
	go func() {
		// NewCredentialPool guarantees a positive interval.
		ticker := time.NewTicker(time.Duration(p.cfg.ProbeIntervalMin) * time.Minute)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-p.stopCh:
				return
			case <-ticker.C:
				p.ProbeOnce(ctx, probe)
			}
		}
	}()
}

// zeroQuotaTTL is how long a ZeroQuota verdict stays fresh before the account is
// re-checked. Quota pools reset on a daily cadence, so hourly re-checks are ample
// and keep background load to roughly one request per account per hour.
const zeroQuotaTTL = time.Hour

// refreshZeroQuotaOnce classifies active accounts whose quota verdict is missing
// or stale. It runs off the request path: it snapshots the accounts needing a
// check under the lock, releases the lock for each network call, then re-takes
// the lock to record the verdict — so a slow /quota never blocks Current().
//
// An account is retired only when total==0 AND exceeded==true together; that pair
// is what a post-trial free-plan credential looks like (observed on the deleted
// 01a0bd70). Any error, timeout, or nil check leaves the account optimistically
// active — never retire on uncertainty.
func (p *CredentialPool) refreshZeroQuotaOnce(ctx context.Context) {
	check := p.cfg.QuotaCheck
	if check == nil {
		return
	}

	p.mu.Lock()
	now := time.Now()
	type pending struct {
		userID string
		token  string
	}
	var due []pending
	for uid, acc := range p.accounts {
		if now.Sub(acc.ZeroQuotaCheckedAt) < zeroQuotaTTL {
			continue
		}
		due = append(due, pending{userID: uid, token: acc.Cred.AccessToken})
	}
	p.mu.Unlock()

	for _, item := range due {
		checkCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
		total, exceeded, err := check(checkCtx, item.token)
		cancel()

		p.mu.Lock()
		acc, exists := p.accounts[item.userID]
		if !exists {
			// Removed by a reload while we were checking; nothing to record.
			p.mu.Unlock()
			continue
		}
		acc.ZeroQuotaCheckedAt = time.Now()
		retire := err == nil && total <= 0 && exceeded
		acc.ZeroQuota = retire
		if retire {
			log.Printf("[pool] retiring %s: quota total=0 exceeded=true (post-trial free plan cannot serve chat calls)",
				maskIdentifier(item.userID))
			delete(p.accounts, item.userID)
			p.retired[item.userID] = acc
			if p.stickyUser == item.userID {
				p.stickyUser = ""
			}
		}
		p.mu.Unlock()
	}
}

// StartQuotaCheckLoop launches the background retirement scan when a QuotaCheck
// is wired. Independent of the recovery probe loop: probing may be disabled while
// quota classification is still wanted, and vice versa.
func (p *CredentialPool) StartQuotaCheckLoop(ctx context.Context) {
	if p.cfg.QuotaCheck == nil {
		return
	}
	go func() {
		// Classify once shortly after startup, then on a fixed cadence.
		timer := time.NewTimer(5 * time.Second)
		defer timer.Stop()
		interval := time.NewTicker(zeroQuotaTTL)
		defer interval.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-p.stopCh:
				return
			case <-timer.C:
				p.refreshZeroQuotaOnce(ctx)
			case <-interval.C:
				p.refreshZeroQuotaOnce(ctx)
			}
		}
	}()
}

func (p *CredentialPool) Close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	select {
	case <-p.stopCh:
	default:
		close(p.stopCh)
	}
}
