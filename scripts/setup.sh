#!/bin/bash
# 一键安装可自动化的部分(macOS / Apple Silicon)。幂等:已有配置不会被覆盖。
# 一次性的「抓密钥」和「完全磁盘访问权限」需你手动完成,见脚本结束时的提示。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
READER="$REPO/reader"
BIN="$READER/bin/wechat-reader"
CFG="$HOME/.config/wechat-realtime-reader"
VAULT="$HOME/.local/share/wechat-realtime-reader"
LAUNCH_SRC="$REPO/launchd/com.lampcat.wechatreader.plist.template"
LAUNCH_DST="$HOME/Library/LaunchAgents/com.lampcat.wechatreader.plist"
LABEL="com.lampcat.wechatreader"
WECHAT_FILES="$HOME/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"

echo "==> 环境检查"
if [[ "$(uname)" != "Darwin" ]]; then
  echo "本套件只在 macOS 上运行(预编译二进制为 Apple Silicon Mach-O)。"
  echo "当前系统是 $(uname)。源码在 $READER,可在 Mac 上直接使用预编译二进制,或安装 Go 1.25+ 后执行:"
  echo "  cd \"$READER\" && go build -o bin/wechat-reader ./cmd/wechat-reader"
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "预编译二进制面向 Apple Silicon (arm64),当前是 $(uname -m)。"
  echo "请在 Apple Silicon Mac 上运行,或安装 Go 1.25+ 后从源码编译:"
  echo "  cd \"$READER\" && go build -o bin/wechat-reader ./cmd/wechat-reader"
fi

if [[ ! -f "$BIN" ]]; then
  echo "找不到预编译二进制 $BIN"
  if command -v go >/dev/null 2>&1; then
    echo "检测到 Go,尝试从源码编译…"
    (cd "$READER" && go build -o bin/wechat-reader ./cmd/wechat-reader)
  else
    echo "请安装 Go 1.25+ 后执行: cd \"$READER\" && go build -o bin/wechat-reader ./cmd/wechat-reader"
    exit 1
  fi
fi
chmod +x "$BIN"
chmod +x "$REPO/scripts/"*.sh

echo "==> 本机配置目录(0700;已存在则保留)"
mkdir -p "$CFG" "$VAULT"
chmod 700 "$CFG" "$VAULT"

if [[ ! -f "$CFG/source-config.json" ]]; then
  if "$BIN" detect -write -json >/tmp/wechat-reader-detect.$$.json 2>/tmp/wechat-reader-detect.$$.err; then
    chosen="$(python3 -c "import json;print(json.load(open('/tmp/wechat-reader-detect.$$.json')).get('chosen') or '')" 2>/dev/null || true)"
    if [[ -n "$chosen" ]]; then
      echo "   已自动绑定本机微信账号目录: $chosen"
    else
      echo "   未找到账号目录(请先登录微信一次);已放置模板,见 $CFG/source-config.json"
    fi
  else
    cp "$REPO/config/source-config.json.template" "$CFG/source-config.json"
    chmod 600 "$CFG/source-config.json"
    echo "   自动检测失败,已放置模板,请编辑 $CFG/source-config.json"
  fi
  rm -f /tmp/wechat-reader-detect.$$.json /tmp/wechat-reader-detect.$$.err
else
  echo "   已保留现有 $CFG/source-config.json"
fi

echo "==> 渲染 launchd 配置"
mkdir -p "$HOME/Library/LaunchAgents"
log="$CFG/serve.log"
if [[ ! -f "$log" ]]; then
  umask 077
  touch "$log"
  chmod 600 "$log"
fi
sed -e "s#__READER_BIN__#$BIN#g" -e "s#__HOME__#$HOME#g" "$LAUNCH_SRC" > "$LAUNCH_DST"

if [[ -f "$CFG/keys.json" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_DST"
  echo "   已安装并启动 launchd 保活($LABEL)"
else
  echo "   已生成 $LAUNCH_DST(尚未载入:还没有密钥)"
  echo "   抓完密钥后请再运行一次本脚本,或执行:"
  echo "     launchctl bootstrap gui/\$(id -u) \"$LAUNCH_DST\""
fi

echo
echo "==================== 安装完成(自动部分) ===================="
echo "读取器二进制: $BIN"
echo "本机配置目录: $CFG"
echo
echo "还需你手动完成(一次性):"
echo "  1) 确认 $CFG/source-config.json 里的 wxid 与 db_base_path 是你的真实值"
echo "  2) 登录并保持微信在线,运行: $REPO/scripts/recapture-keys.sh"
echo "     密钥写入 $CFG(权限 0600),脚本不会打印密钥"
echo "  3) 系统设置 → 隐私与安全性 → 完全磁盘访问权限,加入 $BIN"
echo "  4) 启动服务: $REPO/scripts/serve.sh"
echo "     或(已抓密钥后)再运行一次本脚本,用 launchd 保活"
echo "  5) 用浏览器打开终端打印的本机地址(带令牌)。令牌=完整读权限,请当机密。"
echo "============================================================"
