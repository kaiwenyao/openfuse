# M4f 验收记录：Jellyfin HLS 转码解决移动端 MKV

日期：2026-11-20。分支：`m4f-hls`。基线：Infuse 8.5.10（参照客户端待装）。

AVPlayer 不能打开 MKV/HEVC 容器。服务端转码是移动端不引入 libmpv 的可行路径：本轮让移动端对非 MP4 容器使用 Jellyfin `master.m3u8` 转码 URL，并生成同源 HLS 夹具做真实 AVPlayer 播放测试。

## 交付内容

- `JellyfinClient.hlsURL(itemID:mediaSourceID:token:)`：构造
  `/Videos/{id}/master.m3u8?MediaSourceId=…&VideoCodec=h264&AudioCodec=aac&TranscodingContainer=ts&TranscodingProtocol=hls&SegmentContainer=ts&DeviceId=…&api_key=…`。
- 移动端 `remotePlaybackItem`：
  - 容器为 `mp4/m4v/mov` → 直连 stream + api_key + 认证 loader；
  - 其他（MKV/HEVC）→ HLS 转码 URL，AVPlayer 直接播放；
  - 续播键仍为 `jellyfin://source/item/mediaSource`。
- Jellyfin 夹具：
  - `build/hls-fixture` 从 MKV 生成 H.264/AAC VOD（2s 分片）；
  - `/Videos/{item}/master.m3u8` 返回带 token 的播放列表，分片路径相对、无需 token；
  - 原有 MP4 直连测试保留。
- 测试：`Scripts/test-jellyfin-hls.sh` 认证→PlaybackInfo→HLS URL→AVPlayer 6 秒播放。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| HLS URL | `master.m3u8` + H.264/AAC/TS + api_key |
| AVPlayer HLS | duration **60.0s**，6 秒后 position **5.954s**，无错误 |
| 源文件 | 同源 MKV（HEVC Main 10/E-AC-3 5.1）经服务端转码 |
| `swift test` | **25/25 通过** |
| iOS/iPadOS、tvOS、visionOS generic | **BUILD SUCCEEDED** |
| iOS device Release | **BUILD SUCCEEDED** |
| 移动端 UI 实际启动 | **待验证**：无 runtime |

输出：

```
PASS: Jellyfin HLS transcode URL/AVPlayer playback for MKV source
```

证据：`reports/m4f-hls.json`、`reports/m4f-hls.txt`。

## 可复现差异与未验证

1. **真实 Jellyfin 转码参数未验证**：夹具接受标准 HLS 查询；真实服务器可能需要 PlaybackInfo 返回的 TranscodingUrl/PlaySessionId、设备 profile 或 HTTPS/反代。
2. **移动端无 runtime**：UI、Keychain、触控、后台续播、音频输出未执行；桌面 AVPlayer HLS 已验证同链路。
3. **字幕/音轨**：HLS 默认流；没有 ASS/SRT 外挂、E-AC-3 5.1、多音轨切换。
4. **HLS 生成是测试夹具**：ffmpeg 预转码，不是 Jellyfin 实时转码；延迟/自适应码率/限流未测。
5. **WebDAV MKV** 仍需 libmpv；WebDAV MP4 已可播。
6. **tvOS/visionOS 未调用 Jellyfin HLS 路径**。
7. **CloudKit/Trakt/iCloud 同步未做。**
8. **Mac M3 尾项**：T07 深入、画质元数据补全。

## 下一项

iOS 已在模拟器实际启动/播放/续播，见 [M4g iOS 运行验收](M4G-IOS-RUN.md)。剩余 M4h：tvOS/visionOS runtime、移动端远程实际播放、字幕/音轨、真实 Jellyfin HLS 参数、CloudKit/Trakt；M3 画质元数据/T07 其他场景。
