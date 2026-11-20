# M4l 验收记录：远程 WebDAV 字幕画面修复

日期：2026-11-20。分支：`m4l-remote-fix`。基线：Infuse 8.5.10（参照客户端待装）。

M4k 已能下载 WebDAV 字幕，但截图看不到字幕：远程播放器时长显示 0/0，seek 不可靠。排查后改为从播放器当前 `AVPlayerItem.asset` 读取时长（custom loader asset），播放前等待 ready，并新增“播放到 N 秒自动暂停”的测试钩子。远程 WebDAV 字幕画面现已验证。

## 修复内容

- 时长：`player.currentItem?.asset`（认证 loader）而非新建 `AVURLAsset(url:)`；远程 HUD 显示 20.0s。
- 播放顺序：`waitUntilReady` → 可选 seek → play/pause；seek 后等待 500ms。
- 新测试钩子：`OPENFUSE_AUTOPLAY_PAUSE_AT=4.5`，ticker 检测播放时间跨过目标后暂停，避免截图时播放继续。
- 保留 `OPENFUSE_AUTOPLAY_SEEK`，但远程 seek 仍不如 pause_at 稳定，已记录。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| WebDAV 远程时长 | **20.0s**（此前 0.0） |
| 暂停点 | HUD **4.6/20.0s** |
| 远程字幕 | 「最初の字幕… / 第一句：画面 2.5 秒，字幕准时出现。」 |
| 字幕菜单 | 中文（简体）(SRT)，简/繁文件已下载缓存 |
| 服务器 | 字幕 GET 200，视频 HEAD/GET 200/206 |
| `swift test` | **27/27 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| visionOS runtime | 下载约 53.3%，未安装 |

证据：`Evidence/52-ios-webdav-subtitle.jpg`、`reports/m4l-remote-subtitle.txt`。

## 可复现差异与未验证

1. **远程 seek 仍不稳定**；本轮用播放到 4.5s 暂停验证字幕，未证明远程拖动后字幕同步。
2. **Jellyfin 外挂字幕未接**；内嵌字幕仍由 AVKit 处理。
3. **音频未听测**。
4. **visionOS runtime 未安装**，仅构建。
5. **CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率**未做。
6. **ASS 样式/字体覆盖**仍无移动端 libass。

## 下一项

M4m：远程 seek/字幕同步稳定性、Jellyfin 外挂字幕、音频听测、visionOS runtime、CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率。
