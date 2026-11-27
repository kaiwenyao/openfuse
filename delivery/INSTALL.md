# OpenFuse 0.9.8 · macOS 安装

## 包内容

```text
delivery/OpenFuse-macos.zip              约 30 MiB，自包含 libmpv 及依赖，版本 0.9.8（1934829）
delivery/OpenFuse-macos.zip.sha256       053cca0aab291115bf1bd97b90edc434c7f88cb828a2f16149c98c7444f7e19f
delivery/install-openfuse-macos.sh       安装/升级脚本
```

校验：

```bash
cd delivery
shasum -a 256 -c OpenFuse-macos.zip.sha256
```

## 安装 / 升级

```bash
cd delivery
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

- Apple Silicon。包内 libmpv 的构建目标为 macOS 27.2，本轮在 macOS 27.2.1 验证。
- 安装包内置 libmpv、FFmpeg 及第三方动态库。
- 首次打开会创建 `~/Library/Application Support/OpenFuse`，用于媒体库、播放进度、缩略图缓存和来源配置。

## 安装包实测

- `unzip -t`：无错误。
- `shasum -a 256 -c OpenFuse-macos.zip.sha256`：`OpenFuse-macos.zip: OK`。
- 解包应用通过 `codesign --verify --deep --strict`。`otool -L` 检查了可执行文件和内置动态库，确认依赖已打包。
- 解包应用通过本地 MKV 播放和截图验证，并能直接打开「添加 Jellyfin」表单。见 [TEST-RESULTS.md](TEST-RESULTS.md)。
