#!/bin/bash
#
# OpenFuse for macOS — installer
#
# Downloads the latest release, verifies its SHA-256, signs the app with a
# persistent local code-signing identity (no Apple Developer account needed)
# and installs it into /Applications.
#
# The identity lives in the login Keychain and is reused for every update, so
# macOS keeps the Keychain ACL of the existing credentials across versions. The
# downloaded app is ad-hoc signed; only this installer re-signs it with the
# local identity.
#
# Compatible with the macOS system Bash 3.2.
#
set -Eeuo pipefail

# Ignore caller-controlled executable search paths, but keep the Homebrew
# locations so `gh` (needed for this private repository) can be found.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
umask 077

REPO="kaiwenyao/openfuse"
ASSET_ZIP="OpenFuse-macos.zip"
ASSET_SUM="OpenFuse-macos.zip.sha256"

PRODUCT="OpenFuse"
BUNDLE_ID="com.openfuse.app"
EXECUTABLE="OpenFuse"
CERT_CN="OpenFuse Local Signing"
MIN_MACOS_MAJOR=14
SUPPORT_DIR="$HOME/Library/Application Support/OpenFuse"

PREFIX="/Applications"
PREFIX_SET=0
LAUNCH=1
SIGN_MODE="local"     # local (default, persistent identity) | adhoc (explicit, re-grant)
RESET_IDENTITY=0
LANG_MODE="auto"
LOCAL_SOURCE=""
MODE="install"

work=""
backup_dir=""

# Signing globals set by ensure_identity / sign_app.
IDENTITY_FP=""
SIGN_KEYCHAIN=""
SIGN_RESULT=""
SIGNED_FINGERPRINT=""

# --------------------------------------------------------------------------
# messaging
# --------------------------------------------------------------------------

msg() {
    local key="$1"
    local en cn
    case "$key" in
        usage)
            en="Usage: install-openfuse-macos.sh [--no-launch] [--prefix DIR] [--sign local|adhoc] [--reset-identity] [--app PATH] [--release TAG] [--uninstall] [--lang en|zh-CN] [--help]"
            cn="用法:install-openfuse-macos.sh [--no-launch] [--prefix 目录] [--sign local|adhoc] [--reset-identity] [--app 本地.app或zip] [--release 标签] [--uninstall] [--lang en|zh-CN] [--help]"
            ;;
        downloading)
            en="[1/5] Downloading the latest OpenFuse build…"
            cn="[1/5] 正在下载最新 OpenFuse 安装包…"
            ;;
        verifying)
            en="[2/5] Verifying checksum and app bundle…"
            cn="[2/5] 正在校验 SHA-256 与应用包…"
            ;;
        signing)
            en="[3/5] Signing the app locally…"
            cn="[3/5] 正在本地签名…"
            ;;
        installing)
            en="[4/5] Installing into %s…"
            cn="[4/5] 正在安装到 %s…"
            ;;
        done)
            en="[5/5] OpenFuse is installed."
            cn="[5/5] OpenFuse 安装完成。"
            ;;
        permission)
            en="OpenFuse needs no Accessibility, Input Monitoring or Screen Recording grants. Credentials stay in the login Keychain; the first time macOS asks for keychain access after an update, choose “Always Allow”."
            cn="OpenFuse 不需要辅助功能、输入监控或屏幕录制权限。凭据保存在登录钥匙串；升级后第一次询问钥匙串访问时，选择“始终允许”即可。"
            ;;
        permission_retained)
            en="The signing identity was reused, so existing Keychain access should continue to work."
            cn="签名身份已复用，原有钥匙串访问应当继续有效。"
            ;;
        migration_permission)
            en="This update moves OpenFuse from an ad-hoc signature to a persistent local identity. macOS may ask for Keychain access once; future updates reuse this identity and will not ask again."
            cn="本次更新把 OpenFuse 从 ad-hoc 签名切换为持久本地身份。macOS 可能询问一次钥匙串访问；以后升级会复用该身份，不再询问。"
            ;;
        usage_tip)
            en="Open OpenFuse, tap “添加来源” and add your WebDAV / Jellyfin server; credentials go to the login Keychain."
            cn="打开 OpenFuse，点“添加来源”添加 WebDAV / Jellyfin 服务器；凭据写入登录钥匙串。"
            ;;
        keychain_prompt)
            en="Creating a 10-year self-signed code-signing certificate in your login Keychain. macOS may request a trust confirmation once; this identity is reused on future updates."
            cn="正在登录钥匙串中创建 10 年期自签代码签名证书。macOS 可能请求一次信任确认；以后升级会复用该身份。"
            ;;
        verify_failed)
            en="Checksum verification failed. The download was corrupted or tampered with; nothing was installed."
            cn="SHA-256 校验失败:下载文件损坏或被篡改,未安装任何内容。"
            ;;
        download_failed)
            en="Download failed. Check your network and try again (or install offline with --app <zip>)."
            cn="下载失败,请检查网络后重试(也可用 --app <zip> 离线安装)。"
            ;;
        bundle_invalid)
            en="The downloaded app bundle is invalid or has the wrong bundle identifier; nothing was installed."
            cn="下载的应用包无效或 bundle identifier 不匹配,未安装任何内容。"
            ;;
        signing_failed)
            en="Signing with the persistent identity failed; nothing was installed. Unlock the login Keychain and retry. Do not delete the signing state unless you accept re-approving Keychain access; use --sign adhoc only as a last resort."
            cn="使用持久身份签名失败,未安装任何内容。请解锁登录钥匙串后重试。除非接受重新确认钥匙串访问,否则不要删除签名状态;仅作为最后手段使用 --sign adhoc。"
            ;;
        trust_failed)
            en="macOS did not trust the signing certificate for code signing, so nothing was installed. Unlock the login Keychain, re-run, and approve the trust prompt. Use --sign adhoc only if you accept re-approving Keychain access after updates."
            cn="macOS 未将该证书加入代码签名信任,因此未安装任何内容。请解锁登录钥匙串后重试,并允许系统信任提示。仅当你接受每次升级后重新确认钥匙串访问时,才使用 --sign adhoc。"
            ;;
        keychain_locked)
            en="The login Keychain is locked or the signing key is not accessible. Unlock the login Keychain in Keychain Access and run the installer again."
            cn="登录钥匙串已锁定,或签名私钥不可访问。请在“钥匙串访问”中解锁登录钥匙串后重新运行安装器。"
            ;;
        identity_failed)
            en="Could not create the local signing identity; nothing was installed. Check that the login Keychain is unlocked and try again."
            cn="无法创建本地签名身份,未安装任何内容。请确认登录钥匙串已解锁后重试。"
            ;;
        identity_interrupted)
            en="A previous signing-identity creation was interrupted. Re-run with --reset-identity to create a new identity (macOS will ask for Keychain access once)."
            cn="上一次签名身份创建被中断。请使用 --reset-identity 重新创建身份(需要重新确认一次钥匙串访问)。"
            ;;
        identity_missing)
            en="The saved signing identity is missing or unusable, but a saved requirement exists. To protect Keychain continuity, nothing was installed. Restore the original certificate and private key, or re-run with --reset-identity."
            cn="已保存的签名身份缺失或不可用,但存在已保存的 requirement。为保护钥匙串连续性,未安装任何内容。请恢复原证书和私钥,或使用 --reset-identity。"
            ;;
        identity_ambiguous)
            en="Multiple OpenFuse signing identities are trusted in the login Keychain, so the installer cannot safely choose one. Inspect them in Keychain Access, or re-run with --reset-identity."
            cn="登录钥匙串中存在多个受信任的 OpenFuse 签名身份,安装器无法安全选择。请在“钥匙串访问”中检查,或使用 --reset-identity。"
            ;;
        legacy_state_archived)
            en="An incomplete legacy signing state was found and archived; a new login-Keychain identity will be created."
            cn="检测到不完整的旧版签名状态,已归档;将创建新的登录钥匙串身份。"
            ;;
        continuity_failed)
            en="The new app does not satisfy the saved signing requirement, so installation stopped to protect Keychain continuity. Restore the original signing identity, or re-run with --reset-identity."
            cn="新应用不满足已保存的签名 requirement,为保护钥匙串连续性已停止安装。请恢复原签名身份,或使用 --reset-identity。"
            ;;
        identity_change_warning)
            en="Warning: the installed OpenFuse was signed by a different identity (possibly another macOS user). Replacing it will change the signature and may require approving Keychain access once. Use the account that installed OpenFuse to preserve it."
            cn="警告:已安装的 OpenFuse 由另一张证书签名(可能是另一个 macOS 用户安装的)。替换后会改变签名,可能需要重新确认一次钥匙串访问。请用最初安装 OpenFuse 的系统用户执行更新。"
            ;;
        adhoc_warning)
            en="Signed ad-hoc as requested. This does not preserve Keychain continuity: macOS may ask you to approve keychain access after each update. Re-run without --sign adhoc to use the persistent identity."
            cn="已按请求使用 ad-hoc 签名。此方式不会保持钥匙串连续性:每次升级后 macOS 可能要求确认钥匙串访问。若要使用持久身份,请不要加 --sign adhoc。"
            ;;
        duplicate_install)
            en="Both %s/OpenFuse.app and ~/Applications/OpenFuse.app exist; updating %s. Remove the extra copy to avoid launching the wrong one."
            cn="%s/OpenFuse.app 与 ~/Applications/OpenFuse.app 同时存在;将更新 %s。请移除多余副本,避免启动错误的应用。"
            ;;
        reset_done)
            en="The previous signing identity was removed. A new identity will be created; macOS may ask for Keychain access once."
            cn="已移除旧签名身份。将创建新身份;macOS 可能要求确认一次钥匙串访问。"
            ;;
        macos_too_old)
            en="OpenFuse requires macOS %s or later."
            cn="OpenFuse 需要 macOS %s 或更新版本。"
            ;;
        no_root)
            en="Run this script as your desktop user, without sudo."
            cn="请以当前桌面用户运行本脚本,不要使用 sudo。"
            ;;
        arch_unsupported)
            en="Unsupported CPU architecture; OpenFuse ships for Apple Silicon and Intel."
            cn="不支持的 CPU 架构;OpenFuse 支持 Apple Silicon 与 Intel。"
            ;;
        not_writable)
            en="%s is not writable; installing into ~/Applications instead."
            cn="%s 不可写,改为安装到 ~/Applications。"
            ;;
        quit_failed)
            en="A running OpenFuse did not quit. Quit it manually and run this installer again."
            cn="正在运行的 OpenFuse 未能退出,请手动退出后重新运行安装器。"
            ;;
        uninstall_done)
            en="OpenFuse has been removed, including its local signing identity. Your sources, Keychain items and playback history under %s were kept."
            cn="OpenFuse 已卸载,本地签名身份也已移除。%s 下的来源、钥匙串凭据和观看记录都保留。"
            ;;
        gh_needed)
            en="This app lives in a private repository: install gh and run “gh auth login”, or install offline with --app <zip>."
            cn="应用位于私有仓库：请安装 gh 并执行 gh auth login，或用 --app <zip> 离线安装。"
            ;;
        uninstall_missing)
            en="OpenFuse.app is not installed; nothing to remove."
            cn="未找到已安装的 OpenFuse.app,无需卸载。"
            ;;
        failed)
            en="Installation failed. The previous version was restored; nothing was left half-installed."
            cn="安装失败,已恢复上一版本,未留下半装状态。"
            ;;
        data_summary)
            en="User data kept: %s sources, %s Keychain credential(s), playback history %s."
            cn="用户数据保留:来源 %s 个、钥匙串凭据 %s 条、观看记录 %s。"
            ;;
        installed_summary)
            en="Installed %s (%s) at %s"
            cn="已安装 %s(%s):%s"
            ;;
        *)
            return 1
            ;;
    esac
    case "$LANG_MODE" in
        zh-CN) printf '%s\n' "$cn" ;;
        *) printf '%s\n' "$en" ;;
    esac
}

# Step lines are highlighted the same way as the AnyPaste installer: bold
# cyan on a terminal, reset immediately after the line. Redirected output,
# scripts and CI stay plain; NO_COLOR (https://no-color.org) disables it too.
step_color_start() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[1;36m'; fi
}

step_color_end() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[0m'; fi
}

say() {
    local text
    if text=$(msg "$1"); then
        step_color_start
        printf '%s\n' "$text"
        step_color_end
    fi
}

sayf() {
    local key="$1"; shift
    local text
    if text=$(msg "$key"); then
        step_color_start
        # shellcheck disable=SC2059
        printf "$text\n" "$@"
        step_color_end
    fi
}

warn() {
    local text
    if text=$(msg "$1"); then
        printf '%s\n' "$text" >&2
    fi
}

die() {
    warn "$1"
    exit 1
}

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

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

cleanup() {
    local status=$?
    if [ -n "$work" ] && [ -d "$work" ]; then
        rm -rf "$work" 2>/dev/null || true
    fi
    return "$status"
}

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

macos_major() {
    sw_vers -productVersion 2>/dev/null | cut -d. -f1
}

# Resolve the newest release tag through the API and download from that
# immutable tag URL. Private repository: `gh release download` is preferred.
resolve_base() {
    local tag=""
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        tag=$(gh release view -R "$REPO" --json tagName -q .tagName 2>/dev/null || true)
    fi
    if [ -z "$tag" ] && command -v curl >/dev/null 2>&1; then
        tag=$(curl --fail --silent --show-error --location --max-time 20 \
            --proto '=https' --proto-redir '=https' \
            "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    fi
    if [ -n "$tag" ]; then
        printf 'release:%s\n' "$tag"
    else
        printf 'latest\n'
    fi
}

fetch() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --silent --show-error --location \
            --proto '=https' --proto-redir '=https' \
            --connect-timeout 15 --max-time 600 --retry 2 --retry-max-time 120 \
            --output "$out" "$url"
        return $?
    fi
    return 1
}

fetch_release() {
    local base="$1" name="$2" dir="$3" tag url
    case "$base" in
        release:*) tag="${base#release:}"
            if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
                gh release download "$tag" -R "$REPO" -p "$name" -D "$dir" >/dev/null 2>&1 && return 0
            fi
            url="https://github.com/${REPO}/releases/download/${tag}/${name}"
            ;;
        *) url="https://github.com/${REPO}/releases/latest/download/${name}" ;;
    esac
    fetch "$url" "$dir/$name"
}

quit_running() {
    if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        local i=0
        while pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
            sleep 0.25
            i=$((i + 1))
        done
        if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
            pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
            sleep 1
        fi
        if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
            die quit_failed
        fi
    fi
}

count_sources() {
    local file="$SUPPORT_DIR/sources.json"
    [ -f "$file" ] || { printf '0\n'; return; }
    /usr/bin/python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("sources",[])))' "$file" 2>/dev/null || printf '0\n'
}

count_keychain_credentials() {
    security dump-keychain 2>/dev/null | grep -c 'svce"<blob>="com.openfuse\.' || true
}

# --------------------------------------------------------------------------
# local signing identity (no Apple Developer account required)
# --------------------------------------------------------------------------

login_keychain() {
    security default-keychain 2>/dev/null | tr -d '"' | xargs || true
}

state_dir() {
    printf '%s\n' "$SUPPORT_DIR/Installer"
}

is_fingerprint() {
    case "$1" in
        ""|*[!0-9A-Fa-f]*) return 1 ;;
    esac
    [ "${#1}" -eq 40 ]
}

normalize_fp() {
    printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]'
}

read_state_fp() {
    local dir="$1" raw
    [ -s "$dir/signing-identity" ] || return 1
    raw=$(tr -d '[:space:]' < "$dir/signing-identity" 2>/dev/null || true)
    is_fingerprint "$raw" || return 1
    normalize_fp "$raw"
}

identity_is_trusted() {
    local fp="$1"
    [ -n "$fp" ] || return 1
    security find-identity -v -p codesigning 2>/dev/null | grep -qi "$fp"
}

identity_probe() {
    local fp="$1" probe rc
    probe=$(mktemp "${TMPDIR:-/tmp}/openfuse-probe.XXXXXX") || return 1
    cp /bin/echo "$probe" 2>/dev/null || { rm -f "$probe"; return 1; }
    if run_with_timeout 30 codesign --force --sign "$fp" "$probe" >/dev/null 2>&1; then
        rc=0
    else
        rc=1
    fi
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
        if identity_is_trusted "$fp"; then
            return 0
        fi
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}

# Prints one "fingerprint|CN" record per valid identity in the keychain.
identities_by_cn() {
    local out
    out=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-Fa-f]\{40\}\) "\(.*\)"$/\1|\2/p' || true)
    printf '%s\n' "$out" | grep -F "|$CERT_CN" | cut -d'|' -f1 || true
}

count_identities_by_cn() {
    local count
    count=$(identities_by_cn | grep -c . 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

archive_state() {
    local state suffix f
    state=$(state_dir)
    [ -d "$state" ] || return 0
    suffix=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo legacy)
    for f in signing-identity signing-requirement signing-certificate.pem signing-creating; do
        if [ -e "$state/$f" ]; then
            mv -f "$state/$f" "$state/$f.legacy-$suffix" 2>/dev/null || true
        fi
    done
}

delete_certs_by_cn() {
    local hashes h
    hashes=$(security find-certificate -c "$CERT_CN" -Z 2>/dev/null \
        | sed -n 's/^SHA-1 hash: //p' || true)
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
    archive_state
    rm -f "$state/signing-creating" 2>/dev/null || true
    say reset_done
}

create_identity() {
    local state tmp cert key p12 pass fingerprint
    state=$(state_dir)
    tmp="$work/identity"
    rm -rf "$tmp"
    mkdir -p "$tmp" || die identity_failed
    mkdir -p "$state" 2>/dev/null || die identity_failed
    chmod 700 "$state" 2>/dev/null || true
    : > "$state/signing-creating" 2>/dev/null || die identity_failed

    say keychain_prompt

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

    if ! openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
        -config "$tmp/cert.cnf" -keyout "$key" -out "$cert" >/dev/null 2>&1; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi

    pass=$(openssl rand -hex 24 2>/dev/null || true)
    if [ -z "$pass" ]; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    if ! openssl pkcs12 -export -inkey "$key" -in "$cert" \
        -name "$CERT_CN" -out "$p12" -passout "pass:$pass" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    if ! run_with_timeout 120 security import "$p12" -k "$(login_keychain)" -P "$pass" \
        -T /usr/bin/codesign >/dev/null 2>&1; then
        unset pass
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    unset pass

    fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 2>/dev/null \
        | sed 's/.*=//; s/://g')
    if ! is_fingerprint "$fingerprint"; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    fingerprint=$(normalize_fp "$fingerprint")

    # Write the fingerprint/certificate before requesting trust so an
    # interrupted trust prompt can be resumed without creating a second identity.
    printf '%s\n' "$fingerprint" > "$state/signing-identity" 2>/dev/null || die identity_failed
    cp "$cert" "$state/signing-certificate.pem" 2>/dev/null || die identity_failed
    rm -f "$state/signing-creating"

    if ! trust_identity "$state/signing-certificate.pem" "$fingerprint"; then
        die trust_failed
    fi
    if ! identity_probe "$fingerprint"; then
        die keychain_locked
    fi

    IDENTITY_FP="$fingerprint"
    SIGN_KEYCHAIN=$(login_keychain)
}

ensure_identity() {
    local state fp count
    state=$(state_dir)

    mkdir -p "$state" 2>/dev/null || die identity_failed
    chmod 700 "$state" 2>/dev/null || true

    if fp=$(read_state_fp "$state"); then
        if [ ! -s "$state/signing-certificate.pem" ]; then
            count=$(count_identities_by_cn)
            if [ "${count:-0}" -eq 1 ]; then
                security find-certificate -c "$CERT_CN" -p > "$state/signing-certificate.pem" 2>/dev/null || true
            fi
        fi
        [ -s "$state/signing-certificate.pem" ] || die identity_missing
        if ! identity_is_trusted "$fp"; then
            trust_identity "$state/signing-certificate.pem" "$fp" || die trust_failed
        fi
        if ! identity_probe "$fp"; then
            die keychain_locked
        fi
        IDENTITY_FP="$fp"
        SIGN_KEYCHAIN=$(login_keychain)
        return 0
    fi

    # No usable identity state. Never silently replace an identity that was
    # protecting an existing Keychain grant.
    if [ -s "$state/signing-requirement" ]; then
        die identity_missing
    fi
    if [ -e "$state/signing-creating" ]; then
        die identity_interrupted
    fi

    # Recover an identity whose state directory was removed but whose trusted
    # certificate still lives in the login Keychain.
    count=$(count_identities_by_cn)
    if [ "${count:-0}" -eq 1 ]; then
        fp=$(identities_by_cn | head -1)
        security find-certificate -c "$CERT_CN" -p > "$state/signing-certificate.pem" 2>/dev/null || true
        if [ -s "$state/signing-certificate.pem" ] && identity_probe "$fp"; then
            printf '%s\n' "$fp" > "$state/signing-identity"
            IDENTITY_FP="$fp"
            SIGN_KEYCHAIN=$(login_keychain)
            return 0
        fi
        rm -f "$state/signing-identity" "$state/signing-certificate.pem"
        die identity_missing
    elif [ "${count:-0}" -gt 1 ]; then
        die identity_ambiguous
    fi

    create_identity
}

# Signs the staged app. Sets SIGN_RESULT and SIGNED_FINGERPRINT; returns
# non-zero on failure. Never falls back from local to ad-hoc.
sign_app() {
    local app="$1" state requirement saved
    state=$(state_dir)

    if [ "$SIGN_MODE" = "local" ]; then
        ensure_identity || return 1
        [ -n "$IDENTITY_FP" ] || return 1
        [ -n "$SIGN_KEYCHAIN" ] || SIGN_KEYCHAIN=$(login_keychain)

        if ! run_with_timeout 90 codesign --force --sign "$IDENTITY_FP" --keychain "$SIGN_KEYCHAIN" \
            --identifier "$BUNDLE_ID" --timestamp=none "$app" >/dev/null 2>&1; then
            return 1
        fi
        if ! run_with_timeout 60 codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
            return 1
        fi

        requirement=$(codesign -d -r- "$app" 2>/dev/null \
            | sed -n 's/^#\{0,1\}[[:space:]]*designated => //p' | head -1 || true)
        case "$requirement" in
            ""|*cdhash*) die continuity_failed ;;
            *certificate*) ;;
            *) die continuity_failed ;;
        esac

        if [ -s "$state/signing-requirement" ]; then
            saved=$(tr -d '\r\n' < "$state/signing-requirement" 2>/dev/null || true)
            if [ -n "$saved" ] \
                && ! run_with_timeout 60 codesign --verify --strict -R "=$saved" "$app" >/dev/null 2>&1; then
                die continuity_failed
            fi
        fi

        printf '%s\n' "$requirement" > "$state/signing-requirement.tmp" 2>/dev/null || die signing_failed
        mv -f "$state/signing-requirement.tmp" "$state/signing-requirement" 2>/dev/null || die signing_failed

        SIGN_RESULT="local"
        SIGNED_FINGERPRINT="$IDENTITY_FP"
        return 0
    fi

    if ! run_with_timeout 60 codesign --force --deep --sign - "$app" >/dev/null 2>&1; then
        return 1
    fi
    if ! run_with_timeout 60 codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
        return 1
    fi
    SIGN_RESULT="adhoc"
    SIGNED_FINGERPRINT=""
    return 0
}

restore_backup() {
    rm -rf "$destination" 2>/dev/null || true
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        mv "$backup_dir" "$destination" 2>/dev/null || true
        backup_dir=""
    fi
}

# --------------------------------------------------------------------------
# install / uninstall
# --------------------------------------------------------------------------

install_app() {
    local source_zip="" staged="$work/staged/$PRODUCT.app"
    local state destination_dir destination sign_result signed_fp
    local had_install=0 had_requirement=0 installed_matches_identity=0 installed_was_adhoc=0
    local installed_req installed_fp requirement version commit
    local sources_before keychain_before playback_before sources_after keychain_after playback_after

    state=$(state_dir)

    # Keep the existing install path so the Keychain grant stays with the app.
    destination_dir="$PREFIX"
    if [ "$PREFIX_SET" = "0" ] && [ ! -d "/Applications/$PRODUCT.app" ] \
        && [ -d "$HOME/Applications/$PRODUCT.app" ]; then
        destination_dir="$HOME/Applications"
    fi
    destination="$destination_dir/$PRODUCT.app"
    [ -d "$destination" ] && had_install=1
    [ -s "$state/signing-requirement" ] && had_requirement=1

    if [ -n "$LOCAL_SOURCE" ]; then
        if [ -d "$LOCAL_SOURCE" ]; then
            mkdir -p "$work/staged"
            ditto "$LOCAL_SOURCE" "$staged" >/dev/null 2>&1 || die bundle_invalid
        elif [ -f "$LOCAL_SOURCE" ]; then
            source_zip="$LOCAL_SOURCE"
        else
            die download_failed
        fi
    else
        say downloading
        local base
        base=$(resolve_base)
        fetch_release "$base" "$ASSET_ZIP" "$work" || die download_failed
        fetch_release "$base" "$ASSET_SUM" "$work" || die download_failed
        source_zip="$work/$ASSET_ZIP"
    fi

    say verifying
    if [ -n "$source_zip" ]; then
        local expected actual
        expected=""
        if [ -f "$source_zip.sha256" ]; then
            expected=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$source_zip.sha256" | head -1)
        elif [ -f "$work/$ASSET_SUM" ]; then
            expected=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$work/$ASSET_SUM" | head -1)
        fi
        [ -n "$expected" ] || die verify_failed
        actual=$(shasum -a 256 "$source_zip" | awk '{print $1}')
        [ "$actual" = "$expected" ] || die verify_failed

        mkdir -p "$work/staged"
        ditto -x -k "$source_zip" "$work/staged" >/dev/null 2>&1 || die bundle_invalid
    fi

    [ -x "$staged/Contents/MacOS/$EXECUTABLE" ] || die bundle_invalid
    plutil -lint "$staged/Contents/Info.plist" >/dev/null 2>&1 || die bundle_invalid
    [ "$(plutil -extract CFBundleIdentifier raw "$staged/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] || die bundle_invalid
    /usr/bin/codesign --verify --deep --strict "$staged" >/dev/null 2>&1 || die bundle_invalid
    version=$(plutil -extract CFBundleShortVersionString raw "$staged/Contents/Info.plist" 2>/dev/null || echo unknown)
    commit=$(plutil -extract OpenFuseCommit raw "$staged/Contents/Info.plist" 2>/dev/null || echo unknown)

    say signing
    xattr -dr com.apple.quarantine "$staged" >/dev/null 2>&1 || true
    if ! sign_app "$staged"; then
        die signing_failed
    fi
    sign_result="$SIGN_RESULT"
    signed_fp="$SIGNED_FINGERPRINT"

    if [ "$had_install" = "1" ] && [ -n "$signed_fp" ]; then
        installed_req=$(codesign -d -r- "$destination" 2>/dev/null \
            | sed -n 's/^#\{0,1\}[[:space:]]*designated => //p' | head -1 || true)
        installed_fp=""
        case "$installed_req" in
            *cdhash*)
                installed_was_adhoc=1
                ;;
            *certificate*)
                installed_fp=$(printf '%s\n' "$installed_req" \
                    | sed -E 's/.*certificate (leaf|root) = H"([0-9A-Fa-f]*)".*/\2/p' | head -1 || true)
                if [ -n "$installed_fp" ] \
                    && [ "$(normalize_fp "$installed_fp")" = "$(normalize_fp "$signed_fp")" ]; then
                    installed_matches_identity=1
                elif [ -n "$installed_fp" ]; then
                    warn identity_change_warning
                fi
                ;;
        esac
    fi

    if [ ! -w "$destination_dir" ]; then
        mkdir -p "$destination_dir" 2>/dev/null || true
    fi
    if [ ! -w "$destination_dir" ]; then
        warn not_writable
        destination_dir="$HOME/Applications"
        destination="$destination_dir/$PRODUCT.app"
        mkdir -p "$destination_dir"
    fi

    if [ "$PREFIX_SET" = "0" ] && [ -d "/Applications/$PRODUCT.app" ] \
        && [ -d "$HOME/Applications/$PRODUCT.app" ]; then
        warn duplicate_install
    fi

    sayf installing "$destination_dir"
    quit_running

    sources_before=$(count_sources)
    keychain_before=$(count_keychain_credentials)
    [ -f "$SUPPORT_DIR/playback.json" ] && playback_before="present" || playback_before="missing"

    if [ -e "$destination" ]; then
        backup_dir="$destination_dir/.${PRODUCT}-previous-$$.app"
        rm -rf "$backup_dir"
        mv "$destination" "$backup_dir" || die failed
    fi

    if ! ditto "$staged" "$destination" >/dev/null 2>&1; then
        restore_backup
        die failed
    fi

    if ! /usr/bin/codesign --verify --deep --strict "$destination" >/dev/null 2>&1; then
        restore_backup
        die failed
    fi

    if [ "$sign_result" = "local" ] && [ -s "$state/signing-requirement" ]; then
        requirement=$(tr -d '\r\n' < "$state/signing-requirement" 2>/dev/null || true)
        if [ -n "$requirement" ] \
            && ! /usr/bin/codesign --verify --strict -R "=$requirement" "$destination" >/dev/null 2>&1; then
            restore_backup
            die continuity_failed
        fi
    fi

    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir" || true
        backup_dir=""
    fi

    xattr -dr com.apple.quarantine "$destination" >/dev/null 2>&1 || true

    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$destination" >/dev/null 2>&1 || true

    sources_after=$(count_sources)
    keychain_after=$(count_keychain_credentials)
    [ -f "$SUPPORT_DIR/playback.json" ] && playback_after="present" || playback_after="missing"

    say done
    sayf installed_summary "$version" "$commit" "$destination"
    if [ "$sources_after" = "$sources_before" ] && [ "$keychain_after" = "$keychain_before" ] \
        && [ "$playback_after" = "$playback_before" ]; then
        sayf data_summary "$sources_after" "$keychain_after" "$playback_after"
    else
        printf 'warning: user data changed during install (sources %s→%s, keychain %s→%s, playback %s→%s)\n' \
            "$sources_before" "$sources_after" "$keychain_before" "$keychain_after" \
            "$playback_before" "$playback_after" >&2
    fi

    case "$sign_result" in
        adhoc)
            warn adhoc_warning
            msg permission
            ;;
        *)
            if [ "$installed_was_adhoc" = "1" ]; then
                msg migration_permission
            elif [ "$had_install" = "1" ] && { [ "$had_requirement" = "1" ] || [ "$installed_matches_identity" = "1" ]; }; then
                msg permission_retained
            elif [ "$had_install" = "1" ]; then
                msg migration_permission
            else
                msg permission
            fi
            ;;
    esac
    msg usage_tip

    if [ "$LAUNCH" = "1" ]; then
        open "$destination" >/dev/null 2>&1 || true
    fi
}

uninstall_app() {
    local state fp destination found=0
    state=$(state_dir)

    quit_running || true

    for destination in "$PREFIX/$PRODUCT.app" "/Applications/$PRODUCT.app" "$HOME/Applications/$PRODUCT.app"; do
        if [ -d "$destination" ]; then
            rm -rf "$destination" 2>/dev/null && found=1
        fi
    done
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

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

while [ $# -gt 0 ]; do
    case "$1" in
        --no-launch) LAUNCH=0 ;;
        --prefix) PREFIX="$2"; PREFIX_SET=1; shift ;;
        --sign) SIGN_MODE="$2"; shift ;;
        --reset-identity) RESET_IDENTITY=1 ;;
        --app) LOCAL_SOURCE="$2"; shift ;;
        --release) RELEASE_TAG="$2"; shift ;;
        --lang) LANG_MODE="$2"; shift ;;
        --uninstall) MODE="uninstall" ;;
        --help|-h) select_language; msg usage; exit 0 ;;
        *) select_language; msg usage >&2; exit 2 ;;
    esac
    shift
done

select_language

case "$SIGN_MODE" in
    local|adhoc) ;;
    *)
        msg usage >&2
        exit 2
        ;;
esac

if [ "$(id -u)" -eq 0 ]; then
    die no_root
fi

case "$(uname -m)" in
    arm64|x86_64) : ;;
    *) die arch_unsupported ;;
esac

if [ "$MODE" = "install" ]; then
    major=$(macos_major)
    if [ -n "$major" ] && [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
        printf "$(msg macos_too_old)\n" "$MIN_MACOS_MAJOR" >&2
        exit 1
    fi
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/openfuse-install.XXXXXX")
trap cleanup EXIT INT TERM
trap 'exit 130' INT TERM

if [ "$MODE" = "uninstall" ]; then
    uninstall_app
else
    if [ "$RESET_IDENTITY" = "1" ]; then
        reset_identity
    fi
    install_app
fi
