# OpenFuse 0.9.6 · macOS 安装

## 包内容

```text
delivery/OpenFuse-macos.zip              约 28 MiB，自包含 libmpv 及依赖，版本 0.9.6（7d3ce6b）
delivery/OpenFuse-macos.zip.sha256       bbd2bcf4bfdf25ce12b4e6bf6f2283c31966b5f0df4722b99d8837d0dee1c8f4
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
- 解包后使用本地 MKV 验证播放、截图和退出报告，确认应用加载了内置 libmpv，并应用默认的零提前量设置。见 [TEST-RESULTS.md](TEST-RESULTS.md)。
