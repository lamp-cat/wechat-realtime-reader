#!/bin/bash
# 前台启动只读读取服务(127.0.0.1:5678,令牌鉴权)。
# 覆盖地址: WECHAT_READER_ADDR=127.0.0.1:5678 ./scripts/serve.sh
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/reader/bin/wechat-reader"
ADDR="${WECHAT_READER_ADDR:-127.0.0.1:5678}"
CFG="$HOME/.config/wechat-realtime-reader"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "只在 macOS 上运行。"
  exit 1
fi
if [[ ! -f "$BIN" ]]; then
  echo "找不到 $BIN,请先运行 $REPO/scripts/setup.sh"
  exit 1
fi
chmod +x "$BIN"
if [[ ! -f "$CFG/source-config.json" ]]; then
  echo "缺少 $CFG/source-config.json,请先运行 $REPO/scripts/setup.sh"
  exit 1
fi
if [[ ! -f "$CFG/keys.json" ]]; then
  echo "缺少密钥 $CFG/keys.json,请先运行 $REPO/scripts/recapture-keys.sh"
  exit 1
fi

exec "$BIN" serve -addr "$ADDR"
