# M5c 验收记录：Plex scrobble 完成

日期：2026-11-20。分支：`m5c-plex-scrobble`。基线：Infuse 8.5.10（参照客户端待装）。

M5b 只在 `finishPlayback` 触发 `/:/scrobble`，而实际暂停在 59.967s 未到 EOF。现在 `saveProgress` 判定“已看完”（ResumePolicy 95%）时也调用 `reportPlexStop`，带 `hasReportedPlexStop` 幂等标志；Plex timeline 补发 `state=stopped` 并 scrobble。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| timeline playing | 收到 `state=playing&time=0&duration=60000` |
| timeline paused | 收到 `state=paused&time=59967` |
| timeline stopped | 收到 `state=stopped&time=59967` |
| scrobble | 收到 `/:/scrobble?key=401&identifier=com.plexapp.plugins.library` |
| 播放 | Plex 第 1 集 9.917s；近结尾运行停 59.967s |
| `swift test` | **28/28 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 真实 Plex | 待验证 |

证据：`reports/m5c-plex-timeline.jsonl`、`reports/m5c-plex-scrobble.txt`。

## 可复现差异与未验证

1. **自然 EOF scrobble 未单独验证**：本轮通过 95% finished 保存触发；两者共用幂等上报。
2. **真实 Plex** 参数/认证/限流未测。
3. **Plex 直连浏览/字幕**未做。
4. **Emby/SMB、HDR/AirPlay、自包含打包**未做。
5. **CloudKit 真实账号/Trakt、自动同步/离线队列**未做。
6. **音频听测、M3 T07/WebDAV MKV 分辨率**未做。

## 下一项

Plex 外挂字幕已在 [M5d 验收](Docs/M5D-PLEX-SUBTITLES.md) 完成。剩余 M5e：Plex 直连浏览/音轨/版本；Emby；SMB；HDR/AirPlay；自包含打包；CloudKit/Trakt；音频听测；M3 尾项。
