# AGENTS.md

qodercn-gateway — a lightweight, remote-only proxy that re-exposes the QoderCN
Remote API through OpenAI/Anthropic-compatible HTTP endpoints.

## Commands

```bash
go build ./...            # build
go vet ./...              # vet
go test -race ./...       # test
gofmt -w cmd internal     # format
go run ./cmd/qodercn-gateway --port 8096
```

## Architecture

- `cmd/qodercn-gateway/` — entry point, flags/config/env plumbing
- `internal/httpapi/` — HTTP API layer (OpenAI + Anthropic routing); optional
  server-side tool injection isolated in `servertools_*.go` behind a one-line
  seam in each chat handler
- `internal/remote/` — QoderCN Remote API client: cosy request signing, SSE
  chat, image search/gen, credential loading. `credential_pool.go` owns the
  account pool (member scan, two-state cooldown, pick order, recovery probe).
- `internal/service/` — request orchestration (prompt build, streaming, output limiter)
- `internal/tooltypes/` — shared tool data types + request-side extractors
- `internal/deploy/` — credential / server-bundle export

## Conventions

- Remote-only and dependency-free (Go stdlib): keep `go.mod` without a `require`
  block. Do not reintroduce a local IPC/IDE transport, a desktop GUI, or
  multi-model fallback. **Account fallback is not model fallback:** the pool
  retries the *same* model on a *different* credential when one account hits its
  daily limit. Falling back to a different model remains out of scope.
- Pooling touches `Chat()` only. `FetchQuota`, `ListModels`, `WebSearch`,
  `ImageSearch`, `GenerateImage`, `PolishText` and `deploy/server_bundle.go`
  keep single-credential `LoadCredential` on purpose — none of them spend chat
  quota, so rotating there would burn accounts for nothing.
- Never cool an account on a `isQueued` response. That is the upstream's global
  model queue (free tier), shared by every account, so rotating cannot help and
  the credential itself is healthy.
- The gateway uses native function-calling; there is no prompt-injection tool
  emulation. `EmulatesTextTools` is always false.
- Pin `remote_base_url` to `https://gateway.qoder.com.cn` in config. The default
  (`lingma.alibabacloud.com` in `client.go`) is the legacy Tongyi Lingma host and
  serves 4 models instead of 14.
- Reply to the user in Chinese; keep code comments in English.
