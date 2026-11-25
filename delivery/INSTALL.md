# OpenFuse 0.9.3 · macOS 安装

## 包内容

```text
delivery/OpenFuse-macos.zip              28 MB，自包含 libmpv 及依赖，版本 0.9.3（1bb47d0）
delivery/OpenFuse-macos.zip.sha256       4f901226225cd7b20a94869c1c4bad63f6d20721c1926f34e221d7ee67fcf1f0
delivery/install-openfuse-macos.sh       安装/升级脚本
```

校验：

```bash
cd /Users/ykw/Documents/openfuse/delivery
shasum -a 256 -c OpenFuse-macos.zip.sha256
```

## 安装 / 升级

```bash
cd /Users/ykw/Documents/openfuse/delivery
bash install-openfuse-macos.sh --app OpenFuse-macos.zip
```

默认安装到 `/Applications/OpenFuse.app`，安装前备份旧版本，使用本机持久签名身份重签，保留 Keychain 凭据的访问授权。重复执行即升级。

常用选项：

```bash
# 安装到自定义目录且不自动启动
bash install-openfuse-macos.sh --app OpenFuse-macos.zip --prefix "$HOME/Applications" --no-launch

# 无本地签名身份时使用 ad-hoc（更新后可能需要重新确认 Keychain）
bash install-openfuse-macos.sh --app OpenFuse-macos.zip --sign adhoc
```

## 直接解压（不经过安装器）

```bash
ditto -x -k OpenFuse-macos.zip /Applications
xattr -dr com.apple.quarantine /Applications/OpenFuse.app
open /Applications/OpenFuse.app
```

## 运行要求

- macOS 14.0 或更高；本轮实机为 macOS 27.2.1（arm64）。
- 安装包已包含 libmpv、FFmpeg 及全部第三方动态库，不依赖 Homebrew。
- 首次打开会创建 `~/Library/Application Support/OpenFuse`，用于媒体库、播放进度、缩略图缓存和来源配置。

## 安装包实测

- `unzip -t`：无错误。
- `shasum -a 256 -c OpenFuse-macos.zip.sha256`：`OpenFuse-macos.zip: OK`。
- `codesign --verify --deep --strict build/OpenFuse.app`：通过；`otool -L` 无 `/opt/homebrew` 依赖。
- 打包后的自包含应用实际启动并播放换集流程：换集后空格暂停成功（报告 `paused=true`、`userPaused=true`、`mpv v0.42.0`）。
- 离线安装到临时目录（`--prefix /tmp/openfuse-install-093 --no-launch --sign adhoc`）成功，版本 0.9.3（`1bb47d0`）。
