#!/bin/bash
#
# OpenFuse for macOS — installer / upgrader
#
#   curl -fsSL <release>/install-openfuse-macos.sh | bash            # private repo: use gh first
#   gh release download <tag> -R kaiwenyao/openfuse -p install-openfuse-macos.sh -O -
#
#   install-openfuse-macos.sh                 # newest GitHub release
#   install-openfuse-macos.sh --app FILE.zip  # offline install from a local zip (or .app)
#   install-openfuse-macos.sh --sign local    # stable local code-signing identity
#
# OpenFuse stores credentials in the login Keychain and its library/progress in
# ~/Library/Application Support/OpenFuse. Replacing the .app keeps both, as long
# as the bundle identifier stays com.openfuse.app.
#
# OpenFuse does not need Accessibility, Input Monitoring or Screen Recording;
# the installer never asks for them.
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

PREFIX=""
PREFIX_SET=0
LAUNCH=1
SIGN_MODE="adhoc"        # adhoc | local
RELEASE_TAG=""
LOCAL_SOURCE=""
LANG_MODE="auto"
KEEP_BACKUP=0

work=""
backup_dir=""
had_install=0

msg() {
    local key="$1"; shift || true
    local en cn
    case "$key" in
        usage)
            en="Usage: install-openfuse-macos.sh [--app PATH] [--release TAG] [--prefix DIR] [--sign adhoc|local] [--no-launch] [--lang en|zh-CN] [--help]"
            cn="用法：install-openfuse-macos.sh [--app 本地zip或.app] [--release 标签] [--prefix 目录] [--sign adhoc|local] [--no-launch] [--lang en|zh-CN] [--help]"
            ;;
        downloading) en="[1/5] Downloading the OpenFuse release…"; cn="[1/5] 正在下载 OpenFuse 安装包…" ;;
        verifying)   en="[2/5] Verifying SHA-256 and the app bundle…"; cn="[2/5] 正在校验 SHA-256 与应用包…" ;;
        signing)     en="[3/5] Signing the app…"; cn="[3/5] 正在签名…" ;;
        installing)  en="[4/5] Installing into %s…"; cn="[4/5] 正在安装到 %s…" ;;
        done)        en="[5/5] OpenFuse is installed."; cn="[5/5] OpenFuse 安装完成。" ;;
        no_permissions)
            en="OpenFuse needs no Accessibility / Screen Recording grants. If macOS asks for Keychain access after an ad-hoc update, choose “Always Allow” once — or reinstall with --sign local so updates reuse one identity."
            cn="OpenFuse 不需要辅助功能或屏幕录制权限。若 ad-hoc 升级后 macOS 询问钥匙串访问，点一次“始终允许”即可；或用 --sign local 重装，让以后升级复用同一签名身份。"
            ;;
        verify_failed) en="SHA-256 verification failed. Nothing was installed."; cn="SHA-256 校验失败，未安装任何内容。" ;;
        download_failed) en="Download failed. Check the network / gh login and retry."; cn="下载失败，请检查网络或 gh 登录后重试。" ;;
        bundle_invalid) en="The app bundle is invalid or has the wrong bundle identifier. Nothing was installed."; cn="应用包无效或 bundle id 不匹配，未安装任何内容。" ;;
        signing_failed) en="Signing failed. Nothing was installed."; cn="签名失败，未安装任何内容。" ;;
        identity_missing) en="No “%s” identity found. Run once with --sign local to create it."; cn="未找到“%s”签名身份。先运行一次 --sign local 创建它。" ;;
        rollback) en="Install failed; the previous version was restored."; cn="安装失败，已恢复上一版本。" ;;
        installed_ok) en="Installed %s (%s) at %s"; cn="已安装 %s（%s）：%s" ;;
        data_kept) en="User data kept: %s sources, %s Keychain credential(s), playback history %s."; cn="用户数据保留：来源 %s 个、Keychain 凭据 %s 条、观看记录 %s。" ;;
        data_none) en="No sources configured yet; nothing to migrate."; cn="尚未添加来源，无需迁移。" ;;
        gh_needed) en="The repository is private: install or log in to gh first (brew install gh && gh auth login), or pass --app with a local zip."; cn="仓库是私有的：请先安装并登录 gh（brew install gh && gh auth login），或用 --app 指定本地 zip。" ;;
        help_tail)
            en="After installing: open OpenFuse, add WebDAV / Jellyfin sources, credentials go to the login Keychain by default."
            cn="安装后：打开 OpenFuse，添加 WebDAV / Jellyfin 来源，凭据默认写入登录钥匙串。"
            ;;
        upgrade_note)
            en="Replacing an existing installation; this is an in-place upgrade."
            cn="检测到已安装版本，将原地升级。"
            ;;
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
            printf 'backup kept at %s\n' "$backup_dir"
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

while [ $# -gt 0 ]; do
    case "$1" in
        --app) LOCAL_SOURCE="${2:-}"; shift 2 ;;
        --release) RELEASE_TAG="${2:-}"; shift 2 ;;
        --prefix) PREFIX="${2:-}"; PREFIX_SET=1; shift 2 ;;
        --sign) SIGN_MODE="${2:-}"; shift 2 ;;
        --no-launch) LAUNCH=0; shift ;;
        --lang) LANG_MODE="${2:-}"; shift 2 ;;
        --keep-backup) KEEP_BACKUP=1; shift ;;
        -h|--help) select_language; msg usage; echo; msg help_tail; exit 0 ;;
        *) echo "unknown option: $1" >&2; msg usage >&2; exit 2 ;;
    esac
done

case "$SIGN_MODE" in adhoc|local) ;; *) echo "unknown --sign value: $SIGN_MODE" >&2; exit 2 ;; esac

select_language
work=$(mktemp -d "${TMPDIR:-/tmp}/openfuse-install.XXXXXX")

# --- download -------------------------------------------------------------

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
    local tag="$1" dir="$2" name="$3"
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh release download "$tag" -R "$REPO" -p "$name" -p "$name.sha256" -D "$dir" >/dev/null 2>&1 && return 0
    fi
    local base="https://github.com/${REPO}/releases/download/${tag}"
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 600 --retry 2 --output "$dir/$name" "$base/$name" || return 1
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 600 --output "$dir/$name.sha256" "$base/$name.sha256" || return 1
}

# --- local signing identity ----------------------------------------------

login_keychain() {
    security default-keychain 2>/dev/null | tr -d '"' || true
}

create_local_identity() {
    local login tmp cert key p12 pass fp
    login=$(login_keychain)
    [ -n "$login" ] || return 1
    tmp="$work/identity"
    mkdir -p "$tmp"
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
    security import "$p12" -k "$login" -P "$pass" -T /usr/bin/codesign >/dev/null 2>&1 || return 1
    unset pass
    # Trust prompt: macOS asks once. The identity is reused by later upgrades.
    security add-trusted-cert -r trustRoot -k "$login" "$cert" >/dev/null 2>&1 || return 1
    fp=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$CERT_CN" | head -1 | awk '{print $2}')
    [ -n "$fp" ] || return 1
    echo "$fp"
}

sign_staged_app() {
    local app="$1"
    xattr -dr com.apple.quarantine "$app" >/dev/null 2>&1 || true
    if [ "$SIGN_MODE" = "adhoc" ]; then
        codesign --force --deep --sign - --timestamp=none "$app" >/dev/null 2>&1 || return 1
    else
        local identity
        identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$CERT_CN" | head -1 | awk '{print $2}')
        if [ -z "$identity" ]; then
            identity=$(create_local_identity) || return 1
        fi
        codesign --force --deep --sign "$identity" --timestamp=none "$app" >/dev/null 2>&1 || return 1
    fi
    codesign --verify --deep --strict "$app" >/dev/null 2>&1
}

# --- install --------------------------------------------------------------

quit_running() {
    pgrep -x "$EXECUTABLE" >/dev/null 2>&1 || return 0
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    local i=0
    while pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i+1)); done
    pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
    sleep 1
    ! pgrep -x "$EXECUTABLE" >/dev/null 2>&1
}

count_keychain_credentials() {
    security dump-keychain 2>/dev/null | grep -c 'svce"<blob>="com.openfuse\.' || true
}

install_app() {
    local staged="$work/staged/$PRODUCT.app" zip="" expected="" actual="" version commit destination_dir destination tmpdst
    local sources_count="0" keychain_count="0" playback_state="missing"

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
        if [ -z "$tag" ]; then
            if command -v gh >/dev/null 2>&1; then die download_failed; else die gh_needed; fi
        fi
        name=$(gh release view "$tag" -R "$REPO" --json assets -q '.assets[].name' 2>/dev/null | grep -E "^${ASSET_PREFIX}.*\.zip$" | head -1 || true)
        if [ -z "$name" ]; then
            if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then die gh_needed; fi
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

    # Record user data before touching the bundle so the summary can prove it survived.
    if [ -f "$HOME/Library/Application Support/OpenFuse/sources.json" ]; then
        sources_count=$(/usr/bin/python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("sources",[])))' "$HOME/Library/Application Support/OpenFuse/sources.json" 2>/dev/null || echo 0)
    fi
    keychain_count=$(count_keychain_credentials)
    [ -f "$HOME/Library/Application Support/OpenFuse/playback.json" ] && playback_state="present"

    sayf installing "$destination_dir"
    if [ -d "$destination" ]; then
        had_install=1
        backup_dir="$work/backup"
        mkdir -p "$backup_dir"
        ditto "$destination" "$backup_dir/$PRODUCT.app" || die bundle_invalid
    fi

    tmpdst="$destination_dir/.$PRODUCT.app.new.$$"
    rm -rf "$tmpdst"
    if ! ditto "$staged" "$tmpdst"; then
        rm -rf "$tmpdst"; [ -n "$backup_dir" ] && [ -d "$backup_dir/$PRODUCT.app" ] && ditto "$backup_dir/$PRODUCT.app" "$destination" || true
        die bundle_invalid
    fi
    if [ -d "$destination" ]; then
        if ! rm -rf "$destination" || ! mv "$tmpdst" "$destination"; then
            rm -rf "$destination" 2>/dev/null || true
            [ -d "$backup_dir/$PRODUCT.app" ] && ditto "$backup_dir/$PRODUCT.app" "$destination" || true
            warn rollback
            exit 1
        fi
    else
        mv "$tmpdst" "$destination" || { rm -rf "$tmpdst"; die bundle_invalid; }
    fi

    # Verify the installed copy and the preserved user data.
    [ "$(plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] || die bundle_invalid
    codesign --verify --deep --strict "$destination" >/dev/null 2>&1 || die bundle_invalid

    local after_sources="0" after_keychain="0" after_playback="missing"
    if [ -f "$HOME/Library/Application Support/OpenFuse/sources.json" ]; then
        after_sources=$(/usr/bin/python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("sources",[])))' "$HOME/Library/Application Support/OpenFuse/sources.json" 2>/dev/null || echo 0)
    fi
    after_keychain=$(count_keychain_credentials)
    [ -f "$HOME/Library/Application Support/OpenFuse/playback.json" ] && after_playback="present"

    if [ "$after_sources" = "$sources_count" ] && [ "$after_keychain" = "$keychain_count" ] && [ "$after_playback" = "$playback_state" ]; then
        sayf installed_ok "$version" "$commit" "$destination"
        sayf data_kept "$after_sources" "$after_keychain" "$after_playback"
    else
        sayf installed_ok "$version" "$commit" "$destination"
        printf 'warning: user data changed during install (sources %s→%s, keychain %s→%s, playback %s→%s)\n' \
            "$sources_count" "$after_sources" "$keychain_count" "$after_keychain" "$playback_state" "$after_playback" >&2
    fi

    [ "$LAUNCH" = "1" ] && open "$destination" >/dev/null 2>&1 || true
    msg no_permissions
}

install_app
