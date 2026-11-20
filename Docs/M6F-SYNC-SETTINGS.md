# M6f 验收记录：同步设置 UI 与 CA 导入

日期：2026-11-20。分支 `m6f-sync-settings`。基线 Infuse 8.5.10（参照客户端待装）。

此前同步只靠环境变量。本轮在 Settings 增加“进度同步”：URL、Bearer Token（Keychain）、CA 文件导入（复制到 Application Support），以及“保存并同步”。

## 交付内容

- `AppModel`：
  - UserDefaults `openfuse.sync.url` / `openfuse.sync.ca`；
  - Keychain `sync-token`；
  - `saveSyncSettings(urlText:token:caURL:)`，CA 复制为 `sync-ca.pem`；
  - `syncWithSettings()` / `saveAndSyncSettings()`；
  - `syncPlaybackProgressFromEnvironment` 在无环境变量时回退设置。
- Settings“进度同步”区：URL、Token、CA 路径/选择、保存并同步、状态。
- `Scripts/run-sync-settings.sh`：写入 defaults + env token，验证设置驱动 HTTPS 同步，截设置面板。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 持久化 URL/CA | defaults 读取成功 |
| 同步 | 仅 env token，无 env URL/CA，GET/POST 成功 |
| CA | 测试 CA 路径显示并可导入 |
| Settings | 截图显示 URL/CA/保存并同步 |
| 脚本 | `Scripts/run-sync-settings.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| UI 点击/Keychain 提示/公共 CA | 待验证 |

证据：`Evidence/116-sync-settings.jpg/.png`、`reports/m6f-sync-settings-*`、`reports/m6f-sync-settings.txt`。

## 可复现差异与未验证

1. **fileImporter 点击/Keychain 保存提示**未自动化；用 defaults/env 验证同一路径。
2. **公共/企业 CA、并发同步**未测。
3. **物理5.1/人耳/HDMI、HDR测量、CloudKit、visionOS**未完成。

## 下一项

iPhone 同步设置持久化已在 [M6g 验收](Docs/M6G-IOS-SYNC-SETTINGS.md) 完成。剩余 M6h/M5au：物理5.1/HDMI、HDR测量、小时级/DFS、CloudKit/visionOS。
