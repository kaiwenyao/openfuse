# M4v 验收记录：Jellyfin MP4 直连与跨设备续播

手机样片 SHA-256：`2df2c5d26ccc0cad1282a3c765002c9797396e02ae9cfd63619c7525374acda6`。

日期：2026-11-20。分支 `m4v-direct-mp4-resume`。基线 Infuse 8.5.10（参照客户端待装）。

M4u 的续播状态正确，但 Jellyfin MP4 因 container 字段是 `mov,mp4,m4a,3gp,3g2,mj2`，移动端按整串匹配失败，误走 HLS。本轮按逗号拆分识别直连 MP4，并统一用 `AVURLAssetHTTPHeaderFieldsKey` 注入 Authorization，绕开自定义 loader。

## 交付内容

- 容器判断：`Set(container.split(","))` 与 mp4/m4v/mov 求交。
- 所有 http(s) 媒体用 AVURLAsset HTTP header options（Jellyfin 12 需要 Authorization）。
- 保留 WebDAV/SMB loader 路径。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 直连 URL | `/Videos/<id>/stream?Static=true&MediaSourceId=...` |
| iPhone resume | **10.02s** |
| 播放 | 出画，HUD 12.8/20.1 |
| 脚本 | `Scripts/run-cross-device-sync.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 时间戳一致性 | **通过（修正样片后）**：画面 11.0s / HUD 11.0s |

证据：`Evidence/104-direct-mp4-resume.jpg`、`reports/m4v-direct-mp4-*`、修正后 `Evidence/105-direct-mp4-aligned.jpg`。

## 时间戳偏差根因与修复

- 原手机样片首帧本身是 **4s**（主 MKV 为0s），且 `-c copy` remux 默认 `hev1`，AVPlayer 不渲染。
- 重新从主 MKV `-t 20 -c copy -tag:v hvc1 -movflags +faststart` 生成；首帧0s、hvc1。
- 修正后直连续播：画面 **11.0s / HUD 11.0s**，完全对齐。
- `make_fixtures.sh` 已加入手机样片生成步骤。
- 剩余：HTTP 同步无 TLS/鉴权；并发/CloudKit/真机未测；音频/HDR/visionOS 真机未测。

## 下一项

M4w/M6d：修正 MP4 seek 显示时间戳；同步 HTTPS/token；真实 CloudKit/真机；Jellyfin UI 切换/HTTPS；SMB 多GB/DFS；音频/HDR/visionOS。
