# OpenFuse 0.9.6 · macOS 交付包

本版修复 2026-11-27 功能问题清单里的 7 条：从「继续观看」打开后关闭卡在加载页、打开失败无提示、「仅本次会话」的 WebDAV 来源重启后误报密码错误、来源移除后的历史条目、Keychain 写入警告不可见，以及两条 iOS 问题。Plex 条目在来源仍在时可以从「继续观看」续播。[问题清单](../Docs/BUG-REVIEW-2026-11-27.md) · [PR #3](https://github.com/kaiwenyao/openfuse/pull/3)

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
| `OpenFuse-macos.zip` | Apple Silicon 自包含应用。版本为 `0.9.6`，构建提交为 `7d3ce6b`。 |
| `OpenFuse-macos.zip.sha256` | `bbd2bcf4bfdf25ce12b4e6bf6f2283c31966b5f0df4722b99d8837d0dee1c8f4` |
| `install-openfuse-macos.sh` | 安装和升级脚本 |
| `TEST-RESULTS.md` | 0.9.6 安装包验收及历史测试结果 |
| `screenshots/`、`recording/`、`evidence/` | 0.9.2 界面改版的历史截图、录屏与运行时报告 |
