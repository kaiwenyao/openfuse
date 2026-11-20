# M2f 验收记录：iPhone 真实 Jellyfin MKV HLS

日期：2026-11-20。分支 `m2f-ios-jellyfin-hls`。基线 Infuse 8.5.10（参照客户端待装）。

M2e 验证了 Mac 直连 MP4。本轮让 iPhone 播放真实 Jellyfin 库中的 60s HEVC/E-AC-3 MKV：移动端选择 HLS，服务器实际 `libx264 + libfdk_aac` 转码，AVPlayer 出画并写回 12.24s。

## 交付内容

- `Scripts/run-ios-jellyfin-hls.sh`：使用 M2e Jellyfin 配置，加入 MKV，iPhone 模拟器 autoplay/seek/字幕/进度断言 + 服务器 HLS 日志断言。
- 移动端 HLS：
  - 使用 `AVURLAssetHTTPHeaderFieldsKey` 注入 `Authorization: MediaBrowser Token`（Jellyfin 12 拒绝 api_key-only）；
  - `AuthenticatedAssetLoader` 按 AVFoundation 请求的 custom URL 映射真实 host/path，支持子播放列表/分片。
- HLS URL 记录：`/Videos/<id>/master.m3u8?...h264/aac/ts`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设备 | iPhone 18 Pro 模拟器 / iOS 27.2 |
| 源 | 真实 Jellyfin 12.4 MKV 1080p HEVC/E-AC-3 |
| 播放 | t=12.2 / 60s |
| HLS URL | `master.m3u8`，h264/aac/ts |
| 服务器转码 | ffmpeg `-f hls`，libx264，libfdk_aac，416×234 |
| 进度 | playback.json position **12.242s** |
| 脚本 | `Scripts/run-ios-jellyfin-hls.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| HTTPS/4K/多用户/真机 | 待验证 |

证据：`Evidence/98-ios-jellyfin-hls.jpg`、`reports/m2f-ios-jellyfin-playback.json`、`reports/m2f-jellyfin-hls.log`、`reports/m2f-ios-jellyfin-hls.txt`。

## 可复现差异与未验证

1. **HLS 转码为 416×234**（Jellyfin 默认 profile/码率）；画质/4K/HEVC 转码未验证。
2. **HUD 音轨显示 Unknown、字幕 CC**；HLS 流元数据/字幕编码待优化。
3. **HTTPS/反代/多用户/真实 iPhone**未测。
4. **音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、visionOS 真机**未完成。

## 下一项

真实 Samba SMB3 已在 [M5ak 验收](Docs/M5AK-SAMBA-SMB3.md) 完成。剩余 M5al/M6d：SMB 签名/加密/DFS/大文件、Jellyfin HTTPS/4K/多用户、HLS 元数据、百度网盘、音频听测、HDR 测量、真实 Trakt/CloudKit、visionOS 真机。
