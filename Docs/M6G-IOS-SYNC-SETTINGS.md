# M6g 验收记录：iPhone 同步设置持久化

日期：2026-11-20。分支 `m6g-ios-sync-settings`。基线 Infuse 8.5.10（参照客户端待装）。

M4z 的 iPhone HTTPS 只靠环境变量。本轮在移动端 Sources 增加“进度同步”区，URL/CA 存 UserDefaults、Token 存 Keychain、CA 复制到容器；并验证无 env URL/CA 时从设置读取并续播。

## 交付内容

- `MobileLibraryModel`：
  - `syncURLText`/`syncTokenInput`/`syncCAPath`/`syncBusy`；
  - UserDefaults `openfuse.sync.url`/`openfuse.sync.ca`；
  - Keychain `sync-token`；
  - `saveSyncSettings` / `syncWithSettings` / `runSync`；
  - env 优先，否则读设置。
- `MobileSourcesView`：同步地址、Bearer Token、CA 选择、保存并同步、状态。
- `Scripts/run-ios-sync-settings.sh`：安装 app、写 Preferences、复制 CA、仅 env token 启动并断言续播。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 持久化 URL/CA | simctl defaults 写入，app 读取成功 |
| 同步 | 无 env URL/CA，HTTPS GET 到达 |
| resume | **11.00s** |
| 脚本 | `Scripts/run-ios-sync-settings.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| UI 点击/Keychain 提示/公共 CA | 待验证 |

证据：`Evidence/118-ios-sync-settings.jpg`、`reports/m6g-ios-sync-settings-*`、`reports/m6g-ios-sync-settings.txt`。

## 可复现差异与未验证

1. **Sources UI 的点击/文件选择器**未自动化；用持久化 Preferences 验证同一读取路径。
2. **Keychain 保存提示/公共 CA/并发同步**未测。
3. **物理5.1/人耳/HDMI、HDR测量、CloudKit、visionOS**未完成。

## 下一项

M6h/M5au：物理5.1/HDMI；HDR测量；小时级/DFS；CloudKit/visionOS。
