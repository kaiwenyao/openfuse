# M4u 验收记录：Mac → HTTP 同步 → iPhone 续播

日期：2026-11-20。分支 `m4u-http-sync`。基线 Infuse 8.5.10（参照客户端待装）。

此前只有 Mac 文件/CloudKit 同步模拟。本轮新增 HTTP transport 与移动端拉取，让 Mac 播放的真实 Jellyfin 进度被 iPhone 启动时读取并自动续播。

## 交付内容

- `HTTPProgressTransport`（GET/POST JSON 数组）。
- Mac：`OPENFUSE_SYNC_URL` 接入 `--sync-progress`。
- 移动端：
  - `OPENFUSE_SYNC_URL`；启动/回到前台同步；
  - autoplay 前 `await syncProgress(force:true)`；
  - Jellyfin item 读取记录缺失时再强制同步一次。
- `ResumePolicy`：<60s 短片片尾保护改为 10% 时长，避免 20s 样片 11s 被误判近结尾。
- `Tools/progress_sync_fixture.py`：本地合并服务。
- `Scripts/run-cross-device-sync.sh`：Mac 扫描/播放/推送，iPhone 安装/拉取/续播断言。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Mac 播放 | 11.022s |
| Mac 推送 | POST 1 条 |
| iPhone 拉取 | resume **10.02s** |
| iPhone HUD | 10.0 / 20.1s |
| 指纹 | `jellyfin://c135.../c9a8.../c9a8...` 两端一致 |
| 脚本 | `Scripts/run-cross-device-sync.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| TLS/鉴权/真实 CloudKit/真机 | 待验证 |

证据：`Evidence/103-cross-device-sync.jpg`、`reports/m4u-*`。

## 可复现差异与未验证

1. **HTTP 无 TLS/鉴权**，仅 LAN fixture；生产需 HTTPS/token。
2. **真实 CloudKit 账号/真机**未测。
3. **并发写冲突**仅按 lastPlayedAt 合并，未压测。
4. **HLS seek 后截图帧时间码 4s、HUD 10s**，需查 AVPlayer/HLS 时间戳同步。
5. **音频/HDR/visionOS 真机**未完成。

## 下一项

M4v/M6d：HTTPS/token 同步、并发冲突、HLS seek 时间戳；真实 CloudKit/真机；音频/HDR/visionOS。
