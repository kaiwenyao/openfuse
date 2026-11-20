# M5x 验收记录：Jellyfin/WebDAV HDR 元数据

日期：2026-11-20。分支：`m5x-remote-hdr`。基线：Infuse 8.5.10（参照客户端待装）。

M5w 只解析本地 ffprobe HDR。本轮让 Jellyfin 解析 `VideoRange/VideoRangeType`，WebDAV 远程 MKV ffprobe 同时返回 color transfer/primaries；两者都写入 `dynamicRange` 并显示 HDR10。

## 交付内容

- `JellyfinMediaStream.videoRange/videoRangeType`；`jellyfinHDR` 映射 HDR10/HDR10+/HLG/Dolby Vision/HDR。
- Jellyfin 电影/剧集版本写入 dynamicRange。
- WebDAV ffprobe 改 JSON，返回 height + HDR 标签；`FileCandidate.dynamicRange` 流入 buildLibrary。
- 验收脚本 `Scripts/run-remote-hdr.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Jellyfin | 电影/剧集版本 dynamicRange=**HDR10**、1080p |
| WebDAV | HDR MKV dynamicRange=**HDR10**、1080p、`1080p · WebDAV` |
| 脚本 | `Scripts/run-remote-hdr.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 实际 HDR 输出 | 待验证 |

证据：`Evidence/88-remote-hdr.jpg`、`reports/m5x-jellyfin-hdr.json`、`reports/m5x-webdav-hdr.json`、`reports/m5x-remote-hdr.txt`。

## 可复现差异与未验证

1. **只验证元数据**，未验证 HDR 显示/tone mapping。
2. **真实 Jellyfin/OpenList HDR 字段**未验证；夹具为人工 HDR10。
3. **Dolby Vision/HDR10+** 映射粗略。
4. **音频回环仍被权限阻断**。
5. **真实 SMB3/Trakt、AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

HDR10 SDR 色调映射播放已在 [M5y 验收](Docs/M5Y-HDR-PLAYBACK.md) 完成。剩余 M5z：HDR 直通/真实显示器、音频听测、真实 SMB3/Trakt、AirPlay 实机、CloudKit、M3 多根/损坏过滤。
