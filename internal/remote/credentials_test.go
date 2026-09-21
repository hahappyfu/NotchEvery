package remote

import (
	"strings"
	"testing"
)

func TestLoadCredentialFromBytes_Valid(t *testing.T) {
	validJSON := `{
		"source": "custom_test_source",
		"token_expire_time": "1700000000000",
		"auth": {
			"cosy_key": "test_cosy_key",
			"encrypt_user_info": "test_encrypt_user_info",
			"user_id": "test_user_id",
			"machine_id": "test_machine_id",
			"access_token": "test_access_token"
		}
	}`

	cred, err := LoadCredentialFromBytes([]byte(validJSON), "fallback_source")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if cred.CosyKey != "test_cosy_key" {
		t.Errorf("expected CosyKey 'test_cosy_key', got '%s'", cred.CosyKey)
	}
	if cred.EncryptUserInfo != "test_encrypt_user_info" {
		t.Errorf("expected EncryptUserInfo 'test_encrypt_user_info', got '%s'", cred.EncryptUserInfo)
	}
	if cred.UserID != "test_user_id" {
		t.Errorf("expected UserID 'test_user_id', got '%s'", cred.UserID)
	}
	if cred.MachineID != "test_machine_id" {
		t.Errorf("expected MachineID 'test_machine_id', got '%s'", cred.MachineID)
	}
	if cred.AccessToken != "test_access_token" {
		t.Errorf("expected AccessToken 'test_access_token', got '%s'", cred.AccessToken)
	}
	if cred.Source != "custom_test_source" {
		t.Errorf("expected Source 'custom_test_source', got '%s'", cred.Source)
	}
	if cred.TokenExpireTime != 1700000000000 {
		t.Errorf("expected TokenExpireTime 1700000000000, got %d", cred.TokenExpireTime)
	}

	// Test fallback source
	jsonWithoutSource := `{
		"auth": {
			"cosy_key": "test_cosy_key",
			"encrypt_user_info": "test_encrypt_user_info",
			"user_id": "test_user_id",
			"machine_id": "test_machine_id"
		}
	}`
	credFallback, err := LoadCredentialFromBytes([]byte(jsonWithoutSource), "fallback_source")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if credFallback.Source != "fallback_source" {
		t.Errorf("expected Source 'fallback_source', got '%s'", credFallback.Source)
	}
}

func TestLoadCredentialFromBytes_Invalid(t *testing.T) {
	tests := []struct {
		name        string
		body        []byte
		errContains string
	}{
		{
			name:        "invalid json",
			body:        []byte(`{not valid json}`),
			errContains: "parse remote auth file",
		},
		{
			name: "missing cosy_key",
			body: []byte(`{
				"auth": {
					"encrypt_user_info": "test",
					"user_id": "test",
					"machine_id": "test"
				}
			}`),
			errContains: "remote credential missing cosy_key",
		},
		{
			name: "missing encrypt_user_info",
			body: []byte(`{
				"auth": {
					"cosy_key": "test",
					"user_id": "test",
					"machine_id": "test"
				}
			}`),
			errContains: "remote credential missing encrypt_user_info",
		},
		{
			name: "missing user_id",
			body: []byte(`{
				"auth": {
					"cosy_key": "test",
					"encrypt_user_info": "test",
					"machine_id": "test"
				}
			}`),
			errContains: "remote credential missing user_id",
		},
		{
			name: "missing machine_id",
			body: []byte(`{
				"auth": {
					"cosy_key": "test",
					"encrypt_user_info": "test",
					"user_id": "test"
				}
			}`),
			errContains: "remote credential missing machine_id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := LoadCredentialFromBytes(tt.body, "fallback")
			if err == nil {
				t.Fatalf("expected error containing '%s', got nil", tt.errContains)
			}
			if !strings.Contains(err.Error(), tt.errContains) {
				t.Errorf("expected error containing '%s', got '%v'", tt.errContains, err)
			}
		})
	}
}
