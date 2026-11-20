# M2e 验收记录：真实 Jellyfin 12 全链路

日期：2026-11-20。分支 `m2e-real-jellyfin`。基线 Infuse 8.5.10（参照客户端待装）。

此前 Jellyfin 只用 Python 夹具。本轮用官方 `jellyfin/jellyfin:12.4.0` Docker，脚本完成启动向导、用户、媒体库、扫描，OpenFuse 直连播放/seek/字幕，并在服务器 UserData 验证位置回写。

## 交付内容

- `Scripts/run-real-jellyfin.sh`：
  - `Startup/Configuration` → `GET/POST Startup/User` → `Startup/Complete`；
  - `Authorization: MediaBrowser ...` 登录；
  - 创建 Movies VirtualFolder，等待扫描；
  - OpenFuse 扫描/播放/seek/报告/服务器 UserData 断言；
  - 测试服设 `MinResumeDurationSeconds=0`（20s 样片低于默认 300s）。
- **兼容修复**：Jellyfin 12 只认 `Authorization` 登录头（原 X-Emby-Authorization 失败）。
- **退出修复**：`--quit-after` 终止前调用 `finishSession()`，确保发送 `Sessions/Playing/Stopped`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 服务 | Jellyfin 12.4.0 Docker |
| 扫描 | 1 电影，`1080p · Jellyfin` |
| 播放 | seek 10 → 11.106/20.041 |
| 音轨 | 6 声道 E-AC-3 |
| 字幕 | `mpv:1` 默认字幕 |
| 直连 URL | `/Videos/.../stream?Static=true` |
| 服务器位置 | **110220000 ticks（11.022s）** |
| Played | **false**，PlayedPercentage 54.82 |
| 脚本 | `Scripts/run-real-jellyfin.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| HTTPS/转码/多用户 | 待验证 |

证据：`Evidence/97-real-jellyfin.jpg`、`reports/m2e-real-jellyfin-*.json`、`reports/m2e-real-jellyfin.txt`。

## 可复现差异与未验证

1. **只测 Jellyfin 12.4.0 HTTP + 直连**；HTTPS/反代/转码/HLS/多用户未测。
2. **20s 样片**；测试服改短续播阈值，真实长片默认阈值行为未测。
3. **真实百度网盘、SMB3、Trakt、CloudKit、visionOS 真机**未完成。
4. **音频/字幕人耳与 HDR 测量**未完成。

## 下一项

M2f/M6d：HTTPS/转码/多用户 Jellyfin；百度网盘；SMB3/Trakt/CloudKit；音频/HDR/visionOS 真机。
