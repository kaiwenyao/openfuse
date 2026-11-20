# M3k 验收记录：WebDAV 与 Jellyfin 流分辨率

日期：2026-11-20。分支：`m3k-stream-resolution`。基线：Infuse 8.5.10（参照客户端待装）。

M3j 补齐了本地分辨率。本轮把画质元数据扩展到 WebDAV MP4/MOV 与 Jellyfin 单集：WebDAV 用认证资源加载器读取视频轨尺寸，Jellyfin 扫描时取 PlaybackInfo 的 MediaStreams 高度。

## 交付内容

- `WebDAVClient.basicAuthorizationHeader`：供扫描期 AVAsset 探测使用。
- `scanWebDAV`：对 MP4/M4V/MOV 构造 `AuthenticatedAssetLoader`，`loadTracks(.video)` + `naturalSize`，写回 720p/1080p/2160p；MKV 跳过。
- `scanJellyfin`：每个 episode 调 `playbackInfo(itemID:)`，取首个 MediaSource 的视频 Height，写回版本分辨率。
- 结果随 SQLite 版本行持久化；画质筛选覆盖 Jellyfin 剧集与 WebDAV MP4。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Jellyfin 电影/单集 | movie-1、ep-1、ep-2 均 **1080p** |
| WebDAV MP4 | **720p** |
| Jellyfin 1080p 筛选 | 可见 `OpenFuse Fixture (2026)`、`示例剧` |
| WebDAV 720p 筛选 | 可见 `openfuse-mobile` |
| `swift test` | **26/26 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| tvOS 实际启动 | **待验证**：tvOS 27.2 runtime 下载约 47.6% |

证据：`Evidence/45-stream-resolution-filter.jpg`、`reports/m3k-resolution-*.json`、`reports/m3k-stream-resolution.txt`。

## 可复现差异与未验证

1. **WebDAV MKV 仍无法取分辨率**：AVFoundation 不支持 MKV；需远端 ffprobe/MediaInfo 或服务端元数据。
2. **Jellyfin 每集额外 PlaybackInfo 请求**，大库会变慢；未做并发/缓存。
3. **HDR/4K 实际文件未测**；仅夹具 1080/720。
4. **真实 Jellyfin/OpenList 未验证**；本地夹具。
5. **tvOS/visionOS 无 runtime**；tvOS 下载中。
6. **移动端音频/字幕/音轨、CloudKit/Trakt** 未做。
7. **T07 其他场景**未补。

## 下一项

M4i：tvOS runtime 完成后实际启动/焦点截图；移动端字幕/音轨/音频听测；WebDAV MKV 分辨率；CloudKit/Trakt；T07 其他场景。
