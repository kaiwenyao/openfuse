# M4n 验收记录：Jellyfin 外挂字幕实际播放

日期：2026-11-20。分支：`m4n-jellyfin-subs`。基线：Infuse 8.5.10（参照客户端待装）。

上轮 Jellyfin DeliveryUrl 下载代码已加，但自动播放返回主页。本轮使用已持久化的 Jellyfin 来源重测：movie-1 走 60s HLS，App 下载外挂 SRT 到缓存，播放到 4.5s 暂停，第一句字幕实际显示。

## 交付内容

- Jellyfin 夹具：movie-1/movie-mobile 的 MediaStreams 增加 `IsExternal=true` 的 SRT DeliveryUrl，服务端带 token 返回。
- App：`remotePlaybackItem` 对每个外挂字幕发起带 `X-Emby-Token`/`MediaBrowser` 的下载，写 `SubtitleCache`，生成 `SubtitleTrack(.downloaded)`。
- 自绘字幕菜单显示「外挂简体中文」，ticker/seek 逻辑复用 M4j/M4m。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 外挂字幕下载 | DeliveryUrl GET 200，写入 SubtitleCache |
| 播放 | movie-1 HLS，HUD **4.7/60.0s** |
| 字幕画面 | 「最初の字幕… / 第一句：画面 2.5 秒，字幕准时出现。」 |
| 菜单 | 「外挂简体中文」 |
| `swift test` | **27/27 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| visionOS runtime | 下载约 **85.7%**，未安装 |
| 音频 | 未听测 |

证据：`Evidence/54-ios-jellyfin-external-subtitle.jpg`、`reports/m4n-jellyfin-external-subtitle.txt`。

## 可复现差异与未验证

1. **自动播放仍有时序脆弱**：上轮同一路径返回主页；本轮复用已持久化来源成功。需把 source bootstrap/选组状态明确化。
2. **音频未听测**；HLS 音频默认轨。
3. **外挂简繁切换**只验证简体；繁体 DeliveryUrl 未加。
4. **真实 Jellyfin** 的 DeliveryUrl 形态/鉴权/转码未验证。
5. **visionOS runtime 未安装**，仅构建。
6. **CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率**未做。
7. **ASS 样式/字体覆盖**仍无移动端 libass。

## 下一项

M4o：visionOS runtime 实际启动（约 86%）、音频听测、外挂简繁切换、自动播放时序稳定化、CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率。
