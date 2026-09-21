package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"qodercn-gateway/internal/service"
)

func TestServer_PoolStatusEndpoint(t *testing.T) {
	tempDir := t.TempDir()
	credJSON := `{
		"source": "acc1",
		"token_expire_time": "1999999999000",
		"auth": {
			"cosy_key": "k1",
			"encrypt_user_info": "u1",
			"user_id": "user_12345",
			"machine_id": "m1"
		}
	}`
	if err := os.WriteFile(filepath.Join(tempDir, "acc1.json"), []byte(credJSON), 0644); err != nil {
		t.Fatalf("failed to write test cred file: %v", err)
	}

	svc := service.New(service.Config{
		RemoteAuthPoolDir: tempDir,
	})
	srv := NewServer("", svc)

	req := httptest.NewRequest(http.MethodGet, "/v1/pool/status", nil)
	rec := httptest.NewRecorder()

	srv.http.Handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to unmarshal response: %v", err)
	}

	totalAccounts, ok := resp["total_accounts"]
	if !ok {
		t.Fatalf("expected total_accounts field in response, got %v", resp)
	}
	if total, ok := totalAccounts.(float64); !ok || int(total) != 1 {
		t.Errorf("expected total_accounts = 1, got %v", totalAccounts)
	}
}
