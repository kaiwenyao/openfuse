#!/bin/bash
# OpenFuse for iPhone / iPad — build, install over USB, and renew.
#
#   Scripts/install-openfuse-ios.sh                 # pick the only/first connected iPhone or iPad
#   Scripts/install-openfuse-ios.sh --device "Kai's iPad" --team ABCDE12345
#   Scripts/install-openfuse-ios.sh --list
#
# Uses a free Apple Account (Personal Team) through Xcode automatic signing:
# the development profile expires after 7 days, so re-run the same command to
# overwrite the app and renew it. App data and Keychain items survive the
# overwrite because the bundle identifier and team stay the same.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${OPENFUSE_BUNDLE_ID:-com.openfuse.mobile}"
CONFIG="Release"
DERIVED="build/mobile-device"
DEVICE_ARG=""
TEAM="${OPENFUSE_DEVELOPMENT_TEAM:-}"
LAUNCH=1
LIST_ONLY=0

usage() {
  sed -n '2,10p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE_ARG="${2:-}"; shift 2 ;;
    --team) TEAM="${2:-}"; shift 2 ;;
    --bundle-id) BUNDLE_ID="${2:-}"; shift 2 ;;
    --configuration) CONFIG="${2:-}"; shift 2 ;;
    --derived) DERIVED="${2:-}"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    --list) LIST_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "error: $*" >&2; exit 1; }

# --- prerequisites --------------------------------------------------------

xcode-select -p >/dev/null 2>&1 || fail "Xcode 未安装或未选中：先安装 Xcode，再运行 sudo xcode-select -s /Applications/Xcode.app"
command -v xcodebuild >/dev/null 2>&1 || fail "找不到 xcodebuild"
command -v xcrun >/dev/null 2>&1 || fail "找不到 xcrun"
xcrun devicectl --version >/dev/null 2>&1 || fail "devicectl 不可用：需要 Xcode 15 及以上"
if ! command -v xcodegen >/dev/null 2>&1; then
  fail "缺少 XcodeGen：brew install xcodegen"
fi

# --- connected iPhone / iPad ---------------------------------------------

DEVICES_RAW=$(mktemp "${TMPDIR:-/tmp}/openfuse-devices.XXXXXX")
trap 'rm -f "$DEVICES_RAW"' EXIT
xcrun xctrace list devices >"$DEVICES_RAW" 2>/dev/null || true

# Real devices live in the "== Devices ==" section; keep iPhone/iPad lines only.
awk '
  /^== Devices ==/ {section="devices"; next}
  /^== Simulators ==/ {section="sim"; next}
  section=="devices" && ($0 ~ /iPhone/ || $0 ~ /iPad/) {print}
' "$DEVICES_RAW" > "$DEVICES_RAW.ios"

# bash 3.2 (system bash) has no mapfile: keep the list in a file and index it.
IOS_COUNT=$(grep -c . "$DEVICES_RAW.ios" 2>/dev/null || true)
[ -n "$IOS_COUNT" ] || IOS_COUNT=0
ios_line() { sed -n "${1}p" "$DEVICES_RAW.ios"; }
if [ "$IOS_COUNT" -eq 0 ]; then
  echo "没有检测到已连接的 iPhone / iPad。"
  echo
  echo "插线前请先在设备上完成（每台一次）："
  echo "  1. 用数据线连接 Mac，在 iPhone/iPad 上点“信任此电脑”，输入设备密码。"
  echo "  2. 设置 → 隐私与安全性 → 开发者模式 → 打开，然后重启设备。"
  echo "  3. Xcode → Settings → Accounts 用免费 Apple 账户登录，选中 Personal Team。"
  echo "  4. 首次安装后在 设置 → 通用 → VPN与设备管理 中信任你的开发者证书。"
  echo
  echo "插好设备后重新运行：Scripts/install-openfuse-ios.sh"
  [ "$LIST_ONLY" = "1" ] && exit 0
  exit 3
fi

print_device() {
  local i="$1" line
  line=$(ios_line "$i")
  local name udid os
  name=$(printf '%s' "$line" | sed -E 's/ \([0-9A-Fa-f-]{8,}\)$//' | sed -E 's/ \([0-9.]+\)$//')
  udid=$(printf '%s' "$line" | sed -nE 's/.*\(([0-9A-Fa-f-]{8,})\)$/\1/p')
  os=$(printf '%s' "$line" | sed -nE 's/.*\(([0-9]+\.[0-9.]+)\) \(([0-9A-Fa-f-]{8,})\)$/\1/p')
  printf '  %d) %s%s\n     UDID: %s\n' "$i" "$name" "${os:+ · iOS $os}" "$udid"
}

if [ "$LIST_ONLY" = "1" ]; then
  echo "已连接的 iPhone / iPad："
  i=1
  while [ "$i" -le "$IOS_COUNT" ]; do print_device "$i"; i=$((i + 1)); done
  exit 0
fi

SELECTED_LINE=""
if [ -n "$DEVICE_ARG" ]; then
  i=1
  while [ "$i" -le "$IOS_COUNT" ]; do
    line=$(ios_line "$i")
    if printf '%s' "$line" | grep -qiF "$DEVICE_ARG"; then SELECTED_LINE="$line"; break; fi
    i=$((i + 1))
  done
  [ -n "$SELECTED_LINE" ] || fail "没有找到匹配“$DEVICE_ARG”的设备；用 --list 查看已连接设备。"
elif [ "$IOS_COUNT" -eq 1 ]; then
  SELECTED_LINE=$(ios_line 1)
else
  echo "检测到多台设备，请选择要安装的一台："
  i=1
  while [ "$i" -le "$IOS_COUNT" ]; do print_device "$i"; i=$((i + 1)); done
  printf '输入序号：'
  read -r choice
  case "$choice" in
    ''|*[!0-9]*) fail "无效的序号" ;;
  esac
  [ "$choice" -ge 1 ] && [ "$choice" -le "$IOS_COUNT" ] || fail "序号超出范围"
  SELECTED_LINE=$(ios_line "$choice")
fi

UDID=$(printf '%s' "$SELECTED_LINE" | sed -nE 's/.*\(([0-9A-Fa-f-]{8,})\)$/\1/p')
DEVICE_NAME=$(printf '%s' "$SELECTED_LINE" | sed -E 's/ \([0-9A-Fa-f-]{8,}\)$//' | sed -E 's/ \([0-9.]+\)$//')
[ -n "$UDID" ] || fail "无法解析设备 UDID：$SELECTED_LINE"

# --- signing identity / team ---------------------------------------------

if [ -z "$TEAM" ]; then
  TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E "Apple Development" | head -1 \
    | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')
fi
if [ -z "$TEAM" ]; then
  cat >&2 <<'MSG'
error: 没有找到 Apple Development 签名身份（免费 Personal Team）。

请在 Xcode 里完成一次（只需要一次）：
  1. Xcode → Settings… → Accounts → “+” → Apple ID，登录你的免费 Apple 账户。
  2. 选中刚添加的 Apple ID，点 “Manage Certificates…” → “+” → Apple Development。
  3. Xcode → Settings… → Accounts 里能看到 “Personal Team (团队 ID)”。
然后重新运行本脚本；也可以用 --team <团队ID> 手动指定。
MSG
  exit 4
fi

echo "设备：$DEVICE_NAME ($UDID)"
echo "团队：$TEAM"
echo "Bundle ID：$BUNDLE_ID"

# --- build ----------------------------------------------------------------

echo "[1/3] 构建（自动签名，免费 Personal Team）…"
Scripts/build-ios.sh --device --team "$TEAM" --derived "$DERIVED" --configuration "$CONFIG" --bundle-id "$BUNDLE_ID" >/dev/null

APP="$DERIVED/Build/Products/${CONFIG}-iphoneos/OpenFuse.app"
[ -d "$APP" ] || fail "没有找到构建产物：$APP"

PROFILE="$APP/embedded.mobileprovision"
EXPIRY=""
if [ -f "$PROFILE" ]; then
  PXML=$(mktemp "${TMPDIR:-/tmp}/openfuse-profile.XXXXXX")
  if security cms -D -i "$PROFILE" >"$PXML" 2>/dev/null; then
    EXPIRY=$(plutil -extract ExpirationDate raw -o - "$PXML" 2>/dev/null || true)
  fi
  rm -f "$PXML"
fi

echo "[2/3] 通过 USB 安装（覆盖旧版本，保留 App 数据与 Keychain）…"
if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
  cat >&2 <<'MSG'
error: 安装失败。常见原因：
  - 设备未解锁，或还没点“信任此电脑”；
  - 设置 → 隐私与安全性 → 开发者模式 没打开（打开后需重启设备）；
  - 该 Apple ID 的免费开发证书数量已满：Xcode → Settings → Accounts → Manage Certificates 删除旧证书后重试；
  - Bundle ID 已被别的团队占用：用 --bundle-id com.openfuse.mobile.<你的名字> 换一个。
MSG
  exit 5
fi

if [ "$LAUNCH" = "1" ]; then
  echo "[3/3] 启动 OpenFuse…"
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || \
    echo "warning: 已安装但未能自动启动；请在设备上点开 OpenFuse。首次运行若提示“不受信任的开发者”，到 设置 → 通用 → VPN与设备管理 里信任你的证书。"
else
  echo "[3/3] 已跳过启动（--no-launch）。"
fi

echo
if [ -n "$EXPIRY" ]; then
  DAYS=$(python3 - "$EXPIRY" <<'PY'
import datetime, sys
raw = sys.argv[1].strip()
for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S +0000"):
    try:
        dt = datetime.datetime.strptime(raw, fmt).replace(tzinfo=datetime.timezone.utc)
        break
    except ValueError:
        dt = None
if dt is None:
    print("")
else:
    delta = dt - datetime.datetime.now(datetime.timezone.utc)
    print(max(0, int(delta.total_seconds() // 86400)))
PY
)
  echo "描述文件到期：$EXPIRY（约 ${DAYS:-?} 天）"
  echo "免费 Personal Team 的签名 7 天到期；到期前重新运行同一条命令即可覆盖安装并续签："
  echo "  Scripts/install-openfuse-ios.sh --device \"$DEVICE_NAME\""
else
  echo "未能读取描述文件到期日；免费 Personal Team 的签名 7 天到期，到期前重新运行同一条命令即可续签。"
fi
