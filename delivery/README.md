# OpenFuse 0.9.4 · macOS 交付包

本版修复 macOS 字幕偏移的显示精度和负号解析。菜单、编辑框、保存和播放统一到毫秒精度。重新打开输入框后直接应用可保留 `0.04` 秒精度。输入 `−0.1` 会让字幕提前。[PR #1](https://github.com/kaiwenyao/openfuse/pull/1)

## 安装

在仓库根目录运行。

```bash
cd delivery
shasum -a 256 -c OpenFuse-macos.zip.sha256
bash install-openfuse-macos.sh --app OpenFuse-macos.zip
```

完整说明见 [INSTALL.md](INSTALL.md)。

## 交付文件

| 路径 | 说明 |
| --- | --- |
| `OpenFuse-macos.zip` | Apple Silicon 自包含应用。版本为 `0.9.4`，构建提交为 `cc5f929`。 |
| `OpenFuse-macos.zip.sha256` | `6df75de9953503b1c78f0e6133130469f5a651c8eda4fec0d6649c28f7d2cb43` |
| `install-openfuse-macos.sh` | 安装和升级脚本 |
| `TEST-RESULTS.md` | 0.9.4 安装包验收及历史测试结果 |
| `screenshots/`、`recording/`、`evidence/` | 0.9.2 界面改版的历史截图、录屏与运行时报告 |
