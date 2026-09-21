# QoderCN 网关 · 内嵌式多凭据账号池 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 QoderCN 网关内置凭据池，当 Chat() 拿到 401/403 等额度类失败时，自动当场换号重试，使客户端请求无感成功；全程不影响正在承载当前会话的原 8095 网关。

**架构：** 在独立目录 `qodercn-gateway-pool/` 中初始化独立 git 仓库。通过独立的 `internal/remote/credential_pool.go` 承载全部池状态、成员扫描、两态切换、D1 恢复探针调度及状态摘要；在 `internal/remote/client.go` 的 `Chat()` 函数建立有界重试环（重试时按新号重构 headers 与请求）；新增 `GET /v1/pool/status` 端点供可观测；绑定 8096 独立端口调试。

**技术栈：** Go 1.21+, 标准库 (`net/http`, `sync`, `bufio`, `testing/httptest`)，无新增三方依赖。

**规格：** [docs/superpowers/specs/2026-09-20-qoder-account-pool-design.md](../specs/2026-09-20-qoder-account-pool-design.md)

## 全局约束

- **会话生存硬约束：** 绝不修改、重启、停止或向 `8095` 端口发送请求；原 `qodercn-gateway/` 目录源码一行不改；新项目所有操作在 `/Users/fupingguo/fuhaha_workspace/ali-tools/qodercn-gateway-pool/` 推进，监听端口固定为 **8096**。
- **改动集中原则：** 现有上游代码只动 `credentials.go`（读池成员 helper ~15 行）、`client.go`（`Config` 结构 + `Chat()` 重试环 ~40 行）、`service.go`（配置穿透 ~10 行）、`httpapi/server.go`（注册 `/v1/pool/status` ~20 行）、`main.go`（配置接线 ~15 行）；其余 6 处 `LoadCredential` 调用点与 deploy bundle 逻辑绝对不改。
- **回退安全承诺：** `remote_auth_pool_dir` 为空时，新网关代码执行路径与原版完全一致，池逻辑与后台探针均不启动。
- **保守判定：** 401/403 只有命中额度或鉴权关键字才进入冷却；未命中关键字只换号不冷却；5xx/网络故障绝不碰池状态。

---

### 文件结构与职责表

| 文件路径 | 状态 | 职责 |
|---|---|---|
| `internal/remote/credential_pool.go` | **创建** | 池核心：目录扫描、明文成员加载、sticky+expire 排序、冷却状态机、D1 探针调度、状态摘要、并发安全 |
| `internal/remote/credential_pool_test.go` | **创建** | 池单元测试：加载、排序、关键字判定、冷却解冻、探针模拟（httptest）、并发安全 |
| `internal/remote/credentials.go` | **修改** | 新增 `LoadCredentialFromBytes([]byte, string)` 导出函数，复用现成解析与校验 |
| `internal/remote/client.go` | **修改** | `Config` 接入池字段；`Chat()` 内包裹重试环；导出 `Pool()` 访问器与探针单发方法 |
| `internal/service/service.go` | **修改** | `Config` 接入池配置，向 `remote.New` 穿透参数；暴露 `PoolStatus()` 代理调用 |
| `internal/httpapi/server.go` | **修改** | 路由注册 `GET /v1/pool/status`；处理请求并返回脱敏池状态 JSON |
| `cmd/qodercn-gateway/main.go` | **修改** | 命令行 flag、`fileConfig`、环境变量接入 `remote_auth_pool_dir` 及池参数 |
| `config.example.json` | **修改** | 添加池配置字段注释示例 |

---

### 任务 1：创建独立工作目录与独立 Git 仓库

**文件：**
- 工作根目录：`/Users/fupingguo/fuhaha_workspace/ali-tools/qodercn-gateway-pool/`
- 配置文件：`qodercn-gateway-pool/local.json`

- [ ] **步骤 1：复制基线代码并初始化独立 Git 仓库**

```bash
cd /Users/fupingguo/fuhaha_workspace/ali-tools
cp -R qodercn-gateway qodercn-gateway-pool
cd qodercn-gateway-pool
rm -rf logs/* build/*
git init
git add .
git commit -m "chore: baseline upstream v0.2.1 snapshot"
git tag v0.2.1-upstream
```

- [ ] **步骤 2：调整 local.json 绑定 8096 端口**

编辑 `qodercn-gateway-pool/local.json`，确保 port 为 8096，auth_keys_file 指向本目录下的 `local.authkeys`：
```json
{
  "host": "127.0.0.1",
  "port": 8096,
  "model": "Qwen3.8-Flash",
  "session_mode": "auto",
  "auth_keys_file": "/Users/fupingguo/fuhaha_workspace/ali-tools/qodercn-gateway-pool/local.authkeys"
}
```

- [ ] **步骤 3：验证基线构建与测试**

在 `qodercn-gateway-pool` 目录运行：
`go test -race ./...`
预期：PASS（基线所有测试通过）

- [ ] **步骤 4：Commit 隔离环境配置**

```bash
git add local.json
git commit -m "chore: isolate dev environment to port 8096"
```

---

### 任务 2：重构 Credentials 解析为可复用函数

**文件：**
- 修改：`internal/remote/credentials.go`
- 测试：`internal/remote/credentials_test.go`（若不存在则创建）

- [ ] **步骤 1：编写失败测试验证 LoadCredentialFromBytes**

创建/修改 `internal/remote/credentials_test.go`：
```go
package remote

import (
	"testing"
)

func testValidCredJSON() []byte {
	return []byte(`{
		"source": "pool-test",
		"token_expire_time": "1893456000000",
		"auth": {
			"cosy_key": "test-cosy-key",
			"encrypt_user_info": "test-info",
			"user_id": "user_12345678",
			"machine_id": "mach_12345678",
			"access_token": "token_abc"
		}
	}`)
}

func TestLoadCredentialFromBytes_Valid(t *testing.T) {
	cred, err := LoadCredentialFromBytes(testValidCredJSON(), "test.json")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cred.UserID != "user_12345678" {
		t.Errorf("got UserID %q, want user_12345678", cred.UserID)
	}
	if cred.Source != "pool-test" {
		t.Errorf("got Source %q, want pool-test", cred.Source)
	}
}

func TestLoadCredentialFromBytes_Invalid(t *testing.T) {
	_, err := LoadCredentialFromBytes([]byte(`{"invalid": true}`), "bad.json")
	if err == nil {
		t.Fatal("expected validation error, got nil")
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`go test -v ./internal/remote -run TestLoadCredentialFromBytes`
预期：FAIL（`LoadCredentialFromBytes` 未定义）

- [ ] **步骤 3：在 credentials.go 中提取实现**

修改 `internal/remote/credentials.go`，将 `loadCredentialFile` 底层拆出公用的 `LoadCredentialFromBytes`：
```go
// LoadCredentialFromBytes parses and validates a JSON-encoded credential payload.
func LoadCredentialFromBytes(body []byte, fallbackSource string) (Credential, error) {
	var stored storedCredentialFile
	if err := json.Unmarshal(body, &stored); err != nil {
		return Credential{}, fmt.Errorf("parse remote auth json: %w", err)
	}
	cred := Credential{
		CosyKey:         stored.Auth.CosyKey,
		EncryptUserInfo: stored.Auth.EncryptUserInfo,
		UserID:          stored.Auth.UserID,
		MachineID:       stored.Auth.MachineID,
		AccessToken:     stored.Auth.AccessToken,
		Source:          valueOr(stored.Source, fallbackSource),
		TokenExpireTime: parseExpire(stored.TokenExpireTime),
	}
	return cred, validateCredential(cred)
}

func loadCredentialFile(path string) (Credential, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return Credential{}, fmt.Errorf("read remote auth file: %w", err)
	}
	cred, err := LoadCredentialFromBytes(body, path)
	if err != nil {
		return Credential{}, fmt.Errorf("read remote auth file %s: %w", path, err)
	}
	return cred, nil
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`go test -v ./internal/remote -run TestLoadCredentialFromBytes`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add internal/remote/credentials.go internal/remote/credentials_test.go
git commit -m "refactor(remote): export LoadCredentialFromBytes helper"
```

---

### 任务 3：实现凭据池核心（状态机、目录加载、挑选算法、判据判定）

**文件：**
- 创建：`internal/remote/credential_pool.go`
- 测试：`internal/remote/credential_pool_test.go`

- [ ] **步骤 1：编写池基础能力的失败测试**

在 `internal/remote/credential_pool_test.go` 中编写：
```go
package remote

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func makeTestPoolDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	
	// account 1: expires later
	acc1 := `{
		"source": "acc1",
		"token_expire_time": "1999999999000",
		"auth": {
			"cosy_key": "k1", "encrypt_user_info": "u1", "user_id": "user_1", "machine_id": "m1"
		}
	}`
	// account 2: expires earlier
	acc2 := `{
		"source": "acc2",
		"token_expire_time": "1888888888000",
		"auth": {
			"cosy_key": "k2", "encrypt_user_info": "u2", "user_id": "user_2", "machine_id": "m2"
		}
	}`
	// corrupted account: should be skipped
	bad := `{"corrupted": true}`

	if err := os.WriteFile(filepath.Join(dir, "acc1.json"), []byte(acc1), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "acc2.json"), []byte(acc2), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "bad.json"), []byte(bad), 0600); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestPool_LoadAndOrder(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{PoolDir: dir})
	if err != nil {
		t.Fatalf("NewCredentialPool: %v", err)
	}

	// 1. Initial pick should be sticky to the first available (acc1 has longer expiry)
	c1, err := pool.Current(0, nil)
	if err != nil {
		t.Fatalf("Current(0): %v", err)
	}
	if c1.UserID != "user_1" {
		t.Errorf("got user %s, want user_1", c1.UserID)
	}

	// 2. Next attempt excluding user_1 should return user_2
	c2, err := pool.Current(1, map[string]bool{"user_1": true})
	if err != nil {
		t.Fatalf("Current(1): %v", err)
	}
	if c2.UserID != "user_2" {
		t.Errorf("got user %s, want user_2", c2.UserID)
	}

	// 3. Excluding both should return ErrPoolExhausted
	_, err = pool.Current(2, map[string]bool{"user_1": true, "user_2": true})
	if err != ErrPoolExhausted {
		t.Errorf("got error %v, want ErrPoolExhausted", err)
	}
}

func TestPool_InspectVerdicts(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{PoolDir: dir})
	if err != nil {
		t.Fatal(err)
	}

	// 200 -> OK
	if v := pool.Inspect("user_1", 200, []byte("ok")); v != VerdictOK {
		t.Errorf("got %v, want VerdictOK", v)
	}

	// 403 with quota message -> VerdictSwitch + Cooled
	v := pool.Inspect("user_1", 403, []byte(`{"message": "user daily limit exceeded"}`))
	if v != VerdictSwitch {
		t.Errorf("got %v, want VerdictSwitch", v)
	}

	// Now user_1 is cooled, Current(0) must return user_2
	c, err := pool.Current(0, nil)
	if err != nil {
		t.Fatal(err)
	}
	if c.UserID != "user_2" {
		t.Errorf("got user %s, want user_2 after user_1 cooled", c.UserID)
	}

	// 403 without recognized keyword -> VerdictSwitch, but not cooled
	v2 := pool.Inspect("user_2", 403, []byte(`{"message": "access denied"}`))
	if v2 != VerdictSwitch {
		t.Errorf("got %v, want VerdictSwitch", v2)
	}
	// user_2 should still be uncooled, but excluded in-flight
	excluded := map[string]bool{"user_2": true}
	_, err = pool.Current(1, excluded)
	if err != ErrPoolExhausted {
		t.Errorf("expected pool exhausted when all tried, got %v", err)
	}

	// 500 -> VerdictPropagate
	if v := pool.Inspect("user_2", 500, []byte("internal error")); v != VerdictPropagate {
		t.Errorf("got %v, want VerdictPropagate", v)
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`go test -v ./internal/remote -run "TestPool_LoadAndOrder|TestPool_InspectVerdicts"`
预期：FAIL（未实现 `NewCredentialPool`）

- [ ] **步骤 3：编写 credential_pool.go 核心实现**

创建 `internal/remote/credential_pool.go`：
```go
package remote

import (
	"bytes"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

var ErrPoolExhausted = errors.New("all credentials in pool are cooled or exhausted")

type PoolVerdict int

const (
	VerdictOK PoolVerdict = iota
	VerdictSwitch
	VerdictPropagate
)

type PoolConfig struct {
	PoolDir          string
	MaxSwitches      int
	ProbeEnabled     bool
	ProbeQuietMin    int
	ProbeIntervalMin int
}

type AccountState struct {
	Cred           Credential
	Cooled         bool
	CoolReason     string
	CooledUntil    time.Time
	LastFailedAt   time.Time
	LastSuccessAt  time.Time
	LastProbeAt    time.Time
	LastProbeError string
}

type AccountStatusDTO struct {
	UserID        string `json:"user_id"`
	Source        string `json:"source"`
	Cooled        bool   `json:"cooled"`
	CoolReason    string `json:"cool_reason,omitempty"`
	CooledUntil   string `json:"cooled_until,omitempty"`
	TokenExpireAt string `json:"token_expire_at"`
	LastProbeAt   string `json:"last_probe_at,omitempty"`
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
	cfg        PoolConfig
	mu         sync.RWMutex
	dirModTime time.Time
	accounts   map[string]*AccountState // keyed by user_id
	stickyUser string
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
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			log.Printf("[pool] skip unreadable credential %s: %v", path, err)
			continue
		}
		cred, err := LoadCredentialFromBytes(data, path)
		if err != nil {
			log.Printf("[pool] skip invalid credential %s: %v", path, err)
			continue
		}
		if existing, exists := newAccounts[cred.UserID]; exists {
			if cred.TokenExpireTime > existing.Cred.TokenExpireTime {
				existing.Cred = cred
			}
			continue
		}
		
		// Preserve cooling state if account was already loaded
		state := &AccountState{Cred: cred}
		if old, ok := p.accounts[cred.UserID]; ok {
			state.Cooled = old.Cooled
			state.CoolReason = old.CoolReason
			state.CooledUntil = old.CooledUntil
			state.LastFailedAt = old.LastFailedAt
			state.LastSuccessAt = old.LastSuccessAt
			state.LastProbeAt = old.LastProbeAt
			state.LastProbeError = old.LastProbeError
		}
		newAccounts[cred.UserID] = state
	}
	p.accounts = newAccounts
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

	// 1. Sticky preference on attempt 0
	if attempt == 0 && p.stickyUser != "" {
		if acc, ok := p.accounts[p.stickyUser]; ok {
			if !acc.Cooled && !isTokenExpired(acc.Cred, 5*time.Minute) && !inFlightExcluded[p.stickyUser] {
				return acc.Cred, nil
			}
		}
	}

	// 2. Select best candidate among uncooled, unexpired, non-excluded
	candidates := make([]*AccountState, 0, len(p.accounts))
	for uid, acc := range p.accounts {
		if inFlightExcluded[uid] {
			continue
		}
		if acc.Cooled {
			continue
		}
		if isTokenExpired(acc.Cred, 5*time.Minute) {
			continue
		}
		candidates = append(candidates, acc)
	}

	if len(candidates) == 0 {
		return Credential{}, ErrPoolExhausted
	}

	// Sort by TokenExpireTime descending
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].Cred.TokenExpireTime > candidates[j].Cred.TokenExpireTime
	})

	picked := candidates[0]
	p.stickyUser = picked.Cred.UserID
	return picked.Cred, nil
}

var (
	quotaKeywords = []string{"exceed", "quota", "limit", "每日", "额度", "上限", "配额"}
	authKeywords  = []string{"invalid token", "unauthorized", "未登录", "expire", "token is invalid"}
)

func (p *CredentialPool) Inspect(userID string, statusCode int, body []byte) PoolVerdict {
	p.mu.Lock()
	defer p.mu.Unlock()

	acc, ok := p.accounts[userID]
	if !ok {
		return VerdictPropagate
	}

	now := time.Now()
	if statusCode >= 200 && statusCode < 300 {
		acc.LastSuccessAt = now
		return VerdictOK
	}

	lowerBody := bytes.ToLower(body)

	// 429 Rate Limit
	if statusCode == 429 {
		acc.Cooled = true
		acc.CoolReason = "rate_limited"
		acc.CooledUntil = now.Add(15 * time.Minute)
		acc.LastFailedAt = now
		log.Printf("[pool] account %s rate limited (429); cooling for 15m", maskIdentifier(userID))
		return VerdictSwitch
	}

	// 401 or 403
	if statusCode == 401 || statusCode == 403 {
		acc.LastFailedAt = now
		for _, kw := range quotaKeywords {
			if bytes.Contains(lowerBody, []byte(kw)) {
				acc.Cooled = true
				acc.CoolReason = "daily_limit"
				acc.CooledUntil = nextLocalMidnight(now)
				log.Printf("[pool] account %s hit daily quota limit (status %d); cooling until midnight (%s); sample=%s",
					maskIdentifier(userID), statusCode, acc.CooledUntil.Format(time.RFC3339), truncate(string(body), 150))
				return VerdictSwitch
			}
		}
		for _, kw := range authKeywords {
			if bytes.Contains(lowerBody, []byte(kw)) {
				acc.Cooled = true
				acc.CoolReason = "auth_invalid"
				acc.CooledUntil = nextLocalMidnight(now)
				log.Printf("[pool] account %s auth invalid (status %d); cooling until midnight; re-login required; sample=%s",
					maskIdentifier(userID), statusCode, truncate(string(body), 150))
				return VerdictSwitch
			}
		}
		// 401/403 without matched keywords: switch without cooling
		log.Printf("[pool] account %s status %d without matched keywords; switching account without cooling; sample=%s",
			maskIdentifier(userID), statusCode, truncate(string(body), 150))
		return VerdictSwitch
	}

	// 5xx / 400 / 404 / etc.: propagate without touching pool
	return VerdictPropagate
}

func (p *CredentialPool) Summary() string {
	p.mu.RLock()
	defer p.mu.RUnlock()

	total := len(p.accounts)
	cooled := 0
	var earliestReset time.Time

	for _, acc := range p.accounts {
		if acc.Cooled {
			cooled++
			if earliestReset.IsZero() || acc.CooledUntil.Before(earliestReset) {
				earliestReset = acc.CooledUntil
			}
		}
	}
	active := total - cooled

	earliestStr := "none"
	if !earliestReset.IsZero() {
		earliestStr = earliestReset.Format(time.RFC3339)
	}

	return fmt.Sprintf("accounts=%d active=%d cooled=%d earliest_reset=%s probe=%t",
		total, active, cooled, earliestStr, p.cfg.ProbeEnabled)
}

func (p *CredentialPool) StatusDTO() PoolStatusDTO {
	p.mu.RLock()
	defer p.mu.RUnlock()

	var earliestReset time.Time
	accountsDTO := make([]AccountStatusDTO, 0, len(p.accounts))
	cooledCount := 0

	for _, acc := range p.accounts {
		if acc.Cooled {
			cooledCount++
			if earliestReset.IsZero() || acc.CooledUntil.Before(earliestReset) {
				earliestReset = acc.CooledUntil
			}
		}
		dto := AccountStatusDTO{
			UserID:        maskIdentifier(acc.Cred.UserID),
			Source:        filepath.Base(acc.Cred.Source),
			Cooled:        acc.Cooled,
			CoolReason:    acc.CoolReason,
			TokenExpireAt: time.UnixMilli(acc.Cred.TokenExpireTime).Format(time.RFC3339),
		}
		if acc.Cooled {
			dto.CooledUntil = acc.CooledUntil.Format(time.RFC3339)
		}
		if !acc.LastProbeAt.IsZero() {
			dto.LastProbeAt = acc.LastProbeAt.Format(time.RFC3339)
		}
		accountsDTO = append(accountsDTO, dto)
	}

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

func nextLocalMidnight(t time.Time) time.Time {
	year, month, day := t.Date()
	return time.Date(year, month, day+1, 0, 0, 0, 0, t.Location())
}

func isTokenExpired(cred Credential, buffer time.Duration) bool {
	if cred.TokenExpireTime <= 0 {
		return false
	}
	return time.Now().Add(buffer).After(time.UnixMilli(cred.TokenExpireTime))
}

func maskIdentifier(id string) string {
	if len(id) <= 6 {
		return "***"
	}
	return id[:3] + "..." + id[len(id)-3:]
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`go test -v ./internal/remote -run "TestPool_LoadAndOrder|TestPool_InspectVerdicts"`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add internal/remote/credential_pool.go internal/remote/credential_pool_test.go
git commit -m "feat(remote): add CredentialPool core and state machine"
```

---

### 任务 4：实现 D1 恢复探针调度器

**文件：**
- 修改：`internal/remote/credential_pool.go`
- 测试：`internal/remote/credential_pool_probe_test.go`

- [ ] **步骤 1：编写探针行为的单元测试（使用假执行器）**

创建 `internal/remote/credential_pool_probe_test.go`：
```go
package remote

import (
	"context"
	"testing"
	"time"
)

func TestPool_ProbeRecover(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{
		PoolDir:          dir,
		ProbeEnabled:     true,
		ProbeQuietMin:    0, // zero quiet time for test
		ProbeIntervalMin: 1,
	})
	if err != nil {
		t.Fatal(err)
	}

	// 1. Manually cool user_1
	pool.Inspect("user_1", 403, []byte("daily limit exceeded"))
	acc := pool.accounts["user_1"]
	if !acc.Cooled {
		t.Fatal("expected user_1 to be cooled")
	}

	// 2. Define a mock probe runner that succeeds
	probeFn := func(ctx context.Context, cred Credential) error {
		if cred.UserID == "user_1" {
			return nil // probe success
		}
		return errors.New("unexpected user")
	}

	// Run one probe round synchronously
	recovered := pool.ProbeOnce(context.Background(), probeFn)
	if !recovered {
		t.Errorf("expected probe to recover an account, got false")
	}

	pool.mu.RLock()
	isCooled := pool.accounts["user_1"].Cooled
	pool.mu.RUnlock()

	if isCooled {
		t.Errorf("expected user_1 to be uncooled after successful probe")
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`go test -v ./internal/remote -run TestPool_ProbeRecover`
预期：FAIL（`ProbeOnce` 未定义）

- [ ] **步骤 3：在 credential_pool.go 中实现探针调度与 ProbeOnce**

在 `internal/remote/credential_pool.go` 中追加：
```go
// ProbeFunc executes an isolated, minimal check using the given credential.
type ProbeFunc func(ctx context.Context, cred Credential) error

// ProbeOnce selects the earliest-cooled candidate that passed quiet duration, probes it once.
// Returns true if an account was successfully recovered.
func (p *CredentialPool) ProbeOnce(ctx context.Context, probe ProbeFunc) bool {
	p.mu.Lock()
	now := time.Now()
	var target *AccountState

	for _, acc := range p.accounts {
		if !acc.Cooled {
			continue
		}
		// Quiet duration check
		if now.Sub(acc.LastFailedAt) < time.Duration(p.cfg.ProbeQuietMin)*time.Minute {
			continue
		}
		if target == nil || acc.CooledUntil.Before(target.CooledUntil) {
			target = acc
		}
	}
	if target == nil {
		p.mu.Unlock()
		return false
	}
	cred := target.Cred
	p.mu.Unlock()

	// Probe under short timeout without holding lock
	probeCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	err := probe(probeCtx, cred)

	p.mu.Lock()
	defer p.mu.Unlock()
	target.LastProbeAt = time.Now()

	if err == nil {
		target.Cooled = false
		target.CoolReason = ""
		target.LastProbeError = ""
		log.Printf("[pool] probe succeeded for %s; account restored to active", maskIdentifier(cred.UserID))
		return true
	}

	target.LastProbeError = truncate(err.Error(), 150)
	log.Printf("[pool] probe failed for %s: %s; keeping cooled", maskIdentifier(cred.UserID), target.LastProbeError)
	return false
}

func (p *CredentialPool) StartProbeLoop(ctx context.Context, probe ProbeFunc) {
	if !p.cfg.ProbeEnabled {
		return
	}
	go func() {
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

func (p *CredentialPool) Close() {
	select {
	case <-p.stopCh:
	default:
		close(p.stopCh)
	}
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`go test -v ./internal/remote -run TestPool_ProbeRecover`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add internal/remote/credential_pool.go internal/remote/credential_pool_probe_test.go
git commit -m "feat(remote): add D1 probe scheduler to CredentialPool"
```

---

### 任务 5：改造 Client.Chat() 接入有界重试环与探针请求

**文件：**
- 修改：`internal/remote/client.go`
- 测试：`internal/remote/client_pool_test.go`

- [ ] **步骤 1：编写失败的客户端集成重试测试（使用 httptest 模拟 Qoder 上游）**

创建 `internal/remote/client_pool_test.go`：
```go
package remote

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestClient_Chat_PoolSwitchSuccess(t *testing.T) {
	dir := makeTestPoolDir(t)
	var callCount int32

	// Mock upstream server: first call 403 daily limit, second call 200 with SSE
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cnt := atomic.AddInt32(&callCount, 1)
		if cnt == 1 {
			w.WriteHeader(403)
			_, _ = w.Write([]byte(`{"code": "403", "message": "user daily limit exceed"}`))
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(200)
		_, _ = w.Write([]byte("data: {\"statusCodeValue\":200,\"body\":{\"choices\":[{\"delta\":{\"content\":\"hello from account 2\"}}]}}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer srv.Close()

	pool, err := NewCredentialPool(PoolConfig{PoolDir: dir})
	if err != nil {
		t.Fatal(err)
	}

	cli := New(Config{
		BaseURL:     srv.URL,
		Pool:        pool,
		CosyVersion: "1.1.28",
	})

	var collected string
	res, err := cli.Chat(context.Background(), ChatRequest{Prompt: "test"}, func(ev StreamEvent) {
		if ev.Kind == StreamKindText {
			collected += ev.Delta
		}
	})

	if err != nil {
		t.Fatalf("expected successful chat through switch, got: %v", err)
	}
	if !strings.Contains(collected, "hello from account 2") {
		t.Errorf("got %q, want delta containing hello from account 2", collected)
	}
	if atomic.LoadInt32(&callCount) != 2 {
		t.Errorf("expected 2 calls, got %d", atomic.LoadInt32(&callCount))
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`go test -v ./internal/remote -run TestClient_Chat_PoolSwitchSuccess`
预期：FAIL（`Config.Pool` 字段不存在）

- [ ] **步骤 3：在 client.go 中接入池、重写 Chat() 重试环，并实现 MinimalProbe**

修改 `internal/remote/client.go`：
1. 在 `Config` struct 增加 `Pool *CredentialPool`：
```go
type Config struct {
	BaseURL     string
	AuthFile    string
	ProxyURL    string
	CosyVersion string
	Timeout     time.Duration
	Pool        *CredentialPool
}
```
2. 在 `Client` struct 增加 `pool *CredentialPool` 并于 `New()` 中保存。
3. 增加 `MinimalProbe` 方法：
```go
func (c *Client) MinimalProbe(ctx context.Context, cred Credential) error {
	body, err := c.buildBody(newHexID(), ChatRequest{
		Prompt: "hi",
	})
	if err != nil {
		return err
	}
	headers, err := c.headers(cred, chatPath, body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.cfg.BaseURL+chatPath+chatQuery, strings.NewReader(body))
	if err != nil {
		return err
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
	if resp.StatusCode >= 400 {
		return fmt.Errorf("probe status %d: %s", resp.StatusCode, string(respBody))
	}
	return nil
}
```
4. 改造 `Chat()`：若 `c.pool == nil` 走旧逻辑；若非空则执行重试环：
```go
func (c *Client) Chat(ctx context.Context, request ChatRequest, onDelta func(StreamEvent)) (*ChatResult, error) {
	if c.pool == nil {
		return c.chatSingle(ctx, request, onDelta, c.cfg.AuthFile)
	}

	requestID := newHexID()
	body, err := c.buildBody(requestID, request)
	if err != nil {
		return nil, err
	}

	inFlightExcluded := make(map[string]bool)
	maxSwitches := c.pool.cfg.MaxSwitches
	var firstErr error

	for attempt := 0; attempt <= maxSwitches; attempt++ {
		cred, err := c.pool.Current(attempt, inFlightExcluded)
		if err != nil {
			if firstErr != nil {
				return nil, fmt.Errorf("%w (pool summary: %s)", firstErr, c.pool.Summary())
			}
			return nil, fmt.Errorf("%w (pool summary: %s)", err, c.pool.Summary())
		}
		inFlightExcluded[cred.UserID] = true

		headers, err := c.headers(cred, chatPath, body)
		if err != nil {
			return nil, err
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.cfg.BaseURL+chatPath+chatQuery, strings.NewReader(body))
		if err != nil {
			return nil, err
		}
		for k, v := range headers {
			req.Header.Set(k, v)
		}

		resp, err := c.client.Do(req)
		if err != nil {
			return nil, err
		}

		if resp.StatusCode >= 400 {
			respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
			resp.Body.Close()

			verdict := c.pool.Inspect(cred.UserID, resp.StatusCode, respBody)
			if firstErr == nil {
				firstErr = fmt.Errorf("remote chat status %d: %s", resp.StatusCode, truncate(string(respBody), 1000))
			}

			if verdict == VerdictSwitch && attempt < maxSwitches {
				log.Printf("[client] request failed with status %d on user %s; switching account (%d/%d)",
					resp.StatusCode, maskIdentifier(cred.UserID), attempt+1, maxSwitches)
				continue
			}
			return nil, fmt.Errorf("remote chat status %d: %s", resp.StatusCode, truncate(string(respBody), 1000))
		}

		// 2xx response: parse SSE stream
		defer resp.Body.Close()
		c.pool.Inspect(cred.UserID, resp.StatusCode, nil)

		var textBuilder strings.Builder
		var reasoningBuilder strings.Builder
		var streamErr error

		scanErr := scanSSE(resp.Body, func(event sseEvent) error {
			if event.Done {
				return nil
			}
			if event.Delta != "" {
				textBuilder.WriteString(event.Delta)
				if onDelta != nil {
					onDelta(StreamEvent{Kind: StreamKindText, Delta: event.Delta})
				}
			}
			if event.ReasoningDelta != "" {
				reasoningBuilder.WriteString(event.ReasoningDelta)
				if onDelta != nil {
					onDelta(StreamEvent{Kind: StreamKindReasoning, Delta: event.ReasoningDelta})
				}
			}
			return nil
		})
		if scanErr != nil {
			return nil, scanErr
		}

		return &ChatResult{
			Text:          textBuilder.String(),
			ReasoningText: reasoningBuilder.String(),
		}, nil
	}

	if firstErr != nil {
		return nil, firstErr
	}
	return nil, ErrPoolExhausted
}
```
*(同时保留 `chatSingle` 抽取的纯净旧代码供无池模式使用)*

- [ ] **步骤 4：运行测试验证通过**

运行：`go test -v ./internal/remote -run TestClient_Chat_PoolSwitchSuccess`
预期：PASS

- [ ] **步骤 5：Commit**

```bash
git add internal/remote/client.go internal/remote/client_pool_test.go
git commit -m "feat(remote): integrate CredentialPool bounded retry loop into Client.Chat"
```

---

### 任务 6：Service、HTTP API 与配置透传 (`/v1/pool/status`)

**文件：**
- 修改：`internal/service/service.go`
- 修改：`internal/httpapi/server.go`
- 修改：`cmd/qodercn-gateway/main.go`
- 修改：`config.example.json`
- 测试：`internal/httpapi/server_pool_test.go`

- [ ] **步骤 1：编写 /v1/pool/status 的端点测试**

创建 `internal/httpapi/server_pool_test.go`：
```go
package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"qodercn-gateway/internal/remote"
	"qodercn-gateway/internal/service"
)

func TestServer_PoolStatusEndpoint(t *testing.T) {
	svc := service.New(service.Config{})
	server := New(ServerOptions{
		Service: svc,
	})

	req := httptest.NewRequest(http.MethodGet, "/v1/pool/status", nil)
	rec := httptest.NewRecorder()
	server.http.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d", rec.Code)
	}

	var payload remote.PoolStatusDTO
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("failed to parse json response: %v", err)
	}
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`go test -v ./internal/httpapi -run TestServer_PoolStatusEndpoint`
预期：FAIL（返回 404 或未注册该端点）

- [ ] **步骤 3：在 service、httpapi 和 main.go 中连接配置与路由**

1. **`internal/service/service.go`**：
   在 `Config` 中加入池相关字段：
   ```go
   RemoteAuthPoolDir string
   RemoteAuthPool    remote.PoolConfig
   ```
   在 `Service` struct 中增加 `pool *remote.CredentialPool`，并在 `remoteClientLocked()` 中：
   ```go
   if s.cfg.RemoteAuthPoolDir != "" && s.pool == nil {
       pCfg := s.cfg.RemoteAuthPool
       pCfg.PoolDir = s.cfg.RemoteAuthPoolDir
       if p, err := remote.NewCredentialPool(pCfg); err == nil {
           s.pool = p
           // Start background probe loop
           s.pool.StartProbeLoop(context.Background(), func(ctx context.Context, cred remote.Credential) error {
               return s.remoteClient.MinimalProbe(ctx, cred)
           })
       } else {
           log.Printf("[service] failed to initialize credential pool %s: %v", s.cfg.RemoteAuthPoolDir, err)
       }
   }
   ```
   增加对外只读方法 `PoolStatus() remote.PoolStatusDTO`。

2. **`internal/httpapi/server.go`**：
   在 `New()` 的 mux 注册中增加：
   ```go
   mux.HandleFunc("/v1/pool/status", s.handlePoolStatus)
   ```
   实现 `handlePoolStatus`：
   ```go
   func (s *Server) handlePoolStatus(w http.ResponseWriter, r *http.Request) {
       if r.Method != http.MethodGet {
           s.writeMethodNotAllowed(w)
           return
       }
       dto := s.svc.PoolStatus()
       s.writeJSON(w, http.StatusOK, dto)
   }
   ```
   在 `handleOpenAIChatCompletions` 遇到错误时，追加 `X-QoderCN-Pool` 响应头：
   ```go
   if poolSummary := s.svc.PoolSummary(); poolSummary != "" {
       w.Header().Set("X-QoderCN-Pool", poolSummary)
   }
   ```

3. **`cmd/qodercn-gateway/main.go`**：
   在 `fileConfig` 中加入：
   ```go
   RemoteAuthPoolDir string `json:"remote_auth_pool_dir"`
   RemoteAuthPool    struct {
       MaxSwitches      int  `json:"max_switches"`
       ProbeEnabled     *bool `json:"probe_enabled"`
       ProbeQuietMin    int  `json:"probe_quiet_min"`
       ProbeIntervalMin int  `json:"probe_interval_min"`
   } `json:"remote_auth_pool"`
   ```
   在 flags 中支持 `--remote-auth-pool-dir`，并支持环境变量 `QODERCN_REMOTE_AUTH_POOL_DIR`。

4. **`config.example.json`**：
   写入完整的池配置注释与范例。

- [ ] **步骤 4：运行测试验证通过**

运行：`go test -v ./internal/httpapi -run TestServer_PoolStatusEndpoint`
预期：PASS

- [ ] **步骤 5：运行全局测试套件**

运行：`go test -race ./...`
预期：PASS（全库所有单元测试与集成测试通过，无数据竞态）

- [ ] **步骤 6：Commit**

```bash
git add internal/service/service.go internal/httpapi/server.go internal/httpapi/server_pool_test.go cmd/qodercn-gateway/main.go config.example.json
git commit -m "feat(httpapi): add /v1/pool/status endpoint and pool configuration wiring"
```

---

### 任务 7：真实环境 8096 端口端到端黑盒验证

**文件：**
- 测试脚本：`qodercn-gateway-pool/test_e2e_pool.sh`
- 调试目录：`qodercn-gateway-pool/test_pool/`

- [ ] **步骤 1：准备测试账号池文件**

在 `qodercn-gateway-pool/test_pool/` 下创建 2 个测试号（1 个从真实 `~/.qoder-cn/.auth/user` 转换，另一个放模拟/备用凭据）。

- [ ] **步骤 2：启动 8096 独立网关进程**

```bash
cd /Users/fupingguo/fuhaha_workspace/ali-tools/qodercn-gateway-pool
go run ./cmd/qodercn-gateway --port 8096 --remote-auth-pool-dir ./test_pool &
PID=$!
sleep 2
```

- [ ] **步骤 3：验证 /v1/pool/status 端点响应**

```bash
curl -s http://127.0.0.1:8096/v1/pool/status | jq .
```
预期：HTTP 200，返回 `total_accounts >= 2`，`active_accounts >= 2`。

- [ ] **步骤 4：发起一发真实对话请求**

```bash
curl -s http://127.0.0.1:8096/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen3.8-Flash", "messages": [{"role": "user", "content": "ping"}], "stream": false}' | jq .
```
预期：正常获得模型回复，同时 8095 网关进程完全不受任何影响。

- [ ] **步骤 5：清理测试进程**

```bash
kill $PID
```

- [ ] **步骤 6：Commit 验证脚本与文档**

```bash
git add docs/superpowers/plans/
git commit -m "docs: complete implementation plan for qoder account pool"
```
