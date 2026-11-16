#!/bin/bash
# 一次性用 Frida 抓取本机微信 4.x 数据库密钥(引导模式)。
#
# 流程(与 reader/skills/wechat-db-keys 一致):
#   在一份签名的临时副本上 hook CommonCrypto PBKDF,离线用库首页 HMAC-SHA512
#   配对后写入 ~/.config/wechat-realtime-reader/keys.json(0600)。
# 硬约束:
#   - 不修改官方 /Applications/WeChat.app,不关闭 SIP
#   - 终端只打印数量,不打印密钥本身
#   - 出现微信安全提示、登录受限或崩溃时立刻停止,不要反复重试
set -uo pipefail
umask 077
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
READER="$REPO/reader"
BIN="$READER/bin/wechat-reader"
SKILL="$READER/skills/wechat-db-keys"
CFG="$HOME/.config/wechat-realtime-reader"
APP="/Applications/WeChat.app"
UIDN="$(id -u)"
TS="$(date +%Y%m%d-%H%M%S)"
LABEL="com.lampcat.wechatreader"
capture_work=""
reader_paused=0

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask()  { local a; read -r -p "$* [y/N] " a; [[ "$a" == "y" || "$a" == "Y" ]]; }

cleanup() {
  if [[ -n "$capture_work" && -d "$capture_work" ]]; then
    pids="$(ps -axo pid=,command= | grep -F "$capture_work/WeChat.app/" | grep -v grep | awk '{print $1}')"
    if [[ -n "$pids" ]]; then
      echo "清理临时副本进程: $pids"
      kill -TERM $pids 2>/dev/null || true
      sleep 2
    fi
  fi
  if [[ "$reader_paused" == 1 ]]; then
    launchctl bootstrap "gui/$UIDN" "$HOME/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null && echo "已恢复读取服务保活。"
    reader_paused=0
  fi
}
trap cleanup EXIT

if [[ "$(uname)" != "Darwin" ]]; then
  echo "只在 macOS 上运行。"
  exit 1
fi
if [[ ! -x "$BIN" && -f "$BIN" ]]; then
  chmod +x "$BIN"
fi
if [[ ! -f "$BIN" ]]; then
  echo "找不到读取器二进制 $BIN,请先运行 $REPO/scripts/setup.sh"
  exit 1
fi
if [[ ! -d "$APP" ]]; then
  echo "找不到官方微信 $APP"
  exit 1
fi
if [[ ! -f "$CFG/source-config.json" ]]; then
  echo "缺少 $CFG/source-config.json,请先运行 $REPO/scripts/setup.sh 并填好 wxid / db_base_path"
  exit 1
fi
if [[ ! -d "$SKILL/scripts" ]]; then
  echo "找不到抓密钥配套脚本 $SKILL"
  exit 1
fi

cd "$READER"

say "微信数据库密钥抓取(引导模式)"
echo "正式版微信版本: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 未找到)"

say "第 1 步:先验证现有密钥(不输出密钥)"
if "$BIN" doctor; then
  echo
  echo "现有密钥验证通过,通常不需要重新抓取。"
  ask "仍然要继续重新抓取吗?" || exit 0
fi

DB_ROOT="$(python3 -c "import json,os; print(os.path.expanduser(json.load(open('$CFG/source-config.json'))['db_base_path']))")"
if [[ ! -d "$DB_ROOT" ]]; then
  echo "数据目录不存在:$DB_ROOT(请先在微信里登录一次,并检查 source-config.json)"
  exit 1
fi

say "第 2 步:完全退出微信"
echo "注意:这一步有一定账号风控风险。出现安全提示、登录受限或崩溃时请立刻停止,不要反复重试。"
ask "已了解,继续?" || exit 0

# 抓取期间暂停本套件的读取服务(如果已由 launchd 托管)
if launchctl print "gui/$UIDN/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null && reader_paused=1 && echo "已暂停读取服务保活(结束后自动恢复)。"
fi

while pgrep -f "$APP/Contents/MacOS/WeChat" >/dev/null; do
  echo "微信仍在运行。请在微信菜单选择「退出微信」(关窗口不算退出)。"
  read -r -p "退出后按回车继续(输入 q 放弃)… " a
  [[ "$a" == "q" ]] && exit 0
done
echo "微信已退出。"

say "第 3 步:准备临时签名副本 + 内置 Frida(不改正式版)"
ask "开始复制并签名临时副本?" || exit 0
capture_work="$(mktemp -d /private/tmp/wechat-db-keys.XXXXXX)"
echo "临时目录: $capture_work"
ditto --noextattr --noqtn "$APP" "$capture_work/WeChat.app" || exit 1
codesign --force --deep --sign - --entitlements "$SKILL/references/capture-entitlements.plist" "$capture_work/WeChat.app" || exit 1
codesign --verify --deep --strict "$capture_work/WeChat.app" || exit 1
# Frida：优先用内置的 frida-inject（无需 pip / 联网），其次本机已有的 frida；都没有才从 GitHub 官方 Release 下载并校验
APP_VENDOR="/Applications/消息工作台.app/Contents/Resources/payload/wechat-realtime-reader/skills/wechat-db-keys/vendor/frida"
export WD_FRIDA_VENDOR_DIRS="$SKILL/vendor/frida:$HOME/.local/share/wechatdesk/runtime/wechat-realtime-reader/skills/wechat-db-keys/vendor/frida:$APP_VENDOR"
PY=""
for c in /usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  [[ "$c" == /usr/bin/python3 ]] && ! xcode-select -p >/dev/null 2>&1 && continue
  [[ -x "$c" ]] && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1 && { PY="$c"; break; }
done
[[ -n "$PY" ]] || { echo "找不到 Python 3.8+"; exit 1; }
FRIDA_INFO="$("$PY" "$SKILL/scripts/keys.py" frida-check 2>/dev/null | head -1)"
if [[ -z "$FRIDA_INFO" || "$FRIDA_INFO" == backend=none* ]]; then
  echo "未找到内置 Frida，从 GitHub 官方 Release 下载 frida-inject（固定 17.25.2，校验 sha256，不走 pip）…"
  "$PY" "$SKILL/vendor/frida/fetch.py" || { echo "下载 Frida 失败。可改用安装包（.dmg）里内置的版本。"; exit 1; }
  FRIDA_INFO="$("$PY" "$SKILL/scripts/keys.py" frida-check 2>/dev/null | head -1)"
fi
echo "Frida: $(cut -d' ' -f1-3 <<<"$FRIDA_INFO")"
mkdir -p "$CFG/key-capture"
chmod 700 "$CFG" "$CFG/key-capture"

say "第 4 步:挂监听后启动临时副本(最长 60 秒)"
echo "看到 Hook ready 后副本会启动。若出现扫码/确认页,请在手机上完成;可以点开几个聊天以触发更多数据库。够了就按 Ctrl-C。"
ask "开始抓取?" || exit 0
CAP="$CFG/key-capture/candidates-$TS.jsonl"
"$PY" "$SKILL/scripts/keys.py" capture --app "$capture_work/WeChat.app" --seconds 60 --output "$CAP"
cleanup_pids="$(ps -axo pid=,command= | grep -F "$capture_work/WeChat.app/" | grep -v grep | awk '{print $1}')"
[[ -n "$cleanup_pids" ]] && kill -TERM $cleanup_pids 2>/dev/null || true

say "第 5 步:离线配对(首页 HMAC-SHA512 校验,只输出数量)"
NEW="$CFG/keys-new-$TS.json"
"$PY" "$SKILL/scripts/keys.py" pair --capture "$CAP" --db-root "$DB_ROOT" --output "$NEW" || {
  echo "配对失败,保留原 keys.json 不变。"
  exit 1
}

say "第 6 步:合并到 keys.json(先备份)"
ask "备份并合并新密钥?" || exit 0
if [[ -f "$CFG/keys.json" ]]; then
  cp -p "$CFG/keys.json" "$CFG/keys.json.bak-$TS"
  chmod 600 "$CFG/keys.json.bak-$TS"
fi
python3 - "$CFG/keys.json" "$NEW" <<'PY'
import json, os, sys, tempfile
old_p, new_p = sys.argv[1], sys.argv[2]
old = json.load(open(old_p)) if os.path.isfile(old_p) else {}
new = json.load(open(new_p))
old.update(new)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(old_p) or ".")
os.fchmod(fd, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(old, f, indent=2)
os.replace(tmp, old_p)
os.chmod(old_p, 0o600)
print(f"合并 {len(new)} 个库的新密钥,共 {len(old)} 个库。")
PY

say "第 7 步:验证 + 恢复微信"
"$BIN" doctor; rc=$?
open -a "$APP"
if [[ -n "$capture_work" && -d "$capture_work" ]]; then
  if [[ -d "$HOME/.Trash" ]]; then
    mv "$capture_work" "$HOME/.Trash/" && echo "临时副本已移到废纸篓:$(basename "$capture_work")"
  else
    rm -rf "$capture_work"
    echo "已删除临时副本。"
  fi
  capture_work=""
fi

# 恢复或首次载入 launchd
if [[ -f "$HOME/Library/LaunchAgents/${LABEL}.plist" ]]; then
  if [[ "$reader_paused" == 1 ]]; then
    launchctl bootstrap "gui/$UIDN" "$HOME/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null && echo "已恢复读取服务保活。"
    reader_paused=0
  else
    launchctl bootstrap "gui/$UIDN" "$HOME/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || launchctl kickstart -k "gui/$UIDN/$LABEL" 2>/dev/null || true
  fi
fi

if [[ "$rc" == 0 ]]; then
  say "完成:密钥验证通过。可以用 scripts/serve.sh 启动服务,或再运行一次 scripts/setup.sh 启用 launchd 保活。"
else
  say "doctor 仍有未通过的库,请把上面的输出(不含密钥)留下来排查。保留原备份 keys.json.bak-$TS。"
fi
echo "提示:图片密钥(image-key.json)会在读取器首次处理图片时自动推导;若升级后图片打不开再单独处理。"
exit "$rc"
