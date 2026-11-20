#!/bin/bash
#
# OpenFuse for macOS — installer / upgrader / uninstaller
#
# Private repository: fetch this script with gh, then run it.
#   gh release download <tag> -R kaiwenyao/openfuse -p install-openfuse-macos.sh -O /tmp/install.sh
#   bash /tmp/install.sh
#
#   install-openfuse-macos.sh                  # newest GitHub release
#   install-openfuse-macos.sh --app FILE.zip   # offline install from a local zip (or .app)
#   install-openfuse-macos.sh --sign local     # stable local code-signing identity
#   install-openfuse-macos.sh --reset-identity # forget the local signing identity
#   install-openfuse-macos.sh --uninstall      # remove the app (keeps your library)
#
# OpenFuse keeps credentials in the login Keychain and library/progress in
# ~/Library/Application Support/OpenFuse; replacing the .app keeps both while the
# bundle identifier stays com.openfuse.app.
#
# OpenFuse needs no Accessibility, Input Monitoring or Screen Recording grants.
# The installer never asks for them; the only system prompt you may see is the
# one-time Keychain dialog after an ad-hoc update (or the one-time trust prompt
# when creating the optional local signing identity).
#
set -Eeuo pipefail

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
umask 077

REPO="kaiwenyao/openfuse"
PRODUCT="OpenFuse"
BUNDLE_ID="com.openfuse.app"
EXECUTABLE="OpenFuse"
CERT_CN="OpenFuse Local Signing"
ASSET_PREFIX="OpenFuse-macOS-"
MIN_MACOS_MAJOR=14
SUPPORT_DIR="$HOME/Library/Application Support/OpenFuse"

PREFIX=""
PREFIX_SET=0
LAUNCH=1
SIGN_MODE="adhoc"        # adhoc (default) | local
RELEASE_TAG=""
LOCAL_SOURCE=""
LANG_MODE="auto"
KEEP_BACKUP=0
MODE="install"
RESET_IDENTITY=0

work=""
backup_dir=""

# --------------------------------------------------------------------------
# messaging
# --------------------------------------------------------------------------

msg() {
    local key="$1"
    local en cn
    case "$key" in
        usage)
            en="Usage: install-openfuse-macos.sh [--app PATH] [--release TAG] [--prefix DIR] [--sign adhoc|local] [--reset-identity] [--uninstall] [--no-launch] [--keep-backup] [--lang en|zh-CN] [--help]"
            cn="用法：install-openfuse-macos.sh [--app 本地zip或.app] [--release 标签] [--prefix 目录] [--sign adhoc|local] [--reset-identity] [--uninstall] [--no-launch] [--keep-backup] [--lang en|zh-CN] [--help]"
            ;;
        downloading) en="[1/5] Downloading the OpenFuse release…"; cn="[1/5] 正在下载 OpenFuse 安装包…" ;;
        verifying)   en="[2/5] Verifying SHA-256 and the app bundle…"; cn="[2/5] 正在校验 SHA-256 与应用包…" ;;
        signing)     en="[3/5] Signing the app…"; cn="[3/5] 正在签名…" ;;
        installing)  en="[4/5] Installing into %s…"; cn="[4/5] 正在安装到 %s…" ;;
        done)        en="[5/5] OpenFuse is installed."; cn="[5/5] OpenFuse 安装完成。" ;;
        no_permissions)
            en="OpenFuse needs no Accessibility or Screen Recording grants. If macOS asks for Keychain access after an ad-hoc update, choose “Always Allow” once — or install with --sign local so updates reuse one identity."
            cn="OpenFuse 不需要辅助功能或屏幕录制权限。若 ad-hoc 升级后 macOS 询问钥匙串访问，点一次“始终允许”即可；或用 --sign local 安装，让以后升级复用同一签名身份。"
            ;;
        verify_failed) en="SHA-256 verification failed. Nothing was installed."; cn="SHA-256 校验失败，未安装任何内容。" ;;
        download_failed) en="Download failed. Check the network / gh login and retry."; cn="下载失败，请检查网络或 gh 登录后重试。" ;;
        bundle_invalid) en="The app bundle is invalid or has the wrong bundle identifier. Nothing was installed."; cn="应用包无效或 bundle id 不匹配，未安装任何内容。" ;;
        signing_failed) en="Signing failed. Nothing was installed."; cn="签名失败，未安装任何内容。" ;;
        rollback) en="Install failed; the previous version was restored."; cn="安装失败，已恢复上一版本。" ;;
        installed_ok) en="Installed %s (%s) at %s"; cn="已安装 %s（%s）：%s" ;;
        data_kept) en="User data kept: %s sources, %s Keychain credential(s), playback history %s."; cn="用户数据保留：来源 %s 个、Keychain 凭据 %s 条、观看记录 %s。" ;;
        gh_needed)
            en="The repository is private: install and log in to gh first (brew install gh && gh auth login), or pass --app with a local zip."
            cn="仓库是私有的：请先安装并登录 gh（brew install gh && gh auth login），或用 --app 指定本地 zip。"
            ;;
        help_tail)
            en="After installing: open OpenFuse, add WebDAV / Jellyfin sources; credentials go to the login Keychain by default."
            cn="安装后：打开 OpenFuse，添加 WebDAV / Jellyfin 来源；凭据默认写入登录钥匙串。"
            ;;
        no_root) en="Do not run this installer with sudo; it installs for the current user."; cn="请不要用 sudo 运行安装脚本，它会为当前用户安装。" ;;
        arch_unsupported) en="Unsupported CPU architecture (need arm64 or x86_64)."; cn="不支持的 CPU 架构（需要 arm64 或 x86_64）。" ;;
        macos_too_old) en="OpenFuse needs macOS %s or newer."; cn="OpenFuse 需要 macOS %s 或更新版本。" ;;
        identity_prompt)
            en="Creating a 10-year self-signed “%s” identity in your login Keychain. macOS may ask once to trust it for code signing; later updates reuse it."
            cn="正在登录钥匙串中创建 10 年期自签“%s”身份。macOS 可能请求一次代码签名信任确认；以后升级会复用它。"
            ;;
        identity_failed) en="Could not create or trust the local signing identity. Nothing was installed; run with --sign adhoc or retry after unlocking the Keychain."; cn="无法创建或信任本地签名身份，未安装任何内容；可改用 --sign adhoc，或解锁钥匙串后重试。" ;;
        reset_done) en="Local signing identity removed; the next --sign local install creates a fresh one."; cn="已删除本地签名身份；下次 --sign local 安装会重新创建。" ;;
        identity_migration)
            en="This update switches from the ad-hoc signature to the persistent identity. macOS may ask for Keychain access once; later updates will not."
            cn="本次更新把 ad-hoc 签名切换为持久身份。macOS 可能询问一次钥匙串访问，之后升级不会再问。"
            ;;
        uninstall_done) en="OpenFuse.app was removed. Your sources, Keychain items and playback history under %s were kept."; cn="已删除 OpenFuse.app；%s 下的来源、Keychain 凭据和观看记录都保留。" ;;
        uninstall_missing) en="OpenFuse.app is not installed."; cn="未找到已安装的 OpenFuse.app。" ;;
        *) en="$key"; cn="$key" ;;
    esac
    if [ "$LANG_MODE" = "zh-CN" ]; then printf '%s\n' "$cn"; else printf '%s\n' "$en"; fi
}

say()  { msg "$1"; }
sayf() { local key="$1"; shift; local text; text=$(msg "$key"); printf "$text\n" "$@"; }
warn() { msg "$1" >&2; }
die()  { msg "$1" >&2; exit 1; }

cleanup() {
    local status=$?
    if [ -n "$work" ] && [ -d "$work" ]; then
        if [ "$KEEP_BACKUP" = "1" ] && [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
            printf 'backup kept at %s\n' "$backup_dir" >&2
        fi
        rm -rf "$work" 2>/dev/null || true
    fi
    return "$status"
}
trap cleanup EXIT

select_language() {
    [ "$LANG_MODE" = "auto" ] || return 0
    local preference="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    if [ -z "$preference" ] || [ "$preference" = "C" ] || [ "$preference" = "POSIX" ]; then
        preference=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')
    fi
    case "$preference" in
        *zh*) LANG_MODE="zh-CN" ;;
        *) LANG_MODE="en" ;;
    esac
}

macos_major() { sw_vers -productVersion 2>/dev/null | cut -d. -f1; }

run_with_timeout() {
    local seconds="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$seconds"; kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local watchdog=$!
    local rc=0
    wait "$pid" 2>/dev/null || rc=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return "$rc"
}

# --------------------------------------------------------------------------
# arguments and environment checks
# --------------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --app) LOCAL_SOURCE="${2:-}"; shift 2 ;;
        --release) RELEASE_TAG="${2:-}"; shift 2 ;;
        --prefix) PREFIX="${2:-}"; PREFIX_SET=1; shift 2 ;;
        --sign) SIGN_MODE="${2:-}"; shift 2 ;;
        --reset-identity) RESET_IDENTITY=1; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --no-launch) LAUNCH=0; shift ;;
        --lang) LANG_MODE="${2:-}"; shift 2 ;;
        --keep-backup) KEEP_BACKUP=1; shift ;;
        -h|--help) select_language; msg usage; echo; msg help_tail; exit 0 ;;
        *) echo "unknown option: $1" >&2; msg usage >&2; exit 2 ;;
    esac
done

select_language

case "$SIGN_MODE" in adhoc|local) ;; *) echo "unknown --sign value: $SIGN_MODE" >&2; exit 2 ;; esac
[ "$(id -u)" -eq 0 ] && die no_root
case "$(uname -m)" in arm64|x86_64) : ;; *) die arch_unsupported ;; esac
if [ "$MODE" = "install" ]; then
    major=$(macos_major)
    [ -n "$major" ] && [ "$major" -lt "$MIN_MACOS_MAJOR" ] && { printf "$(msg macos_too_old)\n" "$MIN_MACOS_MAJOR" >&2; exit 1; }
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/openfuse-install.XXXXXX")

# --------------------------------------------------------------------------
# local signing identity (optional; no Apple Developer account required)
# --------------------------------------------------------------------------

state_dir() { printf '%s\n' "$SUPPORT_DIR/Installer"; }
login_keychain() { security default-keychain 2>/dev/null | tr -d '"' || true; }

is_fingerprint() { case "$1" in ""|*[!0-9A-Fa-f]*) return 1 ;; esac; [ "${#1}" -eq 40 ]; }
normalize_fp() { printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]'; }

read_state_fp() {
    local dir="$1" raw
    [ -s "$dir/signing-identity" ] || return 1
    raw=$(tr -d '[:space:]' < "$dir/signing-identity" 2>/dev/null || true)
    is_fingerprint "$raw" || return 1
    normalize_fp "$raw"
}

identity_is_trusted() { security find-identity -v -p codesigning 2>/dev/null | grep -qi "$1"; }

identity_probe() {
    local fp="$1" probe
    probe=$(mktemp "${TMPDIR:-/tmp}/openfuse-probe.XXXXXX") || return 1
    cp /bin/echo "$probe" 2>/dev/null || { rm -f "$probe"; return 1; }
    local rc=1
    run_with_timeout 30 codesign --force --sign "$fp" "$probe" >/dev/null 2>&1 && rc=0
    rm -f "$probe"
    return "$rc"
}

trust_identity() {
    local cert="$1" fp="$2" i=0
    [ -s "$cert" ] || return 1
    identity_is_trusted "$fp" && return 0
    run_with_timeout 180 security add-trusted-cert -r trustRoot -p codeSign \
        -k "$(login_keychain)" "$cert" >/dev/null 2>&1 || true
    while [ "$i" -lt 10 ]; do
        identity_is_trusted "$fp" && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}

delete_certs_by_cn() {
    local hashes h
    hashes=$(security find-certificate -c "$CERT_CN" -Z 2>/dev/null | sed -n 's/^SHA-1 hash: //p' || true)
    for h in $hashes; do
        run_with_timeout 30 security delete-certificate -Z "$h" -t >/dev/null 2>&1 || true
    done
}

reset_identity() {
    local state fp
    state=$(state_dir)
    if fp=$(read_state_fp "$state"); then
        run_with_timeout 30 security delete-certificate -Z "$fp" -t >/dev/null 2>&1 || true
    fi
    delete_certs_by_cn
    rm -rf "$state" 2>/dev/null || true
    say reset_done
}

create_identity() {
    local state tmp cert key p12 pass fingerprint
    state=$(state_dir)
    mkdir -p "$state" 2>/dev/null || return 1
    chmod 700 "$state" 2>/dev/null || true
    tmp="$work/identity"; rm -rf "$tmp"; mkdir -p "$tmp" || return 1
    cert="$tmp/cert.pem"; key="$tmp/key.pem"; p12="$tmp/identity.p12"
    cat > "$tmp/cert.cnf" <<EOF
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3
[dn]
CN = $CERT_CN
O = OpenFuse Local Signing
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
EOF
    openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 -config "$tmp/cert.cnf" \
        -keyout "$key" -out "$cert" >/dev/null 2>&1 || return 1
    pass=$(openssl rand -hex 24)
    openssl pkcs12 -export -inkey "$key" -in "$cert" -name "$CERT_CN" -out "$p12" \
        -passout "pass:$pass" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        >/dev/null 2>&1 || return 1
    run_with_timeout 120 security import "$p12" -k "$(login_keychain)" -P "$pass" -T /usr/bin/codesign >/dev/null 2>&1 || return 1
    unset pass
    fingerprint=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n "s/^[[:space:]]*[0-9][0-9]*) \([0-9A-Fa-f]\{40\}\) \"$CERT_CN\"$/\1/p" | head -1)
    [ -n "$fingerprint" ] || return 1
    printf '%s\n' "$fingerprint" > "$state/signing-identity"
    cp "$cert" "$state/signing-certificate.pem" 2>/dev/null || true
    trust_identity "$cert" "$fingerprint" || return 1
    identity_probe "$fingerprint" || return 1
    printf '%s\n' "$fingerprint"
}

local_identity() {
    local state fp
    state=$(state_dir)
    if fp=$(read_state_fp "$state") && identity_is_trusted "$fp" && identity_probe "$fp"; then
        printf '%s\n' "$fp"; return 0
    fi
    printf '%s\n' "$(msg identity_prompt)" | sed "s/%s/$CERT_CN/" >&2
    create_identity
}

sign_staged_app() {
    local app="$1"
    xattr -dr com.apple.quarantine "$app" >/dev/null 2>&1 || true
    if [ "$SIGN_MODE" = "adhoc" ]; then
        codesign --force --deep --sign - --timestamp=none "$app" >/dev/null 2>&1 || return 1
    else
        local identity
        identity=$(local_identity) || return 1
        codesign --force --deep --sign "$identity" --timestamp=none "$app" >/dev/null 2>&1 || return 1
    fi
    codesign --verify --deep --strict "$app" >/dev/null 2>&1
}

# --------------------------------------------------------------------------
# release download
# --------------------------------------------------------------------------

resolve_tag() {
    if [ -n "$RELEASE_TAG" ]; then echo "$RELEASE_TAG"; return 0; fi
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh release view -R "$REPO" --json tagName -q .tagName 2>/dev/null && return 0
    fi
    curl --fail --silent --show-error --location --max-time 20 --proto '=https' --proto-redir '=https' \
        "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
}

fetch_release_assets() {
    local tag="$1" dir="$2" name="$3" base
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh release download "$tag" -R "$REPO" -p "$name" -p "$name.sha256" -D "$dir" >/dev/null 2>&1 && return 0
    fi
    base="https://github.com/${REPO}/releases/download/${tag}"
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 600 --retry 2 --output "$dir/$name" "$base/$name" || return 1
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 600 --output "$dir/$name.sha256" "$base/$name.sha256" || return 1
}

# --------------------------------------------------------------------------
# install / upgrade / uninstall
# --------------------------------------------------------------------------

quit_running() {
    pgrep -x "$EXECUTABLE" >/dev/null 2>&1 || return 0
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local i=0
    while pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
    pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
    sleep 1
    ! pgrep -x "$EXECUTABLE" >/dev/null 2>&1
}

count_keychain_credentials() {
    security dump-keychain 2>/dev/null | grep -c 'svce"<blob>="com.openfuse\.' || true
}

count_sources() {
    local file="$SUPPORT_DIR/sources.json"
    [ -f "$file" ] || { echo 0; return; }
    /usr/bin/python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("sources",[])))' "$file" 2>/dev/null || echo 0
}

install_app() {
    local staged="$work/staged/$PRODUCT.app" zip="" expected="" actual="" version commit destination_dir destination tmpdst
    local sources_before keychain_before playback_before sources_after keychain_after playback_after

    say downloading
    if [ -n "$LOCAL_SOURCE" ]; then
        if [ -d "$LOCAL_SOURCE" ]; then
            mkdir -p "$work/staged"; ditto "$LOCAL_SOURCE" "$staged" || die bundle_invalid
        elif [ -f "$LOCAL_SOURCE" ]; then
            zip="$LOCAL_SOURCE"
        else
            die download_failed
        fi
    else
        local tag name
        tag=$(resolve_tag)
        [ -n "$tag" ] || die download_failed
        name=$(gh release view "$tag" -R "$REPO" --json assets -q '.assets[].name' 2>/dev/null | grep -E "^${ASSET_PREFIX}.*\.zip$" | head -1 || true)
        if [ -z "$name" ]; then
            command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 || die gh_needed
            die download_failed
        fi
        fetch_release_assets "$tag" "$work" "$name" || die download_failed
        zip="$work/$name"
    fi

    say verifying
    if [ -n "$zip" ]; then
        if [ -f "$zip.sha256" ]; then
            expected=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$zip.sha256" | head -1)
        fi
        [ -n "$expected" ] || die verify_failed
        actual=$(shasum -a 256 "$zip" | awk '{print $1}')
        [ "$actual" = "$expected" ] || die verify_failed
        mkdir -p "$work/staged"
        ditto -x -k "$zip" "$work/staged" >/dev/null 2>&1 || die bundle_invalid
    fi

    [ -x "$staged/Contents/MacOS/$EXECUTABLE" ] || die bundle_invalid
    [ "$(plutil -extract CFBundleIdentifier raw "$staged/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] || die bundle_invalid
    version=$(plutil -extract CFBundleShortVersionString raw "$staged/Contents/Info.plist" 2>/dev/null || echo unknown)
    commit=$(plutil -extract OpenFuseCommit raw "$staged/Contents/Info.plist" 2>/dev/null || echo unknown)

    say signing
    sign_staged_app "$staged" || die signing_failed

    quit_running || die bundle_invalid

    destination_dir="$PREFIX"
    if [ "$PREFIX_SET" = "0" ]; then
        if [ -d "/Applications/$PRODUCT.app" ] || [ -w "/Applications" ]; then destination_dir="/Applications"; else destination_dir="$HOME/Applications"; fi
    fi
    destination="$destination_dir/$PRODUCT.app"
    mkdir -p "$destination_dir" 2>/dev/null || true
    if [ ! -w "$destination_dir" ]; then
        destination_dir="$HOME/Applications"; destination="$destination_dir/$PRODUCT.app"; mkdir -p "$destination_dir"
    fi

    sources_before=$(count_sources)
    keychain_before=$(count_keychain_credentials)
    [ -f "$SUPPORT_DIR/playback.json" ] && playback_before="present" || playback_before="missing"

    sayf installing "$destination_dir"
    if [ -d "$destination" ]; then
        backup_dir="$work/backup"; mkdir -p "$backup_dir"
        ditto "$destination" "$backup_dir/$PRODUCT.app" || die bundle_invalid
    fi

    tmpdst="$destination_dir/.$PRODUCT.app.new.$$"
    rm -rf "$tmpdst"
    if ! ditto "$staged" "$tmpdst"; then
        rm -rf "$tmpdst"
        [ -n "$backup_dir" ] && [ -d "$backup_dir/$PRODUCT.app" ] && ditto "$backup_dir/$PRODUCT.app" "$destination" || true
        die bundle_invalid
    fi
    if [ -d "$destination" ]; then
        if ! rm -rf "$destination" || ! mv "$tmpdst" "$destination"; then
            rm -rf "$destination" 2>/dev/null || true
            [ -d "$backup_dir/$PRODUCT.app" ] && ditto "$backup_dir/$PRODUCT.app" "$destination" || true
            warn rollback; exit 1
        fi
    else
        mv "$tmpdst" "$destination" || { rm -rf "$tmpdst"; die bundle_invalid; }
    fi

    [ "$(plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] || die bundle_invalid
    codesign --verify --deep --strict "$destination" >/dev/null 2>&1 || die bundle_invalid

    sources_after=$(count_sources)
    keychain_after=$(count_keychain_credentials)
    [ -f "$SUPPORT_DIR/playback.json" ] && playback_after="present" || playback_after="missing"

    sayf installed_ok "$version" "$commit" "$destination"
    if [ "$sources_after" = "$sources_before" ] && [ "$keychain_after" = "$keychain_before" ] && [ "$playback_after" = "$playback_before" ]; then
        sayf data_kept "$sources_after" "$keychain_after" "$playback_after"
    else
        printf 'warning: user data changed during install (sources %s→%s, keychain %s→%s, playback %s→%s)\n' \
            "$sources_before" "$sources_after" "$keychain_before" "$keychain_after" "$playback_before" "$playback_after" >&2
    fi

    [ "$LAUNCH" = "1" ] && open "$destination" >/dev/null 2>&1 || true
    msg no_permissions
}

uninstall_app() {
    local destination found=0
    quit_running || true
    for destination in "$PREFIX/$PRODUCT.app" "/Applications/$PRODUCT.app" "$HOME/Applications/$PRODUCT.app"; do
        if [ -d "$destination" ]; then
            rm -rf "$destination" 2>/dev/null && found=1
        fi
    done
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    local state fp
    state=$(state_dir)
    if fp=$(read_state_fp "$state"); then
        run_with_timeout 30 security delete-certificate -Z "$fp" -t >/dev/null 2>&1 || true
    fi
    delete_certs_by_cn
    rm -rf "$state" 2>/dev/null || true
    if [ "$found" = "1" ]; then
        sayf uninstall_done "$SUPPORT_DIR"
    else
        say uninstall_missing
    fi
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

if [ "$MODE" = "uninstall" ]; then
    uninstall_app
    exit 0
fi

[ "$RESET_IDENTITY" = "1" ] && reset_identity
install_app
