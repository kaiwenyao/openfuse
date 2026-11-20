# M4i 验收记录：移动端音轨/字幕轨道与 Apple TV 实际运行

日期：2026-11-20。分支：`m4i-tracks`。基线：Infuse 8.5.10（参照客户端待装）。

本轮两件事：移动端样本升级为 HEVC Main 10 + E-AC-3 5.1 + AAC 双音轨、简繁 mov_text 字幕，并在播放器加入音轨/字幕菜单；tvOS 27.2 runtime 安装完成后，Apple TV 模拟器实际启动并播放。

## 交付内容

- **新移动样本**：`openfuse-mobile.mp4` = HEVC Main10 1920×1080 + E-AC-3 5.1 + AAC 立体声 + 简体/繁体中文 mov_text，20.1s。
- **轨道菜单**：AVPlayer `AVMediaSelectionGroup` 枚举 audible/legible；过滤 forced 字幕；音轨标签区分 E-AC-3 5.1 / AAC；字幕菜单含「关闭」。
- **测试钩子**：`OPENFUSE_AUTOPLAY_AUDIO_INDEX`、`OPENFUSE_AUTOPLAY_SUBTITLE_INDEX`；HUD 显示当前轨道与字幕。
- **tvOS 实际运行**：tvOS 27.2 runtime 安装；Apple TV 4K 模拟器安装 `com.openfuse.tv`，焦点网格与全屏播放验证。
- tvOS autoplay 钩子（`OPENFUSE_AUTOPLAY=1`）用于截图。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| iOS 样本 | HEVC/EAC3 画面推进；HUD `音轨 1 · E-AC-3 5.1 · 字幕：简体中文` |
| 字幕文字 | **未确认**：mov_text 已选中，但截图未出现字幕文本；原生渲染/自定义 overlay 仍需修 |
| tvOS 启动 | 焦点网格实际渲染 |
| tvOS 播放 | 全屏 HEVC/EAC3，帧时间码 5.625s，AVKit 字幕/音轨按钮可见 |
| `swift test` | **26/26 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 音频听测 | **未做** |
| visionOS 运行 | **待验证**：runtime 未安装 |

证据：

- `Evidence/46-ios-tracks.jpg`
- `Evidence/47-tvos-home.jpg`
- `Evidence/48-tvos-playback.jpg`
- `reports/m4i-tracks-tvos.txt`

## 可复现差异与未验证

1. **音频没有实际听测**：只确认轨道选择与画面推进；E-AC-3 5.1 输出未验证。
2. **字幕文字未显示**：mov_text 轨道存在且被选中，但 VideoPlayer 截图无字幕文本；需改用自绘 SRT/ASS 或 legible output 调试。
3. **tvOS 遥控焦点导航未自动化**；仅默认焦点与 autoplay 播放。
4. **visionOS runtime 未安装**，仅构建。
5. **移动端远程 WebDAV/Jellyfin 未在本轮重测**；使用新 HEVC 样本后需回归。
6. **真实 Jellyfin/OpenList、CloudKit/Trakt、M3 T07 其他场景**未做。

## 下一项

M4j：字幕自绘（SRT/ASS）与音频听测；visionOS runtime；远程来源使用新样本回归；CloudKit/Trakt；M3 T07/WebDAV MKV 分辨率。
