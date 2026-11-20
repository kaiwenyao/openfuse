# M5b 验收记录：Plex 播放进度回写

日期：2026-11-20。分支：`m5-plex-progress`。基线：Infuse 8.5.10（参照客户端待装）。

Plex 播放现在会向服务器上报 timeline：文件加载时 `state=playing`，保存进度时 `playing/paused`，结束播放时 `stopped` 并调用 `/:/scrobble`。夹具记录请求，验收检查 timeline 状态与时间。

## 交付内容

- `PlexPlaybackContext`：source/baseURL/token/ratingKey/partKey/duration，随 `MediaItem` 传入 PlayerModel。
- PlayerModel：`reportPlexStart`、`reportPlexProgress`、`reportPlexStop`；与 Jellyfin 上报并列，不互相影响。
- `PlexClient.reportTimeline` / `scrobble`；token query。
- Plex 夹具 `/:/timeline`、`/:/scrobble` 记录 state/time/ratingKey（日志脱敏）。
- 验收脚本增加 timeline playing/paused 断言。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Plex 扫描/播放 | 2 作品/3 集；播放 9.917s |
| timeline playing | 收到 `ratingKey=401&state=playing&time=0&duration=60000` |
| timeline paused | 收到 `state=paused&time=...` |
| scrobble | **未观察到**：seek 到 59s 后播放停在 59.967s，未触发 finishPlayback |
| `swift test` | **28/28 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 真实 Plex | 待验证 |

证据：`Evidence/60-plex-progress.jpg`、`reports/m5b-plex-timeline.jsonl`、`reports/m5b-plex-progress.txt`。

## 可复现差异与未验证

1. **scrobble 未实测**：需要播放真正到文件结束；seek 后暂停在 59.967s 不触发 finish。
2. **真实 Plex** timeline/scrobble 参数、认证、限流未验证。
3. **Plex 直连浏览/字幕/音轨未接**。
4. **Emby/SMB、HDR/AirPlay、自包含打包**未做。
5. **CloudKit 真实账号/Trakt、自动同步/离线队列**未做。
6. **音频听测、M3 T07/WebDAV MKV 分辨率**未做。

## 下一项

M5c：真实 Plex/结束 scrobble、直连浏览/字幕；Emby；SMB；HDR/AirPlay；自包含打包；CloudKit/Trakt；音频听测；M3 尾项。
