# M3j 验收记录：本地分辨率探测与画质筛选补全

日期：2026-11-20。分支：`m3j-resolution`。基线：Infuse 8.5.10（参照客户端待装）。

此前画质筛选只能命中 Jellyfin 电影，因为本地/WebDAV/Jellyfin 单集没有高度。本轮为本地文件补分辨率：MP4 用 AVFoundation，MKV 用 macOS `ffprobe`；`1080p` 筛选现在能显示本地电影与两部剧。

## 交付内容

- `LibraryScanner.probeLocalHeight`：AVFoundation `naturalSize/preferredTransform`，仅对 >1KB 文件；visionOS 上该同步 API 不可用，直接跳过。
- `MediaProbe.enrichLocalResolutions`（Mac App）：扫描后对本地版本运行 `ffprobe -select_streams v:0 -show_entries stream=height`，>1MB 文件才探测；空文件/10k 压力夹具不产生进程。
- 结果写回 `ScannedVersion.resolution`（1080p/2160p 等），随媒体库持久化。
- Jellyfin 电影高度沿用 MediaSource.MediaStreams；WebDAV/Jellyfin 单集仍缺。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 本地 fixture 版本 | 4/4 行 **1080p** |
| `library-resolution hd1080` | 可见 3 作品：OpenFuse Fixture、另一部剧、示例剧 |
| `swift test` | **26/26 通过** |
| iOS/iPadOS、tvOS、visionOS | **BUILD SUCCEEDED** |
| iOS device Release | **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |

证据：`Evidence/44-resolution-filter.jpg`、`reports/m3j-resolution.txt`。

## 可复现差异与未验证

1. **WebDAV/Jellyfin 单集分辨率仍缺**；需在扫描时探测流或读取 MediaSources。
2. **ffprobe 依赖 Homebrew 路径**；未做自包含打包，非 macOS 不调用。
3. **HDR/4K 实际文件未测**；仅 1080p fixture。
4. **M3 T07 其他场景**（扫描中播放/单文件失败）未补。
5. **tvOS/visionOS runtime**：tvOS 27.2 正在下载（约 22%），尚未实际启动。
6. **移动端音频/字幕/音轨、CloudKit/Trakt** 未做。

## 下一项

WebDAV MP4 与 Jellyfin 单集分辨率已在 [M3k 验收](M3K-STREAM-RESOLUTION.md) 完成。剩余 M4i：tvOS runtime 实际启动、移动端字幕/音轨/音频听测、WebDAV MKV 分辨率、CloudKit/Trakt、T07 其他场景。
