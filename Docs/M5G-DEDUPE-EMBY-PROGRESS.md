# M5g 验收记录：Jellyfin+Emby 聚合去重与 Emby 进度

日期：2026-11-20。分支：`m5g-dedupe-emby`。基线：Infuse 8.5.10（参照客户端待装）。

把同一兼容夹具分别以 Jellyfin、Emby 加入同一媒体库：原始 4 作品/6 集在聚合后变为 2 组，每组 sources 同时包含 emby/jellyfin，避免海报库重复卡片。Emby 播放同时验证 Sessions/Playing 与 Progress 已回写。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 原始条目 | 4 作品 / 6 集（两来源各 2/3） |
| 聚合后 | **2 组**，每组 sources = `["emby","jellyfin"]` |
| Emby Sessions/Playing | 204，PositionTicks **99170000**，DirectPlay，ItemId=ep-1 |
| Emby Progress | 204，IsPaused=true，PositionTicks **101670000** |
| 去重脚本 | `Scripts/run-jellyfin-emby-dedupe.sh` PASS |
| Emby 验收脚本 | `Scripts/run-emby-acceptance.sh` PASS |
| `swift test` | **28/28 通过** |
| 构建 | M5f 五端/device/Mac 全通过；本轮无 Swift 改动 |

证据：`Evidence/65-jellyfin-emby-dedupe.jpg`、`reports/m5g-dedupe.json`、`reports/m5g-emby-progress.jsonl`、`reports/m5g-dedupe-progress.txt`。

## 可复现差异与未验证

1. **真实 Emby/Jellyfin** 未验证；本轮是同源兼容夹具。
2. **版本级去重未处理**：组内仍可能同时出现 Jellyfin/Emby 两个 `1080p HEVC 5.1` 版本；是否合并需产品决定。
3. **Stopped 事件未断言**；只验证 Playing/Progress。
4. **Plex 直连/音轨/版本、SMB/HDR/AirPlay、CloudKit/Trakt、音频、M3 尾项**未做。
5. **真实 Infuse 对照、人工听测**仍缺。

## 下一项

Plex 多版本已在 [M5h 验收](M5H-PLEX-VERSIONS.md) 完成。剩余 M5i：Plex 直连/音轨、版本级去重、真实服务器、SMB/HDR/AirPlay、CloudKit/Trakt、音频、M3 尾项。
