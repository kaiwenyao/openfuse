# M4d 验收记录：认证资源加载与 WebDAV 移动端远程播放

日期：2026-11-20。分支：`m4d-auth-asset`。基线：Infuse 8.5.10（参照客户端待装）。

本轮实现 `AuthenticatedAssetLoader`：用 `AVAssetResourceLoaderDelegate` 把 AVPlayer 的请求转成带 Basic/Token 头的 HTTP Range 请求，解决 AVPlayer 无法直接携带 WebDAV Basic Auth 的问题。移动端 WebDAV MP4/MOV 因此可远程播放并续播；Jellyfin 远程、MKV/字幕仍在后续。

## 交付内容

- **`AuthenticatedAssetLoader`**（OpenFuseData）：
  - 自定义 `openfuse-auth://` scheme + `AVURLAsset.resourceLoader`；
  - HEAD 取 Content-Length/Content-Type/Accept-Ranges；
  - GET `Range: bytes=...`，处理 206/200、偏移裁剪、取消；
  - 请求头可注入 `Authorization: Basic ...` 或 `X-Emby-Token`。
- **移动端 WebDAV 远程播放**：`MobilePlaybackItem` 增加 `httpHeaders`；WebDAV 条目从 Keychain 取密码，构造 Basic 头、真实 URL 与 `webdav://source/path` 续播键；播放器用 loader 创建 `AVPlayerItem`。
- **三端播放器共用**：iPhone/iPad/tvOS/visionOS 的 `makePlayer` 统一走 loader；本地文件仍直接 AVPlayer。
- **真实测试**：`Scripts/test-auth-asset.sh` 启动 Basic Auth WebDAV，先用 AVAsset 加载时长/轨道/尺寸，再用 AVPlayer 实际播放 4 秒确认进度推进；错误密码必须失败。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| AVAsset 认证加载 | duration **20.0s**、**1** 条视频轨、**1280×720** |
| AVPlayer 实际播放 | 4 秒后 position **3.598s**，item ready，无错误 |
| 错误密码 | asset load 返回错误 |
| `swift test` | **25/25 通过** |
| iOS/iPadOS、tvOS、visionOS generic | 全部 **BUILD SUCCEEDED** |
| iOS device Release | **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |

测试输出：

```
PASS: authenticated AVAsset load, duration/track/size via WebDAV Basic auth
PASS: AVPlayer advanced with authenticated WebDAV stream
PASS: wrong credentials fail asset load
```

证据：`reports/m4d-auth-asset.json`、`reports/m4d-auth-play.json`、`reports/m4d-auth-asset.txt`。

## 可复现差异与未验证

1. **移动端 UI 仍未实际启动**：没有安装 iOS/tvOS/visionOS runtime；触摸/焦点/空间布局/后台续播/音频输出待验证。桌面 AVPlayer 播放验证了同一 loader 链路，不等同于移动端实机。
2. **Jellyfin 远程播放未接**：需要 PlaybackInfo + HLS 转码参数或 token loader；当前仅 WebDAV MP4/MOV。
3. **MKV 仍不能播**：AVPlayer 不支持 MKV；需 libmpv/FFmpeg 集成。
4. **字幕/音轨未接**：远程 SRT/ASS、E-AC-3 5.1、音轨切换未在移动端实现。
5. **iPad/tvOS/visionOS 来源 UI**：tvOS/visionOS target 未包含 `MobileSourcesView`。
6. **CloudKit/Trakt/iCloud 同步未做。**
7. **Mac M3 尾项**：T07 深入、画质元数据补全。

## 下一项

Jellyfin 移动端远程 MP4 已在 [M4e Jellyfin 验收](M4E-JELLYFIN-MOBILE.md) 完成（PlaybackInfo/api_key/loader，AVPlayer 6s 5.866s）。剩余 M4f：HLS 转码/MKV、字幕/音轨、runtime 后三端截图、tvOS/visionOS 来源/焦点、CloudKit/Trakt。
