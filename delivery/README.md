# OpenFuse 0.9.5 · macOS 交付包

本版改善 macOS 播放时用 `Cmd+Tab` 切换应用的卡顿。播放器调整出帧时序，减少 libmpv 在窗口主线程上的等待。验收脚本记录切换前后的播放状态，并分别统计快捷键切换和 Finder 回退。[修复与验证记录](../Docs/MACOS-CMD-TAB-FIX.md) · [PR #2](https://github.com/kaiwenyao/openfuse/pull/2)

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
| `OpenFuse-macos.zip` | Apple Silicon 自包含应用。版本为 `0.9.5`，构建提交为 `cc6e753`。 |
| `OpenFuse-macos.zip.sha256` | `7a8bc13f0278e8b428e8d7f53c1e1c1424ec6974981ec59393ffccfed9933bf0` |
| `install-openfuse-macos.sh` | 安装和升级脚本 |
| `TEST-RESULTS.md` | 0.9.5 安装包验收及历史测试结果 |
| `screenshots/`、`recording/`、`evidence/` | 0.9.2 界面改版的历史截图、录屏与运行时报告 |
