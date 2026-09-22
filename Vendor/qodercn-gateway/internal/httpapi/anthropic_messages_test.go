package httpapi

import (
	"encoding/json"
	"testing"
)

// TestNormalizeAnthropicRequest_PutsToolResultsBeforeSameTurnText pins the fix for
// the DeepSeek "insufficient tool messages following tool_calls message" rejection.
//
// OpenAI-shaped upstreams require the tool messages answering an assistant's
// tool_calls to come IMMEDIATELY after it. Anthropic clients routinely put a text
// block and tool_result blocks in the same user turn; emitting that text as a
// role:"user" message before the tool turns wedged a non-tool message into the
// gap and every such request failed upstream (worked on Qwen3.8-Flash, which
// tolerates it, and broke on DeepSeek, which does not).
func TestNormalizeAnthropicRequest_PutsToolResultsBeforeSameTurnText(t *testing.T) {
	raw := `{
		"model": "DeepSeek-Flash",
		"max_tokens": 100,
		"messages": [
			{"role": "user", "content": "what is 25*4?"},
			{"role": "assistant", "content": [
				{"type": "tool_use", "id": "toolu_01AAA", "name": "calc", "input": {"expr": "25*4"}}
			]},
			{"role": "user", "content": [
				{"type": "text", "text": "here is the result"},
				{"type": "tool_result", "tool_use_id": "toolu_01AAA", "content": "100"}
			]}
		]
	}`

	var req anthropicRequest
	if err := json.Unmarshal([]byte(raw), &req); err != nil {
		t.Fatalf("failed to unmarshal test request: %v", err)
	}

	chatReq, err := normalizeAnthropicRequest(req)
	if err != nil {
		t.Fatalf("normalizeAnthropicRequest failed: %v", err)
	}

	// Expected order: user(text) → assistant(tool_calls) → tool(result) → user(text).
	// The tool message must directly follow the assistant message that carries the
	// matching tool_calls.
	if len(chatReq.Messages) != 4 {
		t.Fatalf("expected 4 normalized messages, got %d: %+v", len(chatReq.Messages), chatReq.Messages)
	}

	if chatReq.Messages[1].Role != "assistant" || len(chatReq.Messages[1].ToolCalls) != 1 {
		t.Fatalf("message[1] should be the assistant turn carrying tool_calls, got %+v", chatReq.Messages[1])
	}

	toolMsg := chatReq.Messages[2]
	if toolMsg.Role != "tool" {
		t.Fatalf("message[2] must be the tool result immediately after tool_calls, got role %q (order broken)", toolMsg.Role)
	}
	if toolMsg.ToolCallID != "toolu_01AAA" {
		t.Errorf("tool message paired to %q, want toolu_01AAA", toolMsg.ToolCallID)
	}

	// The same turn's text must still be preserved, just moved after the tool turn.
	last := chatReq.Messages[3]
	if last.Role != "user" || last.Text != "here is the result" {
		t.Errorf("same-turn text should survive after the tool turn, got role=%q text=%q", last.Role, last.Text)
	}
}

// A user turn with no tool results is unaffected: plain text still normalizes to a
// single user message.
func TestNormalizeAnthropicRequest_PlainUserTurnUnchanged(t *testing.T) {
	raw := `{
		"model": "DeepSeek-Flash",
		"max_tokens": 100,
		"messages": [
			{"role": "user", "content": [{"type": "text", "text": "just text"}]}
		]
	}`

	var req anthropicRequest
	if err := json.Unmarshal([]byte(raw), &req); err != nil {
		t.Fatalf("failed to unmarshal test request: %v", err)
	}

	chatReq, err := normalizeAnthropicRequest(req)
	if err != nil {
		t.Fatalf("normalizeAnthropicRequest failed: %v", err)
	}
	if len(chatReq.Messages) != 1 {
		t.Fatalf("expected 1 message, got %d: %+v", len(chatReq.Messages), chatReq.Messages)
	}
	if chatReq.Messages[0].Role != "user" || chatReq.Messages[0].Text != "just text" {
		t.Errorf("plain user turn changed shape: %+v", chatReq.Messages[0])
	}
}