# OpenFuse 安装（macOS）

## 一行安装 / 升级

```bash
curl -fL --proto '=https' --proto-redir '=https' \
  -o install-openfuse-macos.sh \
  https://github.com/kaiwenyao/openfuse/releases/latest/download/install-openfuse-macos.sh \
  && bash install-openfuse-macos.sh
```

离线安装（已有 ZIP）：

```bash
bash install-openfuse-macos.sh --app OpenFuse-macos.zip
```

## 说明

- 应用装到 `/Applications`，不可写时回落 `~/Applications`；先校验 `OpenFuse-macos.zip.sha256`，再备份旧版、替换，失败自动回滚，重复执行即升级。
- 默认 `--sign local`：在登录钥匙串里创建并复用 10 年期本地签名身份，升级后钥匙串授权保持连续；`--sign adhoc` 为显式降级（每次升级可能要重新确认钥匙串访问）。
- 其他参数：`--prefix DIR`、`--release TAG`、`--reset-identity`、`--uninstall`、`--no-launch`、`--lang en|zh-CN`。
- OpenFuse 不需要辅助功能、输入监控或屏幕录制权限；凭据保存在登录钥匙串。
- 应用数据（来源、观看记录、媒体库索引）在 `~/Library/Application Support/OpenFuse`，升级与卸载都不会删除。

## iPhone / iPad

真机安装与 7 天续签命令、免费 Apple 账户的前置步骤见
[INSTALL-MAC-IOS.md](INSTALL-MAC-IOS.md) 第二节。
