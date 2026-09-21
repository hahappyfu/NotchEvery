#!/bin/bash
# 编译 vendor 的 qodercn-gateway Go 源码到 Xcode 产物目录。
# 由 NotchDrop target 的 "Build Qoder Gateway" pre-build phase 调用。
# 约束：脚本内不出现证书名 / codesign / cp 进 bundle —— 签名交给 Xcode 打包流水线。
set -euo pipefail
GO_BIN="$(command -v go || true)"
if [ -z "$GO_BIN" ]; then
  echo "error: go not found. Install with: brew install go" >&2
  exit 1
fi
SRC="${SRCROOT}/Vendor/qodercn-gateway"
OUT="${BUILT_PRODUCTS_DIR}/qodercn-gateway"
cd "$SRC"
"$GO_BIN" build -trimpath -o "$OUT" ./cmd/qodercn-gateway
echo "built $OUT"
