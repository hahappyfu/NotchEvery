package remote

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
)

func TestClient_Chat_PoolSwitchSuccess(t *testing.T) {
	poolDir := t.TempDir()
	cred1Path := filepath.Join(poolDir, "cred1.json")
	cred2Path := filepath.Join(poolDir, "cred2.json")

	acc1 := `{
		"source": "acc1",
		"token_expire_time": "1999999999000",
		"auth": {
			"cosy_key": "k1", "encrypt_user_info": "u1", "user_id": "user_1", "machine_id": "m1"
		}
	}`
	acc2 := `{
		"source": "acc2",
		"token_expire_time": "1888888888000",
		"auth": {
			"cosy_key": "k2", "encrypt_user_info": "u2", "user_id": "user_2", "machine_id": "m2"
		}
	}`
	if err := os.WriteFile(cred1Path, []byte(acc1), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cred2Path, []byte(acc2), 0o600); err != nil {
		t.Fatal(err)
	}

	var reqCount int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cnt := atomic.AddInt32(&reqCount, 1)
		if cnt == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			_, _ = w.Write([]byte(`{"code":"USER_FLOW_LIMIT","message":"Rate limit exceeded"}`))
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = fmt.Fprint(w, "data: {\"statusCodeValue\":200,\"body\":\"{\\\"choices\\\":[{\\\"delta\\\":{\\\"content\\\":\\\"hello from user_2\\\"}}]}\"}\n\n")
		_, _ = fmt.Fprint(w, "data: {\"statusCodeValue\":200,\"body\":\"{\\\"choices\\\":[{\\\"finish_reason\\\":\\\"stop\\\"}],\\\"usage\\\":{\\\"prompt_tokens\\\":10,\\\"completion_tokens\\\":5,\\\"total_tokens\\\":15}}\"}\n\n")
		_, _ = fmt.Fprint(w, "data: [DONE]\n\n")
	}))
	defer server.Close()

	poolCfg := PoolConfig{
		PoolDir: poolDir,
	}
	pool, err := NewCredentialPool(poolCfg)
	if err != nil {
		t.Fatalf("failed to create pool: %v", err)
	}

	client := New(Config{BaseURL: server.URL})
	client.SetPool(pool)

	var streamedText string
	res, err := client.Chat(context.Background(), ChatRequest{
		Prompt: "hi",
	}, func(e StreamEvent) {
		if e.Kind == StreamKindText {
			streamedText += e.Delta
		}
	})
	if err != nil {
		t.Fatalf("expected chat to succeed with pool switch, got: %v", err)
	}
	if res == nil || res.Text != "hello from user_2" {
		t.Fatalf("unexpected res text: %v", res)
	}
	if streamedText != "hello from user_2" {
		t.Fatalf("unexpected streamedText: %s", streamedText)
	}
	if atomic.LoadInt32(&reqCount) != 2 {
		t.Fatalf("expected 2 requests, got %d", reqCount)
	}
	// The usage log attributes a call via CredentialUser. An empty value here
	// would make the acct= field silently useless, and Source alone cannot tell
	// accounts apart (several pool members share one Source).
	if res.CredentialUser != "user_2" {
		t.Errorf("CredentialUser = %q, want user_2 — the account that actually served the call", res.CredentialUser)
	}
}
