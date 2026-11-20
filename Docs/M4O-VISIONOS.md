# M4o 验收记录：Vision Pro 模拟器实际启动与播放

日期：2026-11-20。分支：`m4o-visionos`。基线：Infuse 8.5.10（参照客户端待装）。

visionOS 27.2 runtime 安装完成。本轮实际启动 Apple Vision Pro 模拟器中的 OpenFuse：空间窗口显示侧栏/详情，autoplay 打开播放 sheet，HEVC Main10/E-AC3 样本渲染到 24s 时间码。

## 交付内容

- visionOS 27.2 runtime（24N120）安装；Apple Vision Pro 模拟器。
- `com.openfuse.vision` 安装/启动；`OpenFuseVision` target 使用 `NavigationSplitView` 侧栏+详情。
- autoplay 钩子：`OPENFUSE_AUTOPLAY=1` 自动选择首部作品并打开 `VisionPlayerView`。
- 五端运行状态：Mac、iPhone、iPad、Apple TV、Vision Pro 均已有实际启动截图。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Vision Pro 启动 | 空间房间中出现 OpenFuse 窗口，侧栏海报/详情占位 |
| 播放 | autoplay 打开 sheet，HEVC/EAC3 画面到帧时间码 24s |
| `swift test` | **27/27 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 音频 | 未听测 |
| 空间交互/沉浸式影院 | 未实现/未验证 |

证据：`Evidence/55-visionos-home.jpg`、`Evidence/56-visionos-playback.jpg`、`reports/m4o-visionos.txt`。

## 可复现差异与未验证

1. **音频未听测**：Vision Pro 空间音频/E-AC-3 5.1 输出未验证。
2. **窗口是普通空间窗口**，不是沉浸式影院；无环境/屏幕尺寸/手势调优。
3. **手眼焦点/手势未自动化**，只验证默认渲染与 autoplay。
4. **visionOS 字幕自绘/音轨菜单未接**；只有 AVKit 基础播放。
5. **CloudKit/Trakt/iCloud、M3 T07/WebDAV MKV 分辨率、真实 OpenList/Jellyfin、Infuse 对照**未做。
6. **移动端自动播放时序仍脆弱**；Jellyfin 外挂字幕仅简体。

## 下一项

M5：SMB/Plex/Emby、HDR/AirPlay、自包含打包；同步/账号；音频主观听测；M3 尾项与真实服务验证。
