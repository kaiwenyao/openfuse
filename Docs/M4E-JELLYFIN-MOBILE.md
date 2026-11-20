# M4e 验收记录：Jellyfin 移动端远程播放

日期：2026-11-20。分支：`m4e-jellyfin`。基线：Infuse 8.5.10（参照客户端待装）。

本轮把移动端 Jellyfin 从“可扫描”推进到“可远程播放 MP4/MOV”：详情页调用 PlaybackInfo 选择 MediaSource，生成带 `api_key` 的直连 URL，用 M4d 的认证 loader 创建 AVPlayer。MKV/HEVC 仍受 AVPlayer 容器限制。

## 交付内容

- `MobileLibraryModel.remotePlaybackItem(for:episode:)`：
  - Keychain 取 token；
  - `JellyfinClient.playbackInfo(itemID:)` 取 MediaSources；
  - 优先匹配库中版本的 `mediaSourceID`，否则第一条；
  - `streamURL` + `api_key` 查询；
  - 指纹键 `jellyfin://source/item/mediaSource`，续播独立；
  - loader 头带 `X-Emby-Token` / `Authorization: MediaBrowser Token=...`。
- iPhone/iPad 详情：Jellyfin 条目显示「播放服务器版本」，异步获取后进入播放器；失败提示 MKV/HEVC 需转码或 libmpv。
- 夹具：`jellyfin_fixture.py --mobile-sample` 增加 `movie-mobile`（H.264/AAC MP4，20s）与 `/Videos/movie-mobile/stream`；不影响默认夹具与既有验收。
- 测试：`Scripts/test-jellyfin-mobile.sh` 走 auth → PlaybackInfo → token URL → loader → AVPlayer。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Jellyfin 认证/PlaybackInfo/URL | 通过，URL 含 `api_key` |
| AVAsset | duration **20.0s**、**1** 条视频轨 |
| AVPlayer | 6 秒后 position **5.866s**，item ready，无错误 |
| `swift test` | **25/25 通过** |
| iOS/iPadOS、tvOS、visionOS generic | **BUILD SUCCEEDED** |
| iOS device Release | **BUILD SUCCEEDED** |
| 移动端 UI 实际启动 | **待验证**：无 runtime |

输出：

```
PASS: Jellyfin auth/PlaybackInfo/token URL/loader/AVPlayer remote playback
```

## 可复现差异与未验证

1. **没有移动 runtime/真机证据**：UI、Keychain 弹窗、触控、后台续播、音频未执行；桌面同链路 AVPlayer 已验证。
2. **Jellyfin MKV/HEVC 仍不能直接播**：需 HLS 转码参数或 libmpv；直连 URL 只适合 MP4/MOV。
3. **真实 Jellyfin** 的转码 profile、HTTPS/反代、限流、外挂字幕未验证；仅本地夹具。
4. **字幕/音轨切换未接**；AVPlayer 只播放默认音轨/内嵌字幕。
5. **WebDAV MKV** 同样需 libmpv；WebDAV MP4 已可播。
6. **tvOS/visionOS 未调用 `remotePlaybackItem`**；只包含基础 UI。
7. **CloudKit/Trakt/iCloud 同步未做。**
8. **Mac M3 尾项**：T07 深入、画质元数据补全。

## 下一项

M4f：Jellyfin HLS 转码/MKV、字幕/音轨、三端 runtime 启动截图、tvOS/visionOS 远程来源、CloudKit/Trakt；M3 T07/画质元数据。
