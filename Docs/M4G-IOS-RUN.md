# M4g 验收记录：iOS 模拟器实际启动、播放与续播

日期：2026-11-20。分支：`m4g-ios-run`。基线：Infuse 8.5.10（参照客户端待装）。

iOS 27.2 Simulator runtime 安装完成。本轮首次实际启动 iPhone/iPad 应用，验证首屏、iPad 分栏、样本 MP4 播放和退出后重启续播，并修复一个真实的文件 URL 解析 bug。

## 交付内容

- **运行验证**：iPhone 18 Pro + iPad Pro 13-inch 安装并启动 `com.openfuse.mobile`。
- **iPad 分栏**：常规宽度 `NavigationSplitView` 侧栏（海报、标题、集数）+ 详情占位，实际渲染。
- **播放**：样本 MP4 通过 AVPlayer 播放，画面时间码推进；测试 HUD 显示 3.0/20.0s。
- **续播**：`OPENFUSE_AUTOPLAY_STOP_AFTER=5` 自动保存并关闭，`playback.json` 记录 4.795s；重启后 3 秒 HUD 为 12.0/20.0s（从保存位置继续），不是从 0。
- **修复**：本地媒体 `fileURL` 存的是 `file://` URL 字符串，移动端曾用 `URL(fileURLWithPath:)` 当路径解析导致 `item=false`；改为先 `URL(string:)`。
- **测试钩子**：`OPENFUSE_AUTOPLAY=1` 启动即播；`OPENFUSE_AUTOPLAY_STOP_AFTER=N` 自动保存/关闭；HUD 仅在测试钩子下显示。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| iPhone 首屏 | 1 作品/1 集，样本海报与标题正常 |
| iPad 分栏 | 侧栏 + 详情占位实际渲染 |
| 播放 | HUD **3.0 / 20.0s**，画面时间码推进 |
| 自动保存 | `playback.json` position **4.795s** |
| 重启续播 | 3 秒后 HUD **12.0 / 20.0s**（从保存位置继续） |
| `swift test` | **26/26 通过** |
| iOS/iPadOS、tvOS、visionOS、iOS device | 全部 **BUILD SUCCEEDED** |
| 音频/字幕 | **未验证**：模拟器声音未做人工听测，字幕/音轨未接 |

证据（截图）：

- `Evidence/38-ios-home.jpg`
- `Evidence/39-ios-playback.jpg`
- `Evidence/40-ios-resume.jpg`
- `Evidence/41-ipad-split.jpg`
- `Evidence/reports/m4g-ios-run.txt`

## 可复现差异与未验证

1. **音频没有人工听测**：截图只证明画面/进度；模拟器音频输出与 E-AC-3 5.1 未验证。
2. **测试 HUD** 只在 autoplay 钩子显示，正常 UI 仍使用 AVKit 控件。
3. **tvOS/visionOS 没有安装 runtime**，仍只有构建验证。
4. **远程播放没有在移动端实际跑**：WebDAV/Jellyfin loader/HLS 仅桌面 probe 与构建验证。
5. **字幕/音轨切换未接**；AVPlayer 默认轨。
6. **无 CloudKit/Trakt/iCloud 同步。**
7. **M3 画质元数据/T07 其他场景未补。**
8. **示例是 H.264/AAC 转码**，不是移动端直接解 HEVC/E-AC-3。

## 下一项

移动端 WebDAV/Jellyfin（含 60s HLS）远程播放已在 [M4h 验收](M4H-MOBILE-REMOTE.md) 实际跑通。剩余 M4i：字幕/音轨/音频听测、tvOS/visionOS runtime、真实 Jellyfin/OpenList、CloudKit/Trakt；M3 画质元数据/T07。
