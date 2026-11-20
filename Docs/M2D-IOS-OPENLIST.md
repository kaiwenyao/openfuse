# M2d 验收记录：iPhone 真实 OpenList 播放

日期：2026-11-20。分支：`m2d-ios-openlist`。基线：Infuse 8.5.10（参照客户端待装）。

M2c 验证了 Mac 连真实 OpenList。本轮在 iPhone 18 Pro 模拟器用同一 Docker OpenList `/dav`，实际播放 1080p MP4、远程简中 SRT、seek 与进度回写；并修复移动端暂停不保存进度。

## 交付内容

- `Scripts/run-ios-openlist.sh`：起 OpenList Docker、创建 Local 存储、构建/安装/启动 iPhone、自动播放、截图、读 playback.json。
- 移动端 `AUTOPLAY_PAUSE_AT` 暂停时调用 `saveProgress()`（产品行为修复）。
- 远程字幕索引 1 自动选中 SRT。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设备 | iPhone 18 Pro 模拟器 / iOS 27.2 |
| OpenList | Docker `/dav` + Local 存储 |
| 播放 | t=15.958s，HUD 12.1/20.1 |
| 音轨 | E-AC-3 5.1 |
| 字幕 | 中文（简体）(SRT)，中日双语同步 |
| 进度 | playback.json position **12.061s** |
| 远程 URL | `5244/dav/local/Movies/...` |
| 脚本 | `Scripts/run-ios-openlist.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 百度网盘/真机/听测 | 待验证 |

证据：`Evidence/96-ios-openlist.jpg`、`reports/m2d-ios-openlist-playback.json`、`reports/m2d-ios-openlist.txt`。

## 可复现差异与未验证

1. **未接百度网盘账号**；OpenList 云 302/限流未验证。
2. **模拟器**，真机 AVPlayer/HDR/音频未验证。
3. **iPad OpenList 未单独跑**（同一 MobileLibraryModel）。
4. **音频听测、HDR 测量、真实 Jellyfin/SMB/Trakt、CloudKit、visionOS 真机**未完成。

## 下一项

M2e/M6d：百度网盘/云跳转；iPad/真机 OpenList；音频听测；HDR 测量；真实 Jellyfin/SMB/Trakt；CloudKit；visionOS 真机。
