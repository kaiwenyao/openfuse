# OpenFuse 0.9.7 · macOS 交付包

本版为 macOS 应用加入新的 OpenFuse 图标，采用深色底和暖橙色折面播放键。

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
| `OpenFuse-macos.zip` | Apple Silicon 自包含应用。版本为 `0.9.7`，构建提交为 `0a98d64`。 |
| `OpenFuse-macos.zip.sha256` | `69a016f4fc7ea88890171e53d763a2eb7d53388cafe44d3129737cb055721920` |
| `install-openfuse-macos.sh` | 安装和升级脚本 |
| `TEST-RESULTS.md` | 0.9.7 安装包验收及历史测试结果 |
| `screenshots/`、`recording/`、`evidence/` | 0.9.2 界面改版的历史截图、录屏与运行时报告 |
