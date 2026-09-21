package remote

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestPool_ProbeRecover(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{
		PoolDir:          dir,
		ProbeEnabled:     true,
		ProbeQuietMin:    1,
		ProbeIntervalMin: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	probeFn := func(ctx context.Context, cred Credential) error {
		if cred.UserID == "user_1" {
			return nil
		}
		return errors.New("unexpected user")
	}

	// Cool user_1 on a real daily limit.
	pool.Inspect("user_1", 403, []byte(`{"code":"110","message":"Billing daily count exceeded"}`))
	if got := pool.Status().CooledAccounts; got != 1 {
		t.Fatalf("cooled accounts after limit = %d, want 1", got)
	}

	// Still inside the quiet window: a freshly cooled account must not be probed,
	// otherwise a daily limit gets re-attacked every tick.
	if pool.ProbeOnce(context.Background(), probeFn) {
		t.Fatal("ProbeOnce ran inside the quiet window")
	}
	if got := pool.Status().CooledAccounts; got != 1 {
		t.Fatalf("quiet-window probe changed state: cooled=%d, want 1", got)
	}

	// Backdate past the quiet window; the probe now runs and recovers the account.
	pool.mu.Lock()
	pool.accounts["user_1"].LastFailedAt = time.Now().Add(-2 * time.Minute)
	pool.mu.Unlock()

	if !pool.ProbeOnce(context.Background(), probeFn) {
		t.Fatal("ProbeOnce did not recover an account once the quiet window passed")
	}
	if got := pool.Status().CooledAccounts; got != 0 {
		t.Errorf("cooled accounts after successful probe = %d, want 0", got)
	}
}

// TestPool_ProbeFailureKeepsCooled covers the other half: a probe that still hits
// the limit must leave the account offline rather than bounce it back into the
// rotation.
func TestPool_ProbeFailureKeepsCooled(t *testing.T) {
	dir := makeTestPoolDir(t)
	pool, err := NewCredentialPool(PoolConfig{PoolDir: dir, ProbeQuietMin: 1})
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	pool.Inspect("user_1", 403, []byte(`{"code":"110","message":"Billing daily count exceeded"}`))
	pool.mu.Lock()
	pool.accounts["user_1"].LastFailedAt = time.Now().Add(-2 * time.Minute)
	pool.mu.Unlock()

	if pool.ProbeOnce(context.Background(), func(context.Context, Credential) error {
		return errors.New(`remote sse status 403: {"code":"110","message":"Billing daily count exceeded"}`)
	}) {
		t.Error("failed probe reported a recovery")
	}
	if got := pool.Status().CooledAccounts; got != 1 {
		t.Errorf("cooled accounts after failed probe = %d, want 1", got)
	}
}
