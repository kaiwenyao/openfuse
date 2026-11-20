# M4p 验收记录：跨设备续播同步（本地 transport + CloudKit 代码）

日期：2026-11-20。分支：`m4p-progress-sync`。基线：Infuse 8.5.10（参照客户端待装）。

本轮实现进度同步协议与两种 transport：本地共享 JSON 文件（用于两设备模拟和验收）与 CloudKit private database。用两个独立 support 目录模拟两台设备：A 播放到 9.917s，同步后 B 从该位置继续到 14.417s，证明续播键/进度合并生效。

## 交付内容

- `PlaybackStore.merge(records:)`：按 `lastPlayedAt` 取新；本地同级时间优先，避免覆盖正在进行的本地暂停。
- JSON 日期改为带毫秒的 ISO8601，修复同步时间戳被截断到整秒导致合并失败。
- `ProgressSyncTransport` 协议；`LocalProgressTransport`（共享文件）；`CloudKitProgressTransport`（CKRecord `PlaybackProgress`，私有库）。
- `ProgressSyncService`：拉取远端 → 合并 → 推送本地全部记录。
- App CLI：`--sync-progress` + `OPENFUSE_SYNC_FILE` / `OPENFUSE_CLOUDKIT_CONTAINER`；同步状态显示。
- 两台“设备”验收脚本 `Scripts/test-progress-sync.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| A 播放 | 冻结 9.917s，记录写入 A 的 playback.json |
| A→共享文件 | 同步成功 |
| B 同步 | 拉取并合并记录 |
| B 续播 | 5 秒后位置 **14.417s**（不是从 0） |
| 第二次 B 播放 | 21.917s，画面见 Evidence 57 |
| `swift test` | **28/28 通过**（新增同步合并测试） |
| iOS/iPadOS/tvOS/visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 真实 CloudKit | **待验证**：需要 iCloud entitlements/账号；代码可编译，未连接真实容器 |

证据：`Evidence/57-progress-sync-b.jpg`、`reports/m4p-*`、`reports/m4p-progress-sync.txt`。

## 可复现差异与未验证

1. **CloudKit 未实测**：没有签名 entitlement/iCloud 账号；真实容器、查询索引、冲突与错误恢复待验证。
2. **同一时间戳冲突**：本地优先；没有设备 ID/版本向量。
3. **Trakt 未实现**。
4. **同步触发是 CLI/手动**；未在播放暂停/退出自动后台同步，也无离线队列。
5. **移动端/Apple TV/Vision 未接此同步 UI**；只用 Mac 两 support 目录验证。
6. **音频未听测**；M3 T07/WebDAV MKV 分辨率未做。

## 下一项

M4q/M5：CloudKit entitlements/真实账号验证、自动同步与离线队列、Trakt、移动端同步 UI；SMB/Plex/Emby、HDR/AirPlay、自包含打包；音频听测；M3 尾项。
