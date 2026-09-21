package remote

import (
	"errors"
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
	// account 3: expired (5 min buffer)
	acc3 := `{
		"source": "acc3",
		"token_expire_time": "1000000000000",
		"auth": {
			"cosy_key": "k3", "encrypt_user_info": "u3", "user_id": "user_3", "machine_id": "m3"
		}
	}`

	_ = os.WriteFile(filepath.Join(dir, "acc1.json"), []byte(acc1), 0644)
	_ = os.WriteFile(filepath.Join(dir, "acc2.json"), []byte(acc2), 0644)
	_ = os.WriteFile(filepath.Join(dir, "acc3.json"), []byte(acc3), 0644)
	return dir
}

func TestPool_LoadAndOrder(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{

		PoolDir: dir,
	})
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	// 1. First attempt: should pick acc1 (expire time 1999999999000 > 1888888888000)
	c1, err := pool.Current(0, nil)
	if err != nil {
		t.Fatalf("Current(0) failed: %v", err)
	}
	if c1.UserID != "user_1" {
		t.Errorf("got user %s, want user_1", c1.UserID)
	}

	// 2. Next attempt excluding user_1: should pick acc2
	c2, err := pool.Current(1, map[string]bool{"user_1": true})
	if err != nil {
		t.Fatalf("Current(1) failed: %v", err)
	}
	if c2.UserID != "user_2" {
		t.Errorf("got user %s, want user_2", c2.UserID)
	}

	// 3. Next attempt excluding both: acc3 expired, should return ErrPoolExhausted
	_, err = pool.Current(2, map[string]bool{"user_1": true, "user_2": true})
	if err != ErrPoolExhausted {
		t.Errorf("got error %v, want ErrPoolExhausted", err)
	}
}

func TestPool_InspectVerdicts(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{

		PoolDir: dir,
	})
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	// 1. Success verdict
	if v := pool.Inspect("user_1", 200, []byte("ok")); v != VerdictOK {
		t.Errorf("got %v, want VerdictOK", v)
	}

	// 2. Daily limit 403 verdict
	quotaBody := []byte(`{"error": "daily quota exceed"}`)
	if v := pool.Inspect("user_1", 403, quotaBody); v != VerdictSwitch {
		t.Errorf("got %v, want VerdictSwitch", v)
	}

	// user_1 should now be cooled; Current(0) should return user_2
	c, err := pool.Current(0, nil)
	if err != nil {
		t.Fatalf("Current(0) after cool failed: %v", err)
	}
	if c.UserID != "user_2" {
		t.Errorf("got user %s, want user_2 after user_1 cooled", c.UserID)
	}

	// 3. Rate limit 429 verdict
	if v2 := pool.Inspect("user_2", 429, []byte("too many requests")); v2 != VerdictSwitch {
		t.Errorf("got %v, want VerdictSwitch", v2)
	}

	// Both active cooled, should return ErrPoolExhausted
	_, err = pool.Current(0, nil)
	if err != ErrPoolExhausted {
		t.Errorf("expected pool exhausted when all tried, got %v", err)
	}

	// 4. Server error 500 should propagate
	if v := pool.Inspect("user_2", 500, []byte("internal error")); v != VerdictPropagate {
		t.Errorf("got %v, want VerdictPropagate", v)
	}
}

// TestPool_InspectQueueDoesNotCool covers the global model queue: the free tier
// (Qwen3.8-Flash / qfmodel) answers 403 with isQueued while the account itself is
// healthy and every account shares the same backlog. Cooling here took all five
// real accounts offline until midnight on 2026-09-20, so this stays a regression
// guard.
func TestPool_InspectQueueDoesNotCool(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{PoolDir: dir})
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	// Verbatim body returned by gateway.qoder.com.cn for qfmodel.
	queueBody := []byte(`{"code":"403","message":"{\"code\":\"10605\",\"message\":\"{\\\"isQueued\\\":true,\\\"modelKey\\\":\\\"qfmodel\\\",\\\"queueCount\\\":7633,\\\"queueType\\\":\\\"p3\\\",\\\"retryAfterSeconds\\\":30,\\\"serviceAvailable\\\":true,\\\"waitTime\\\":232}\"}"}`)

	got := pool.Inspect("user_1", 403, queueBody)
	if got != VerdictPropagate {
		t.Errorf("queue verdict = %v, want VerdictPropagate", got)
	}

	if acc := pool.accounts["user_1"]; acc.Cooled {
		t.Errorf("queue cooled the account (reason %q); the queue is global and the account is healthy", acc.CoolReason)
	}

	// A real per-account daily limit must still cool, and must not be mistaken
	// for a queue.
	limitBody := []byte(`{"code":"110","message":"Billing daily count exceeded"}`)
	if got := pool.Inspect("user_1", 403, limitBody); got != VerdictSwitch {
		t.Errorf("daily-limit verdict = %v, want VerdictSwitch", got)
	}
	if acc := pool.accounts["user_1"]; !acc.Cooled || acc.CoolReason != "daily_limit" {
		t.Errorf("daily limit not cooled correctly: cooled=%v reason=%q", acc.Cooled, acc.CoolReason)
	}
}

// TestQueueRetryDelay covers reading the delay out of a queue signal. The payload
// is JSON nested inside JSON inside JSON, so the quotes arrive at differing
// escape depths — this parses the error text the client actually sees.
func TestQueueRetryDelay(t *testing.T) {
	verbatim := errors.New(`remote sse status 403: {"code":"403","message":"{\"code\":\"10605\",\"message\":\"{\\\"isQueued\\\":true,\\\"modelKey\\\":\\\"qfmodel\\\",\\\"queueCount\\\":7633,\\\"queueType\\\":\\\"p3\\\",\\\"retryAfterSeconds\\\":30,\\\"serviceAvailable\\\":true,\\\"waitTime\\\":232}\"}"}`)

	got, ok := queueRetryDelay(verbatim)
	if !ok {
		t.Fatal("queueRetryDelay did not recognise a queue signal")
	}
	if want := 30 * time.Second; got.RetryAfter != want {
		t.Errorf("RetryAfter = %v, want %v", got.RetryAfter, want)
	}
	// waitTime is what the caller budgets against, so it must survive parsing
	// even though it sits beside retryAfterSeconds at the same escape depth.
	if want := 232 * time.Second; got.WaitTime != want {
		t.Errorf("WaitTime = %v, want %v", got.WaitTime, want)
	}
	if want := 7633; got.QueueCount != want {
		t.Errorf("QueueCount = %d, want %d", got.QueueCount, want)
	}
	if want := "qfmodel"; got.ModelKey != want {
		t.Errorf("ModelKey = %q, want %q", got.ModelKey, want)
	}

	// Missing retryAfterSeconds must still count as queued, on the default wait,
	// and must report no WaitTime so the caller falls back to its own ceiling.
	noDelay := errors.New(`remote sse status 403: {"code":"10605","message":"{\"isQueued\":true}"}`)
	got, ok = queueRetryDelay(noDelay)
	if !ok {
		t.Fatal("queue signal without an explicit delay was not recognised")
	}
	if want := 30 * time.Second; got.RetryAfter != want {
		t.Errorf("fallback delay = %v, want %v", got.RetryAfter, want)
	}
	if got.WaitTime != 0 {
		t.Errorf("WaitTime = %v, want 0 when the upstream did not report one", got.WaitTime)
	}

	// A real per-account limit must not be mistaken for a queue.
	if _, ok := queueRetryDelay(errors.New(`remote sse status 403: {"code":"110","message":"Billing daily count exceeded"}`)); ok {
		t.Error("daily billing limit treated as a retryable queue")
	}
}
