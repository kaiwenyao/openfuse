# M4k 验收记录：WebDAV 远程侧载字幕

日期：2026-11-20。分支：`m4k-remote-subs`。基线：Infuse 8.5.10（参照客户端待装）。

M4j 只支持本地侧载字幕。本轮在移动端播放 WebDAV 视频时，列出同目录文件、按同一套匹配规则找 SRT/ASS，带 Basic Auth 下载到本地缓存，再复用自绘字幕菜单。

## 交付内容

- `playbackItemAsync(for:episode:)`：本地直接返回；Jellyfin 走既有远程路径；WebDAV 列目录、匹配、下载字幕。
- `WebDAVClient.subtitleTracks` 复用；`SubtitleCache/<hash>.<ext>`；`SubtitleTrack.source = .downloaded`。
- 详情页播放按钮与 autoplay 改为异步获取，确保字幕在播放器创建前就绪。
- 本地/远程统一 `MobilePlaybackItem.sidecarSubtitles`，字幕菜单与 SRT 解析不变。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| WebDAV 字幕发现 | 简/繁 SRT 均被列出并下载（服务器 GET 200） |
| 缓存 | `SubtitleCache/` 写入本地文件 |
| 菜单 | HUD 显示「字幕：中文（简体）(SRT)」 |
| 远程字幕画面 | **未取得**：本轮远程播放时间跳至末尾，未捕获字幕文本；本地侧载已在 M4j 验证（Evidence 49–50） |
| `swift test` | **27/27 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| visionOS runtime | 下载约 19.9%（7.65 GB），未安装 |

证据：`Evidence/51-ios-webdav-remote-subtitle.jpg`、`reports/m4k-remote-subs.txt`。

## 可复现差异与未验证

1. **远程字幕视觉未验证**：下载/选择链路成功，但 AVPlayer 时间跳变导致未截到 cue；需修远程播放时间/暂停逻辑。
2. **Jellyfin 外挂字幕未接**：PlaybackInfo DeliveryUrl 未下载；内嵌字幕仍用 AVKit。
3. **ASS 样式/字体覆盖**仍无移动端 libass；自绘仅文本。
4. **音频输出未听测**。
5. **visionOS runtime 未安装**，仅构建。
6. **真实 OpenList/Jellyfin、CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率**未做。

## 下一项

M4l：修远程播放时间/暂停与远程字幕截图；Jellyfin 外挂字幕；音频听测；visionOS runtime；CloudKit/Trakt；M3 T07/WebDAV MKV 分辨率。
