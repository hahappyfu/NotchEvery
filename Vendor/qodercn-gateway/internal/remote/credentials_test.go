package remote

import (
	"strings"
	"testing"
	"time"
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

// The two login sources disagree on the epoch unit: the QoderCN CLI cache
// hands over expireTime in SECONDS, the legacy IDE cache in MILLISECONDS.
// TokenExpireTime is consumed as milliseconds everywhere (IsExpired, the
// deploy/export formatter, the pool pick policy), so parsing must normalize
// rather than store whatever the source happened to use.
func TestParseExpire_NormalizesSecondsToMilliseconds(t *testing.T) {
	// 2026-10-22, as handed over by the CLI login cache (seconds).
	const seconds = int64(1792681259)
	got := parseExpire("1792681259")
	if want := seconds * 1000; got != want {
		t.Errorf("parseExpire(seconds) = %d, want %d (must be milliseconds)", got, want)
	}

	// Same instant as milliseconds must pass through untouched — converting
	// twice would push the expiry ~55,000 years out.
	if got := parseExpire("1792681259000"); got != seconds*1000 {
		t.Errorf("parseExpire(milliseconds) = %d, want %d (must not re-scale)", got, seconds*1000)
	}

	// Missing/unparsable values stay zero so callers can treat them as "unknown".
	if got := parseExpire(""); got != 0 {
		t.Errorf("parseExpire(\"\") = %d, want 0", got)
	}
}

func TestParseExpireAny_NormalizesEverySourceType(t *testing.T) {
	const seconds = int64(1792681259)
	const ms = seconds * 1000
	cases := []struct {
		name  string
		input any
		want  int64
	}{
		{"string seconds (CLI login cache)", "1792681259", ms},
		{"string milliseconds (legacy IDE cache)", "1792681259000", ms},
		{"float64 seconds (json.Number path)", float64(seconds), ms},
		{"float64 milliseconds", float64(ms), ms},
		{"int64 seconds", seconds, ms},
		{"int seconds", int(seconds), ms},
		{"missing", nil, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := parseExpireAny(tc.input); got != tc.want {
				t.Errorf("parseExpireAny(%v) = %d, want %d", tc.input, got, tc.want)
			}
		})
	}
}

// The user-visible symptom: a credential whose source reported expiry in
// seconds was declared "already expired" by the export command, which printed
// "token expire at: 1970-01-22" for a token actually valid until 2026-10-22.
func TestIsExpired_SecondsSourcedTokenIsNotExpired(t *testing.T) {
	cred := Credential{TokenExpireTime: parseExpire("1792681259")}
	if IsExpired(cred, 0) {
		t.Errorf("token expiring %s reported as expired (TokenExpireTime=%d)",
			time.UnixMilli(cred.TokenExpireTime).Format(time.RFC3339), cred.TokenExpireTime)
	}

	// A genuinely past deadline must still be caught.
	past := Credential{TokenExpireTime: time.Now().Add(-time.Hour).UnixMilli()}
	if !IsExpired(past, 0) {
		t.Error("a token that expired an hour ago must still report expired")
	}
}
