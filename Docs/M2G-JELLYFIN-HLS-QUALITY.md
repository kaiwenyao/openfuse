# M2g 验收记录：Jellyfin HLS 1080p 与轨道标签

日期：2026-11-20。分支 `m2g-jellyfin-hls-quality`。基线 Infuse 8.5.10（参照客户端待装）。

M2f 的 HLS 默认被压到 416×234，HUD 显示 Unknown/CC。本轮给 master.m3u8 加 8Mbps/1080p 限制，移动端 HUD 用 Jellyfin MediaStreams 的默认音轨/字幕名称，并标注「转码 AAC / 服务器」。

## 交付内容

- `hlsURL` 增加 `VideoBitrate=8000000`、`AudioBitrate=640000`、`MaxWidth/Height=1920/1080`。
- `MobilePlaybackItem` 增加 serverAudioLabel/serverSubtitleLabel；`MobilePlayerView` 在 AVPlayer 单轨/CC 标签时覆盖。
- 验收脚本断言 `-maxrate 8000000`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 分辨率 | 1920×1080 |
| Jellyfin 转码 | `-maxrate 8000000`，scale min(1920,1080)，AAC 6ch |
| 播放 | 12.0/60s |
| HUD 音轨 | E-AC-3 5.1 测试音轨 - Chinese - Dolby Digital+ - Default（转码 AAC） |
| HUD 字幕 | Chinese (Simplified) - ASS - External（服务器） |
| 脚本 | `Scripts/run-ios-jellyfin-hls.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 4K/HTTPS/多用户/真机 | 待验证 |

证据：`Evidence/101-ios-hls-1080.jpg`、`reports/m2g-ios-hls-playback.json`、`reports/m2g-jellyfin-1080.log`、`reports/m2g-ios-hls-1080.txt`。

## 可复现差异与未验证

1. **HLS 仍为 1080p H.264 8Mbps**；4K/HEVC 转码未验证。
2. **CPU 负载/流畅度**未测；转码画质未与源对比。
3. **HTTPS/反代/多用户/真实 iPhone**未测。
4. **音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、visionOS 真机**未完成。

## 下一项

M2h/M6d：4K/HTTPS/多用户 Jellyfin；音频听测；HDR 测量；真实 SMB3/Trakt；CloudKit；visionOS 真机。
