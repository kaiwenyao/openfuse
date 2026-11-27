# OpenFuse 0.9.8 · macOS 交付包

本版恢复从界面添加 Jellyfin / Emby 的入口：侧边栏和文件页的「添加来源」改为菜单，可选 WebDAV 或 Jellyfin / Emby。0.9.0 到 0.9.7 中，没有 Jellyfin 来源时界面上找不到添加入口。[PR #4](https://github.com/kaiwenyao/openfuse/pull/4)

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
| `OpenFuse-macos.zip` | Apple Silicon 自包含应用。版本为 `0.9.8`，构建提交为 `1934829`。 |
| `OpenFuse-macos.zip.sha256` | `053cca0aab291115bf1bd97b90edc434c7f88cb828a2f16149c98c7444f7e19f` |
| `install-openfuse-macos.sh` | 安装和升级脚本 |
| `TEST-RESULTS.md` | 0.9.8 安装包验收及历史测试结果 |
| `screenshots/`、`recording/`、`evidence/` | 0.9.2 界面改版的历史截图、录屏与运行时报告 |
