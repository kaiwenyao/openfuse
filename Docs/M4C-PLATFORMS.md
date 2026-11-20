# M4c 验收记录：iPad 分栏与 tvOS/visionOS 目标

日期：2026-11-20。分支：`m4c-ipad`。基线：Infuse 8.5.10（参照客户端待装）。

本轮把移动端从“iPhone 单栏”推进到 iPad 分栏，并建立 Apple TV、Vision Pro 目标。三端共享 `MobileLibraryModel`、示例 MP4 与 `OpenFuseData`；播放仍用 AVPlayer（MP4/MOV）。模拟器 runtime 下载未完成，因此三端只做构建验证，UI/遥控/手势/空间布局标「待验证」。

## 交付内容

- **iPad 分栏**：`horizontalSizeClass == .regular` 时使用 `NavigationSplitView`：左侧媒体库列表（海报缩略图、标题、年份/集数），右侧 `MobileDetailView`；iPhone 继续 `NavigationStack` 单栏。来源/导入/设置工具栏共用。
- **tvOS**：`OpenFuseTV` target；大屏网格 + `.buttonStyle(.card)` 焦点卡片，选中播放示例；`TVPlayerView` 用 AVPlayer、续播、退出保存进度。文本明确“服务器来源/MKV/字幕待接入”。
- **visionOS**：`OpenFuseVision` target；`NavigationSplitView` 侧栏 + 详情 + 播放 sheet；默认窗口 1100×760；空间沉浸式布局待后续。
- **共享**：三端均复用 `MobileLibraryModel`（库/来源/续播）与内置 `openfuse-mobile.mp4`；tvOS/visionOS 不包含 iOS 专属 `MobileSourcesView`（服务器来源 UI 后续单独适配）。
- **脚本**：`Scripts/build-platforms.sh` 一次构建 iOS/iPadOS、tvOS、visionOS generic simulator。

## 实测结果

| 目标 | 命令 | 结果 |
| --- | --- | --- |
| iOS Simulator | `Scripts/build-ios.sh` | **BUILD SUCCEEDED**（fat x86_64+arm64） |
| iOS device | `Scripts/build-ios.sh 'generic/platform=iOS' build/mobile-device Release` | **BUILD SUCCEEDED**（arm64） |
| tvOS Simulator | `xcodebuild -scheme OpenFuseTV -destination 'generic/platform=tvOS Simulator'` | **BUILD SUCCEEDED** |
| visionOS Simulator | `xcodebuild -scheme OpenFuseVision -destination 'generic/platform=visionOS Simulator'` | **BUILD SUCCEEDED** |
| SwiftPM | `swift test` | **25/25 通过** |
| Mac | `Scripts/build-app.sh` | 成功（回归） |
| 三端实际启动/截图 | — | **待验证**：无安装的模拟器 runtime；iOS runtime 下载约 37%（8.32 GB） |

构建产物：

```
build/mobile-derived/Build/Products/Debug-iphonesimulator/OpenFuse.app
build/tv-derived/Build/Products/Debug-appletvsimulator/OpenFuse.app
build/vision-derived/Build/Products/Debug-xrsimulator/OpenFuse.app
```

## 可复现差异与未验证

1. **没有运行时证据**：UI 布局、iPad 分栏折叠、tvOS 焦点、visionOS 窗口/空间布局、触控/遥控/手势、后台续播、音频均未实际执行；所有截图待补。
2. **三端只播本地 MP4/MOV**；MKV、字幕、音轨、E-AC-3 5.1 未接；tvOS/visionOS 播放器只是基础 AVPlayer。
3. **tvOS/visionOS 没有服务器来源 UI**；`MobileLibraryModel` 已含 WebDAV/Jellyfin 扫描，但这两个 target 未包含 `MobileSourcesView`。
4. **无 CloudKit/Trakt/iCloud 同步**；示例仅本地 Documents。
5. **iPad 分栏没有三栏/键盘快捷键/拖放**；visionOS 无沉浸式影院/空间音频。
6. **Mac M3 尾项**：T07 深入、画质元数据补全。
7. **真实设备/Infuse 对照/人工听测**仍缺。

## 下一项

M4d：runtime 完成后实际启动三端并截图；远程播放代理/转码；MKV/字幕/音轨；tvOS/visionOS 来源与焦点细节；CloudKit/Trakt 同步。
