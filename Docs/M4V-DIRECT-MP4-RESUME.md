# M4v 验收记录：Jellyfin MP4 直连与跨设备续播

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
| 时间戳一致性 | **未通过**：画面 16.833s / HUD 12.8s（约+4s） |

证据：`Evidence/104-direct-mp4-resume.jpg`、`reports/m4v-direct-mp4-*`。

## 可复现差异

1. **直连 MP4 seek 后画面时间码领先 HUD 约4s**；HLS 路径此前约+7s。续播状态（10.02s）正确，但显示时间需修 AVPlayer 编辑列表/PTS。
2. HTTP 同步无 TLS/鉴权；并发/CloudKit/真机未测。
3. 音频/HDR/visionOS 真机未测。

## 下一项

M4w/M6d：修正 MP4 seek 显示时间戳；同步 HTTPS/token；真实 CloudKit/真机；Jellyfin UI 切换/HTTPS；SMB 多GB/DFS；音频/HDR/visionOS。
