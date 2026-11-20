# M4x 验收记录：Jellyfin 用户切换

日期：2026-11-20。分支 `m4x-jellyfin-user-switch`。基线 Infuse 8.5.10（参照客户端待装）。

M2h/M2i 验证了多用户隔离，但 OpenFuse 没有切换入口。本轮在 Settings 增加 Jellyfin 用户列表与“切换用户…”面板，CLI 可无头验收；切换会清理旧用户库，避免重复。

## 交付内容

- `AppModel.switchJellyfinUser(_:username:password:)`：
  - 认证新用户；
  - 删除旧 sourceID 的库行（jellyfin/emby）；
  - upsert 新来源、保存 token、重新扫描。
- Settings「Jellyfin 用户」列表 + 切换面板（用户名/密码）。
- `--jellyfin-switch-user/-password/-source` CLI。
- `Scripts/run-jellyfin-switch.sh`：test 扫描 → test2 切换 → 库清理/播放/服务器进度断言。
- 修复 `removeJellyfinSource` 未删除 library 行导致切换后 4 条重复。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 切换后来源 | 1 个，username=**test2** |
| 库作品 | **2**（无旧 test 重复） |
| 播放/seek | 11.042/20.041 |
| test2 UserData | PlaybackPositionTicks≈110.42M |
| Settings UI | 显示 test2 + 切换用户 |
| 脚本 | `Scripts/run-jellyfin-switch.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| HTTPS/并发/真机 | 待验证 |

证据：`Evidence/107-settings-jellyfin-switch.jpg`、`reports/m4x-switch-*`、`reports/m4x-jellyfin-switch.txt`。

## 可复现差异与未验证

1. **切换面板点击**未自动化，仅截图 + CLI 验收。
2. **HTTPS/并发会话/每文件夹 ACL**未测。
3. **真实设备/音频/HDR/visionOS**未测。

## 下一项

M4y/M6d：切换面板自动化、HTTPS/并发；SMB 多GB/DFS；音频/HDR/visionOS。
