# M4j 验收记录：移动端字幕自绘（简/繁 + seek 同步）

日期：2026-11-20。分支：`m4j-subtitles`。基线：Infuse 8.5.10（参照客户端待装）。

上一轮 mov_text 字幕虽被选中但画面不显示。本轮改用可自绘的 SRT 侧载字幕：`SubtitleParser` 解析 SRT/ASS，播放器用 0.25s ticker 按当前时间选择 cue，SwiftUI 叠加显示；简/繁两份侧载可切换，seek 后重新计算。

## 交付内容

- `SubtitleParser`（OpenFuseData）：SRT/VTT/ASS/SSA 解析；清理 HTML/ASS 覆盖标签、`\\N` 换行；单元测试。
- 移动样本旁提供 `OpenFuse Mobile Sample.zh-Hans.srt` / `.zh-Hant.srt`；seed 时从 bundle 复制。
- `MobilePlaybackItem.sidecarSubtitles`：本地播放条目用 `SubtitleCatalog.discover` 自动发现侧载。
- 播放器：
  - 侧载优先于 mov_text；菜单「关闭 / 简体 / 繁體」；
  - `Timer.publish(0.25s)` 更新 HUD 时间与当前 cue，修复此前 HUD 停在 0.0；
  - 字幕以系统字体叠加（中日文 fallback），非 libass 样式；
  - 测试钩子 `OPENFUSE_AUTOPLAY_SEEK` / `PAUSE` 用于定位 cue。
- 音轨菜单（E-AC-3/AAC）保留；音频输出仍未听测。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 简体字幕 | seek 4.5s，HUD 4.1/20.1，显示「最初の字幕… / 第一句：画面 2.5 秒…」 |
| 繁体字幕 | seek 10s，HUD 10.1/20.1，显示「第二句：拖動後字幕仍同步…」 |
| 简繁切换 | 菜单/环境选择生效，标签「中文（简体）/（繁體）(SRT)」 |
| Seek 同步 | seek 后 ticker 重新选取 cue，截图验证 |
| 字体 fallback | 系统字体显示中/日文，无豆腐块 |
| 音轨 | E-AC-3 5.1 选中；音频未听测 |
| `swift test` | **27/27 通过**（新增 SRT/ASS 解析测试） |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |

证据：

- `Evidence/49-ios-subtitle-hans.jpg`
- `Evidence/50-ios-subtitle-hant.jpg`
- `reports/m4j-subtitles.txt`

## 可复现差异与未验证

1. **移动端字幕是 SRT 自绘，不是 ASS/libass**：没有 ASS 定位/样式/字体覆盖；Mac 端仍使用 libmpv/libass。
2. **音频未实际听测**：只确认轨道选择与画面推进；E-AC-3 5.1 输出未验证。
3. **远程来源侧载字幕未接**：WebDAV/Jellyfin 的远程字幕尚未下载/发现。
4. **tvOS 仍用 AVKit 默认字幕**，没有这套自绘 UI；未验证 mov_text/字幕按钮效果。
5. **visionOS runtime 未安装**；仅构建。
6. **CloudKit/Trakt/iCloud 同步、M3 T07 其他场景、WebDAV MKV 分辨率**未做。

## 下一项

M4k：移动端远程字幕、ASS/libass 或更完整字幕样式；音频听测；visionOS runtime；CloudKit/Trakt；M3 T07/WebDAV MKV 分辨率。
