# M2h 验收记录：Jellyfin 多用户隔离

日期：2026-11-20。分支 `m2h-jellyfin-multiuser`。基线 Infuse 8.5.10（参照客户端待装）。

本轮在真实 Jellyfin 12 创建第二个用户 test2，独立 OpenFuse 配置扫描/播放/回写，验证两个用户的观看位置互不污染。

## 交付内容

- `Scripts/run-jellyfin-multiuser.sh`：
  - 创建 test2（若不存在），通过 `/Users/{id}/Configuration` 启用本地密码；
  - 清空 test 在目标影片上的进度；
  - test2 独立 support 扫描/播放；
  - 分别用两个 token 查询 UserData，断言 test2 有位置、test 仍为 0。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 用户 | test/test、test2/test2 |
| test2 播放 | 11.064s |
| test2 UserData | PlaybackPositionTicks≈110.6M |
| test UserData | **0**（未被污染） |
| 脚本 | `Scripts/run-jellyfin-multiuser.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| UI 用户切换/并发会话 | 待验证 |

证据：`reports/m2h-jellyfin-user1.json`、`m2h-jellyfin-user2.json`、`m2h-jellyfin-play.json`、`m2h-jellyfin-multiuser.txt`。

## 可复现差异与未验证

1. **OpenFuse UI 没有用户切换**；通过不同来源配置/独立 support 验证。
2. **未验证每用户媒体库权限/并发会话/HTTPS**。
3. **真实设备/音频/HDR/visionOS**未测。

## 下一项

Jellyfin 权限隔离已在 [M2i 验收](Docs/M2I-JELLYFIN-PERMISSIONS.md) 完成。剩余 M2j/M6d：UI 用户切换/并发/HTTPS、SMB 多GB/DFS、音频听测、HDR 测量、真实 Trakt/CloudKit、visionOS 真机。
