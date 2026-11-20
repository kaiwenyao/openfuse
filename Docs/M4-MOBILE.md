# M4a 验收记录：跨平台数据层与 iOS/iPadOS 首版

日期：2026-11-20。分支：`m4-shared-core`。基线：Infuse 8.5.10（参照客户端待装）。

本轮开始 M4：把 Foundation 数据层拆成 `OpenFuseData`，建立 iPhone/iPad 应用目标、示例 MP4、本地导入、AVPlayer 播放与续播。模拟器 runtime 在本轮构建时尚未安装，因此启动/触控/后台恢复只完成构建验证，运行项标「待验证」。

## 交付内容

- **`OpenFuseData` target**：媒体模型、SQLite 媒体库、扫描器、WebDAV、Jellyfin、TMDB、NFO、覆盖/播放记录、凭据、聚合全部跨平台；链接 `sqlite3`、`Security`。
- **`OpenFuseCore` 保持 macOS 播放层**：`MPVEngine`/`MPVGLView`/libmpv/OpenGL；`@_exported import OpenFuseData` 让 Mac 应用与测试无需改 import。
- **iOS/iPadOS 应用**：`Platforms/Mobile` + `project.yml`（XcodeGen），SwiftUI 媒体库/详情/设置；iPhone/iPad 共用 adaptive grid。
- **播放**：AVPlayer + AVKit `VideoPlayer`；本地 MP4/MOV；启动时按 `PlaybackStore` 续播；每秒记录位置，退出/后台写入 `playback.json`；完成后清位置并标记已看。
- **示例素材**：`Fixtures/mobile/openfuse-mobile.mp4`（H.264 High / AAC 立体声，20 秒，1.1 MB）与海报；首次启动复制到 Documents 并扫描入库。
- **导入**：Files 选择 MP4/MOV，复制到 Documents/Imports，重扫该来源；不支持 MKV 时给出明确提示。
- **服务器来源（M4b）**：设置入口「媒体来源」可添加/扫描/删除 WebDAV（OpenList）与 Jellyfin；密码/token 存 Keychain；扫描复用 `OpenFuseData` 的 WebDAV/Jellyfin scanner；Jellyfin 海报按 item id + token 生成远程 URL。
- **设置**：引擎/容器/音频/来源/版本说明。

## 构建

```bash
brew install xcodegen
Scripts/build-ios.sh                                  # iOS Simulator generic
Scripts/build-ios.sh 'generic/platform=iOS' build/mobile-device Release
Scripts/build-app.sh                                  # Mac 回归
swift test                                            # 25/25
```

生成的项目 `OpenFuseMobile.xcodeproj` 不入库；`project.yml` 可重建。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| `swift test` | **25/25 通过**（数据层拆分后） |
| Mac 构建/扫描 | 3 作品 / 4 集 / 3 组，正常 |
| iOS Simulator generic 构建 | **BUILD SUCCEEDED**（exit 0） |
| iOS device generic 构建 | **BUILD SUCCEEDED**（exit 0） |
| M4b 来源管理构建 | **BUILD SUCCEEDED**（Simulator + device，25/25 测试） |
| 来源添加/扫描 | 数据层复用；无模拟器/真机，UI 流程与 Keychain 交互待验证 |
| 模拟器启动/截图 | **待验证**：runtime 下载中（iOS 27.2 Simulator 8.32 GB） |
| 触控布局、横竖屏、后台续播 | **待验证**（无 runtime/真机） |
| iPad 分屏/键盘 | 未做（当前 NavigationStack 自适应，无三栏） |
| tvOS/visionOS | 未开始 |

构建产物：

```
build/mobile-derived/Build/Products/Debug-iphonesimulator/OpenFuse.app
build/mobile-device/Build/Products/Release-iphoneos/OpenFuse.app
```

## 可复现差异与未验证

1. **AVPlayer 打不开 MKV**；移动端首版只支持 MP4/MOV，MKV 需后续集成 libmpv/FFmpeg。字幕（ASS/PGS）、音轨切换、E-AC-3 5.1 未在移动端验证。
2. **无模拟器运行证据**：runtime 下载未完成；UI 布局、触控、旋转、后台恢复、音频输出均为待验证。
3. **移动端 Jellyfin/WebDAV 已接添加/扫描**，但远程播放未接：Jellyfin 直连 MKV/HEVC 依赖转码 HLS 或 libmpv，WebDAV Basic Auth 需要本机代理；当前 remote 条目显示「待接入」。
4. **无 CloudKit/Trakt/iCloud 续播**；播放记录只在本机。
5. **无 iPad 三栏、键盘快捷键、Apple Pencil/拖放；tvOS/visionOS 目标未建。**
6. **示例是 H.264/AAC 转码**，不是 HEVC Main 10/E-AC-3 原片；移动端音频验收未做。
7. **Mac 端 M3 剩余项**（防剧透、观看状态/分辨率筛选、继续观看排序、T07 深入）仍在待办。

## 下一项

M4d：完成模拟器 runtime 安装并实际启动/截图；远程播放（Jellyfin 转码/HLS 或 libmpv、WebDAV 鉴权代理）；MKV/字幕/音轨；tvOS/visionOS 来源/焦点细节；CloudKit/Trakt。iPad 分栏与 tvOS/visionOS 构建已在 [M4c 平台验收](M4C-PLATFORMS.md) 完成。
