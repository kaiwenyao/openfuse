# M7 播放器：控制栏可见性、WebDAV 路径与 IINA 式播放管线

日期：2026-11-20。范围：macOS 主应用（`Sources/OpenFuseApp`、`Sources/OpenFuseCore`、`Sources/OpenFuseData`）。
移动端 `Platforms/Mobile/MPV/MobileMPVEngine.swift` 本轮不动。

## 1. 结论

三个问题都已修：

1. **播放器控制栏在默认明亮主题下不可见**：字幕、音轨、倍速三个菜单和返回/日志图标都画成了黑底黑字。改为播放器挂载期间窗口强制 `darkAqua`，退出时恢复用户主题；进度条换成自绘 `ScrubberBar`，未播放段/已缓冲段在黑底上可见。
2. **WebDAV 加载中连点导致路径重复**：导航从“追加完整路径字符串”改成纯值状态机 `RemotePathState`（规范化 + 幂等 + 加载中丢弃），并把旧版本持久化的重复路径迁移成规范形式。
3. **MKV 偶发卡顿**：按 IINA 的 `MPVController` / `ViewLayer` / `VideoView` 结构重写渲染管线（CAOpenGLLayer + 专用 GL 队列 + CVDisplayLink + `display-fps-override`），把 10 Hz 播放头从 `PlayerModel` 拆到独立的 `PlaybackClock`。控制栏淡出造成的约 100 ms 停帧消失，帧间隔从 p99 51.9 ms / max 100.8 ms 降到 p99 12.2 ms / max 15.8 ms（60 s 连播）。

## 2. 复现与根因

### 2.1 控制栏不可见（明亮主题）

0.4.0 把默认外观改成明亮，但播放器仍是纯黑背景。AppKit 绘制的 `Menu` 标签、SF Symbol 按钮、`Slider` 未播放轨道用的是 `labelColor`/`controlTextColor`，明亮模式下是黑色。

同一份代码、同一台机器，只切外观：

```bash
OPENFUSE_SUPPORT_DIR=/tmp/of/support OPENFUSE_FORCE_CONTROLS=1 \
  build/OpenFuse.app/Contents/MacOS/OpenFuse \
  --open Fixtures/generated/openfuse-fixture.mkv \
  --capture-ui /tmp/of/player-ui.png --ui-after 5 --quit-after 8
# 再加 --appearance dark 对照
```

- 明亮：返回箭头、日志图标、三个菜单全部消失；进度条未播放段不可见。
- 深色：`中文（简体）(ASS) ⌄ / 中文·E-AC-3 5.1 测试音轨 ⌄ / 1.00x ⌄` 正常显示。

量化：控制栏右侧菜单条（截图 2360×1520，裁剪 `760:46:1230:1400`）的 `YAVG` 修复前是 **16**（纯黑），修复后是 **46**。

### 2.2 WebDAV 路径重复

旧代码（`Sources/OpenFuseApp/BrowserView.swift`）：

```swift
pathStack.append(entry.path)      // entry.path 是相对来源根的完整路径
.disabled(!entry.isDirectory && !entry.isPlayableVideo)   // 加载中目录行仍可点
```

`.task(id: currentPath)` 在路径变化后才开始加载，加载完成前 `isLoading` 为真但行按钮未禁用，于是连点 N 次就追加 N 次同一条完整路径；面包屑按 `.lastPathComponent` 渲染，右上角出现 `Show / Show / Show`，并被 `setWebDAVPath` 写进持久化。

### 2.3 偶发卡顿

旧实现是 `NSOpenGLView.draw(_:)` 在主线程渲染，`swapInterval = 1` 的 `flushBuffer` 也在主线程；同时 `PlayerModel.position` 是 `@Published`，mpv 每 50 ms 推一次就让整棵播放器视图（三个 `Menu`、`AVRoutePickerView`、全屏按钮）重新布局。任何一次主线程停顿都会让下一帧错过 vsync。

用 `OPENFUSE_DEBUG_GL=1` 给每次 `draw` 打单调时间戳，20 s 连播（控制栏自动隐藏，即真实使用路径）：

| 指标 | 修复前 | 修复后（60 s） |
| --- | --- | --- |
| 平均/中位帧间隔 | 41.67 ms | 8.35 ms（跟屏刷新） |
| p99 | 51.9 ms | 12.2 ms（多次运行 11.6–12.6） |
| 最大 | 100.8 ms（t≈2.95 s，正是控制栏 3.2 s 淡出） | 15.8 ms（多次运行 15.8–18.9） |
| >50 ms 的间隔 | 20 s 内 22 次 | 0 次（60 s） |
| 控制栏淡出瞬间的间隔 | ~100 ms | 12.3 ms |

另外 `display-fps` 现在是 CVDisplayLink 实测的 120.001（旧实现靠 mpv 估算），因此 23.976/24 fps 的片源能对齐 5 个刷新周期。

## 3. 与 IINA 的对应关系

架构按 IINA `develop` 的三件套移植，只取播放相关部分，不带 OSC/插件/画中画：

| IINA | OpenFuse | 说明 |
| --- | --- | --- |
| `iina/MPVController.swift` | `Sources/OpenFuseCore/MPVController.swift` | mpv 句柄、选项、`mpv_set_wakeup_callback` 事件泵、属性观察（含 `MPV_FORMAT_NODE` 的 `track-list`）、`ADVANCED_CONTROL` 渲染上下文、CGL 锁 |
| `iina/ViewLayer.swift` | `Sources/OpenFuseCore/MPVVideoLayer.swift` | `CAOpenGLLayer`：`canDraw` 用 `mpv_render_context_update & MPV_RENDER_UPDATE_FRAME` 门控；`display()` 覆写 + `MainThreadPriorityLock`；AppKit 跳过绘制时用 `SKIP_RENDERING` + `BLOCK_FOR_TARGET_TIME=0` 补一帧；10bit 像素格式与 `bufferDepth=16`；`CGLEnable(kCGLCEMPEngine)` |
| `iina/VideoView.swift` | `Sources/OpenFuseCore/MPVVideoView.swift` | `NSView` + layer、`wantsBestResolutionOpenGLSurface`、CVDisplayLink 每刷新一次 `mpv_render_context_report_swap()`、按屏幕设置 `display-fps-override`、暂停 4 s 后停 link 省电 |
| `MPVController.mpvInitRendering` | `MPVVideoLayer.attachRenderer()` | `mpv_render_context_create` 带 `MPV_RENDER_PARAM_ADVANCED_CONTROL` |
| `ViewLayer.captureSnapshot()` | `MPVVideoLayer.requestFrameCapture(to:)` | 读 layer 自己的 FBO（`GL_COLOR_ATTACHMENT0`），保留验收脚本的抓帧能力 |

`MPVEngine` 保留为门面（`openfuse-probe` 与 `AppModel` 的调用点不变），内部换成 `MPVController` + `MPVVideoLayer`；旧的 `Sources/OpenFuseCore/MPVGLView.swift` 已删除。

### 线程与时序契约

- mpv 命令/属性写入任意线程，`commandLock` 串行化；`seek`/`loadfile` 走 `mpv_command_async`，主线程不再等解封装器。
- 渲染只在 `mpvGLQueue`（持 CGL 锁）或 Core Animation 的绘制线程上发生；释放渲染上下文在 CGL 锁内完成，与进行中的 `draw` 互斥。
- 事件泵：`mpv_set_wakeup_callback` → 串行队列排空 `mpv_wait_event(handle, 0)`；属性/时间回调统一投递主线程。
- 拆除顺序：停 CVDisplayLink → 停更新回调 → 释放渲染上下文 → `mpv_unobserve_property(0)` → `quit` → `eventQueue.sync {}` 保证没有线程停在 `mpv_wait_event` → `mpv_terminate_destroy`。

## 4. UI 侧的解耦

- `Sources/OpenFuseCore/PlaybackClock.swift`：10 Hz 发布的播放头（`position` + `buffered`），可注入时钟便于单测。`PlayerModel.position` 改为普通存储，只用于续播/上报。
- `Sources/OpenFuseApp/PlayerScrubber.swift`：`PlayerScrubber` 只观察 `PlaybackClock`；`PlayerTimeRow` 把两侧时间码和它放在一起，因此 10 Hz 只重算这一行。
- `Sources/OpenFuseApp/PlayerView.swift`：拆出 `PlayerChrome`（顶栏/传输条/日志面板），根视图不再随播放头刷新。
- `Sources/OpenFuseApp/PlayerChromeHost.swift`：`NSViewRepresentable`，挂载时把窗口设为 `.darkAqua`，卸载时恢复 `AppTheme.stored.appearance`。

## 5. mpv 选项（相对旧实现的差异）

| 选项 | 值 | 原因 |
| --- | --- | --- |
| `vo` / `keepaspect` / `gpu-hwdec-interop` | `libmpv` / `yes` / `auto` | IINA 同款 |
| `hwdec` / `vd-lavc-threads` | `videotoolbox` / `0` | 硬件解码，线程自动 |
| `cache` / `cache-secs` | `yes` / `20` | IINA 网络缓存段 |
| `demuxer-max-bytes` / `demuxer-max-back-bytes` / `demuxer-readahead-secs` | `512MiB` / `128MiB` / `20` | 深读前，减少长 GOP MKV 尾部抖动 |
| `video-sync` | `display-resample` | **唯一一处有意偏离 IINA 默认 `audio`**，见下 |
| `audio-pitch-correction` | `yes` | 配合 resample，音高不变 |
| `opengl-swapinterval` / `opengl-pbo` | `1` / `yes` | GL 层由 CA 调度 |

`video-sync=display-resample` 的取舍（同一素材 30 s）：

| 模式 | p50 | p99 | max | >50 ms | CPU（1080p24 HEVC，整机 `%CPU`） |
| --- | --- | --- | --- | --- | --- |
| `audio`（IINA/mpv 默认） | 41.9 ms | 51.0 ms | 51.7 ms | 19 | ~16% |
| `display-resample`（当前默认） | 8.4 ms | 12.3 ms | 17.5 ms | 0 | ~33% |

`audio` 模式下每一两个帧就有一次“晚一个刷新”的抖动，正是“偶尔卡顿”的观感来源；`display-resample` 用音频重采样对齐屏幕时钟，代价是每个刷新都渲染一次（CPU 约翻倍）。需要回退时设置环境变量 `OPENFUSE_VIDEO_SYNC=audio`。

## 6. 验收

新增脚本：

```bash
Scripts/run-player-ui.sh          # 明亮/深色控制栏可见性 + 退出后外观恢复
Scripts/run-player-pipeline.sh    # 60 s 连播：帧间隔、丢帧、控制栏淡出、证据抓帧
Scripts/run-webdav-browser.sh     # 本地 WebDAV 夹具，深路径浏览 + 服务器日志断言
```

单测：`RemotePathTests`（进入幂等、加载中丢弃、旧栈迁移、同名目录）、`PlaybackClockTests`（10 Hz 节流、强制刷新、重置）。`swift test` 共 **69** 项通过。

本机结果：

```
PASS: control bar visible in light and dark themes; appearance restored on exit
PASS: 60 s soak, panel-locked pacing, no post-warm-up frame drops, fade-out no longer stalls video
PASS: WebDAV deep path browsed with a single canonical listing request (/dav/Shows/Season%201/)
PASS: frozen ~9.9 s frames, zh-Hans/zh-Hant selection, 6ch E-AC-3, libmpv output, font-fallback cue, resume from 20 s
```

证据：`build/player-ui/light.png`、`build/player-ui/dark.png`、`build/player-ui/restore.png`、`build/player-pipeline/frame.png`、`build/player-pipeline/player-ui.png`、`build/webdav-browser/breadcrumb.png`。

其它实测过的路径：全屏切换（`--fullscreen`，`isFullScreen=true`、抓帧正常）、暂停 4 s 后显示链路停止再恢复（空格恢复，`position` 继续前进、`paused=false`）、关闭播放器再打开（`--reopen-test`，无崩溃）、`openfuse-probe mpv`（headless 不建 layer）。

## 7. 已知差异与未做

- 只移植播放管线；IINA 的 OSC、缩略图预览、画中画、插件系统没有引入，控制栏仍是 OpenFuse 的 SwiftUI。
- 10bit 像素格式在支持时启用（实测 `depth=16`），HDR 实际亮度/色彩仍未测量。
- 启动阶段 mpv 偶尔记 0–1 次丢帧、3 次 mistimed frame（12 s 与 50 s 读数相同，属解封装/解码预热），稳态为 0。
- `display-resample` 的 CPU 代价见上表；远程高码率片源若出现掉帧，可先用 `OPENFUSE_VIDEO_SYNC=audio` 对照。
- 窗口截图（`--capture-ui`）不包含 CAOpenGLLayer 内容，播放器截图里视频区域仍是黑的；帧证据一律用 `--capture`（读 layer FBO）。

## 8. 回滚

改动分三段：A 控制栏外观、B WebDAV 路径、C 播放管线。C 是独立的一组文件（`MPVController`/`MPVVideoLayer`/`MPVVideoView` + `MPVEngine` 门面），回滚该提交即可恢复旧 `MPVGLView` 路径；A、B 可单独保留。

## 9. 0.5.1 追加：字幕安全区与标题栏

用户反馈的截图里，字幕在控制栏出现时被压在底部黑色渐变下，只露出上半截；播放器窗口的标题栏仍然是明亮模式的白底，与黑色播放器不一致。两处都已修：

### 9.1 字幕随控制栏上移

- 控制栏可见时，`PlayerModel` 把控制栏高度（由 `PlayerChrome` 用 `PreferenceKey` 上报，约 110 pt）换算成画面比例，设置 mpv `sub-pos = 100 − 比例×100`，约 150 ms 分 6 步过渡；控制栏隐藏后回到 100。mpv 默认 `sub-ass-override=scale`，所以 ASS 与外挂 SRT 都适用。
- 纯文本字幕改为 `sub-use-margins=no`，留在画面内，不再被推进底部黑边（也就是控制栏所在的位置）。
- 底部渐变从 240 pt / 0.82 收到 200 pt / 0.72，过渡期间字幕仍然可读。
- 实测（60 s 夹具，字幕在 2.5–6.2 s）：控制栏可见时字幕行 **1162–1207**，隐藏时回到 **1279–1324**；`Scripts/run-player-pipeline.sh` 的帧节拍与淡出停帧不受影响（p99 12.7 ms，淡出 10.3 ms）。

### 9.2 标题栏跟随播放器

上一版用 1×1 的 `NSViewRepresentable` 设置 `window.appearance`，会被场景级 `.preferredColorScheme` 覆盖，标题栏仍是亮色。现在颜色方案按路由决定：

```swift
private var preferredColorScheme: ColorScheme? {
    if case .player = model.route { return .dark }
    return AppTheme(rawValue: appearance)?.colorScheme
}
```

`--report` 里的 `windowAppearance` 在播放器内为 `NSAppearanceNameDarkAqua`，回到首页后恢复（`Scripts/run-player-ui.sh` 的背景 YAVG 154.7 通过）。`PlayerChromeHost` 保留作 AppKit 兜底。

### 9.3 诊断

`OPENFUSE_DEBUG_GL=1` 现在还会打印 view/window/layer 的几何与窗口外观（去重后只在变化时输出），`--report` 增加 `windowAppearance`，便于下次排查“画面被裁”“外观不跟随”这类问题。

## 10. 0.5.2：回退播放核心，修复色彩与字幕

0.5.0 的 Core Animation 播放核心（`MPVController` + `MPVVideoLayer`）在真机片源上暴露了两个严重回归，0.5.2 把**播放核心回退到 0.4.x 的 `MPVEngine` + `NSOpenGLView`**，其余改进保留。

### 10.1 色彩失衡

- 0.5.x 使用 10-bit float 的 `CAOpenGLLayer`（`contentsFormat = .RGBA16Float`）承载画面，却没有给图层声明颜色空间；同时 `target-colorspace-hint` 让 mpv 按 EDR 输出。Core Animation 于是按扩展范围解释这块缓冲区，在 XDR 屏上整幅画面发黄偏绿（用户截图里的肤色和草地）。
- 0.4.x 的 `NSOpenGLView` 是 8-bit RGBA，CA 不会做扩展范围解释，颜色正确。0.5.2 回到该路径，`target-colorspace-hint` 仍是 0.4.x 的“EDR 屏幕才提示”，HDR 由 mpv 色调映射到 SDR。
- 真实片源对照（Big Buck Bunny 1080p 10 s）：播放器帧均值 RGB **93.4 / 102.6 / 57.0**，ffmpeg 解码同一帧 **94.1 / 106.6 / 57.8**（差异来自帧时刻与缩放）。

### 10.2 字幕只显示一部分 / 乱码

- 新播放核心下，纯文本（SRT）字幕经 mpv OSD 渲染时经常整段丢失；`sub-pos` 抬升还会把文本推出画面，表现为“只剩一部分/乱码”。ASS 有时只画出一部分。
- 回退到 0.4.x 的 `NSOpenGLView` + libmpv 渲染后，SRT 与 ASS 都完整显示（黑底 SRT 的亮像素包围盒 904–1460 × 1385–1436；ASS 行 1279–1324），与 0.4.0 的抓帧一致。
- 字幕避让改为**只对纯文本生效**的 `sub-margin-y-offset = 72`（折合 152 px @1520，约 10%），把 SRT 抬到控制栏之上；ASS 保持脚本位置，不会跳动。

### 10.3 保留与放弃

保留：10 Hz `PlaybackClock`、自绘进度条、深色标题栏、CVDisplayLink 的 `display-fps`、WebDAV 路径规范化、Jellyfin 浏览加固、缓存/硬解选项。

放弃：Core Animation 图层与 `MPVVideoLayer`/`MPVVideoView`/`MPVController`（从 0.5.2 起不再编译）。相应地，跟屏渲染（p50 ~8.4 ms）回到 24 fps 输出（p50 41.4 ms、p99 54.2 ms、max 56.8 ms、`frameDropCount=5`/50 s）；控制栏淡出停帧仍是 35 ms（0.4.0 约 100 ms），因为播放头已与 UI 解耦。

回退触发条件：只要 8-bit sRGB 呈现路径能保证颜色与字幕正确，就优先正确性；后续若要重新引入跟屏渲染，必须先补上图层颜色空间声明、并解决纯文本字幕的 OSD 渲染问题，再用真实片源验收。

### 10.4 验证命令与证据

```bash
Scripts/run-player-pipeline.sh   # 60 s：p50 41.4 ms、p99 54.2 ms、淡出 35 ms、无解码丢帧
Scripts/run-player-ui.sh         # 明亮/深色控制栏、退出后外观恢复
Scripts/run-acceptance.sh        # 冻结抓帧、简繁 ASS、6ch、续播
```

真实片源截图：`build/player-fix/window.png`（窗口捕获，含深色标题栏、控制栏、完整中文字幕）、`film.png`（渲染帧，用于颜色对照）、`fixture-ass.png`、`srt-black.png`。窗口捕获用新增的 `--capture-window <path>`（`CGWindowListCreateImage`，可捕获本进程的 OpenGL 视图）。

## 11. 0.5.3：缓冲 HUD 与缓存区间高亮

两个缓存相关的功能，数据口径对齐 IINA 的 `BufferIndicatorView`（`iina/BufferIndicatorView.swift` + `PlayerCore.syncUI(.time)`）。

### 11.1 数据来源

`MPVEngine` 观察以下属性（旧引擎的 `mpv_observe_property` 路径）：

| 属性 | 用途 |
| --- | --- |
| `paused-for-cache` | 是否因等待缓存暂停 |
| `cache-buffering-state` | 缓冲百分比（0–100，仅在 `paused-for-cache` 时有意义） |
| `demuxer-cache-state` | `fw-bytes`（前向缓存字节数）、`raw-input-rate`（下载速度 B/s）、`cache-end`、`seekable-ranges`、`bof-cached` |
| `cache-speed` | 与 `raw-input-rate` 相同，用于打开阶段尽早拿到速度 |
| `demuxer-cache-time` | 缓存时间点（回退值） |

`MPVEngine` 汇总成 `MPVCacheState`，以最多 5 Hz 通过 `onCacheStateChanged` 投递主线程；`PlaybackClock` 再把 `bufferedRanges` 以 5 Hz 发布给进度条，避免缓存事件（每秒几十次）重排 UI。

### 11.2 缓冲/打开 HUD

`PlayerCacheHUD`（SwiftUI，居中）：

- `paused-for-cache` 时：`缓冲中 N%` + `已缓存大小 · 速度`，例如 `125 KB · 29 KB/s`。
- 首次打开（`loadfile` 到首帧之前）：`正在打开…`；一旦拿到速度/字节数也会显示明细。
- 结束或失败时由 `onEndFile(error)` 收起并给出状态提示。

和 IINA 的对应关系：`progressLabel`（`Buffering… %d%%`）→ “缓冲中 N%”；`detailLabel`（`used B (speed B/s)`）→ “已缓存大小 · 速度”；IINA 的网络打开提示 “Opening stream…” → “正在打开…”。

### 11.3 进度条缓存高亮

`PlayerScrubber` 在未播放轨道上按 `clock.bufferedRanges` 画浅蓝区间（`Theme.accent.opacity(0.42)`），已播放段仍是实心强调色。

- 基础数据是 `seekable-ranges`；它只覆盖有索引条目的区间，且可能落后于已下载字节。
- 引擎会把“到达 `cache-end` 的那一段”延伸到 `cache-end`；如果没有区间覆盖 `cache-end`，则按 `bof-cached` 从 0 或从播放头开始补一段。这样本地顺序播放时高亮就是“已下载到哪”，远程流拖动后可以同时显示多段。
- 区间按 `duration` 裁剪，`sub` 与进度条都不会越界。

### 11.4 验收

新增 `Scripts/run-cache-features.sh`：

1. 从夹具生成 faststart H.264 副本（约 5.9 MB / 60 s），由本地 WebDAV 夹具以 **30 KB/s** 限速提供（低于约 90 KB/s 的码率，必然进入 `paused-for-cache`）。
2. 播放 22 s 后抓窗口（`--capture-window`，同时包含视频、控制栏、HUD 与进度条）并写报告。
3. 断言：本地 `bufferedRanges` 非空且末端超过播放头、`cacheUsedBytes>0`；网络侧 `isBuffering=true`、`bufferingPercent>0`、`cacheSpeedBytes>0`、`bufferedRanges` 非空。

本机结果：

```
local:   position 5.7, bufferedRanges [{0, 25.6}], cacheUsed 3.69 MB, speed 160 KB/s
network: position 5.0, isBuffering true, bufferingPercent 89, speed 29.9 KB/s, ranges [{4.54, 6.21}]
PASS: buffering HUD metrics and cached-span highlight verified
```

证据：`build/cache-features/buffering-window.png`（HUD “缓冲中 89% · 125 KB · 29 KB/s” + 进度条上的短缓存段）、`build/cache-features/local-window.png`（0–25.6 s 的长缓存段）。

## 12. 0.5.4：打开响应性、缓冲状态、音量与右键暂停

### 12.1 打开/切换播放器为什么会卡住

复现与证据（本机 macOS 27.2.1，M2 Pro）：

- 延迟首字节 5 s 的 WebDAV 源，点击播放后立即 ⌘Tab 到 Finder 再切回：旧构建在 20 次全屏/窗口循环里出现 4 次 `SIGSEGV`（崩溃报告 `OpenFuse-2026-11-21-012027.ips`、`013750`、`015100`、`020241`）。崩溃线程为 `openfuse.mpv.events` 或主线程，栈顶都是 `MPVEngine.refreshTracks()` ← `runEventLoop` / `handleFileLoaded`。
- 根因有四个，互相叠加：
  1. `MPVEngine.shutdown()` 在主线程 `mpv_terminate_destroy` 并最多等待 2 s；切换/退出时如果旧会话还在打开慢流，主线程被卡住，⌘Tab 回来后窗口无法响应。
  2. `stop()` 先在主线程把 `handle` 置 nil，事件线程同时在读这个 Optional；撕裂的指针会传进 `mpv_get_property_string`，随后在 `refreshTracks` 里以 `EXC_BAD_ACCESS` 崩溃。
  3. `PlayerModel.handleFileLoaded()` 在主线程又调用一次 `engine.refreshTracks()`，与事件线程的 `refreshTracks` 并发写 `tracks` 数组（无锁），堆损坏。
  4. `engine.addSubtitle` 同步调用 `sub-add`，本地 3 条 ASS 的字幕解析/字体初始化在主线程造成约 400 ms 停顿（`MAIN-STALL 405ms`）。
- 另外，SwiftUI 会在切换视频时复用旧的 `NSOpenGLView`，新引擎没有渲染上下文，界面停在全黑；`--switch-to` 测试直接复现为 `hasRenderContext=false`、position=0。

修复：

- `load`/`seek`/`sub-add` 改为 `mpv_command_async`；主线程不再等待 demuxer 或字幕解析。
- `MPVEngine.stop()`：主线程只做 GL 侧拆解（`MPVGLView.prepareForTeardown()` 让上下文 current 后释放 render context），`quit`、等待事件循环、`mpv_terminate_destroy` 全部放到 `openfuse.mpv.events` 队列；`handle` 只在 terminate 之后由事件队列置 nil。
- 事件循环强持有引擎，直到 `SHUTDOWN` 与 terminate 结束；删除 `deinit` 中的 teardown（避免在事件线程碰 AppKit/GL 或复活 self）。
- `tracks` 与 `refreshTracks` 用 `stateLock` 串行化；删除主线程的重复刷新。
- `PlayerView` 的 `MPVSurface` 加 `.id(ObjectIdentifier(engine))`，每个会话独立 GL 视图。
- 所有异步来源打开（WebDAV/Jellyfin/Plex/SMB/本地）带 `sessionGeneration` 令牌；退出、换片或新的打开会作废旧请求，慢 PROPFIND 的结果不能覆盖后选的视频。
- 打开/首帧耗时用 `OPENFUSE_DEBUG_TIMING=1` 打点；主队列心跳超过 250 ms 记录 `MAIN-STALL`。

### 12.2 延迟 5 s 首字节的实测

窗口模式一次典型时间线（`build/player-responsiveness/window-1/timing.log`）：

```
startPlayer.begin        0.0 ms
mpvEngine.init           0.4–120 ms
playback.load.begin      ~220 ms
playback.load.returned   ~220 ms   (异步，立即返回)
playback.fileLoaded      ~5.27 s   (服务器延迟 5 s)
playback.firstFrame      ~5.4 s
```

- 10 次窗口 + 10 次全屏：全部 `front=OpenFuse`、`keys>=1`（空格事件被处理）、`MAIN-STALL` 为 0；全屏个别轮次有一次 255 ms 的首帧着色器编译停顿（< 400 ms），其余为 0。
- 本地 MKV 3 次：0 停顿；冷启动偶发 < 300 ms 的窗口/GL 初始化停顿。
- 打开中切换到本地视频：新会话 `hasRenderContext=true`、duration=60、position>1，主线程停顿 0。
- 打开中按 Esc：回到媒体库，主页截图存在，0 停顿。
- Jellyfin：本机没有服务器且 Docker 不可用，未做实测；它和 WebDAV 共用 `startPlayer`、`stop()` 与会话令牌路径。

### 12.3 缓冲/测速状态机

`MPVEngine` 在 `demuxer-cache-state` / `cache-speed` 事件上置 `hasSpeedSample`（0 也算样本），`PlayerModel` 增加：

- `hasSpeedSample`：无样本 → HUD 明细“测速中…”；有样本且速度为 0 → “0 B/s”；否则按 B/s、KB/s、MB/s 格式化。
- `isNetworkStalled`：网络源、非用户暂停、位置与缓存都 2.5 s 不动 → HUD 标题“连接中断，重试播放”并获得 0 B/s；按播放/空格/右键调用 `reconnect()`，在当前位置重新 `loadfile` 并恢复字幕选择。
- 只有 `item.isRemote` 才显示测速；本地文件只显示“正在打开…”，不显示网络速度。
- 每次换片在 `beginPlaybackIfReady` 重置速度、字节、区间与样本状态。

`Scripts/run-cache-features.sh` 的四个可重复场景（本机结果）：

| 场景 | 结果 |
| --- | --- |
| 首字节延迟 5 s，3 s 截图 | `isOpening=true`、`hasSpeedSample=false`，HUD “正在打开… / 测速中…” |
| 30 KB/s + 中途停 12 s，16 s 截图 | `isBuffering=true`、`speed≈29.9 KB/s`、`bufferedRanges=[{0.67,1.37}]` |
| 播放中杀掉服务器，16 s 报告 | `isNetworkStalled=true`、`cacheSpeedBytes=0`、HUD “连接中断，重试播放 / 0 B/s” |
| 杀掉后重启服务器，按空格重连 | `isNetworkStalled=false`、position 前进、speed≈29.8 KB/s |

### 12.4 音量与右键

- `VolumeMath`（Core）：0–100 夹取、±5 步进、取消静音恢复；`PlayerModel.volume` 写入 `openfuse.player.volume`，新会话在 `loadfile` 前设置 mpv `volume`。
- 控制栏 `VolumeControl`：扬声器按钮 + 64 pt 滑块；HUD 显示 `🔊 85%` 1.2 s。
- 裸 ↑/↓ 在 `PlayerView` 的本地 key monitor 中处理；带 ⌘/⌥/⌃/⇧ 的方向键、文本框、菜单和设置窗口保持原行为。按键重复事件直接处理，所以按住连续调节。
- 右键用 `NSEvent.addLocalMonitorForEvents([.rightMouseDown])`，只在播放器挂载期间安装，返回 `nil` 吞掉事件；覆盖视频、黑边、字幕区、缓冲 HUD、控制栏和全屏；媒体库/文件列表不受影响。
- `userPaused` 记录用户意图：缓冲恢复时 mpv 若自动解除暂停，会立刻重新 `pause`，所以“缓冲期间右键暂停”在恢复后仍保持暂停。

本机验收：`build/player-interactions/`（音量 95、mpv 95、四个区域暂停、两次恢复、缓冲暂停保持）与 `build/player-responsiveness/summary.txt`（10+10 次 ⌘Tab）。

## 13. 0.5.5：进度条 hover 缩略图

### 13.1 结构

- `ThumbnailProvider`（App 目标，`@MainActor`）持有一个独立的 `MPVEngine`，初始化参数 `thumbnailOutput:` 打开图像输出模式：
  `vo=image`、`vo-image-format=png`、`vo-image-outdir=<dir>`、`frames=1`、`vf=scale=320:-2`、`hwdec=no`、`audio=no`、`keep-open=no`、`sub-visibility=no`、`sid=no`。它不创建 GL 渲染上下文，也不使用播放器的 URL/位置。
- 每次请求在 `openfuse.thumbnails` 串行队列上：清空输出目录 → `start=<bucket>` → `loadfile` → `play` → 轮询 PNG（本地 2.5 s、远程 8 s 超时）。播放引擎完全不动，所以预览不会造成 seek、缓冲或音频中断。
- 2 秒一个 bucket（`ThumbnailMath`），最多缓存 80 张；同一 bucket 直接命中。每次新请求递增 `RequestBox` 令牌，旧任务在 load 前/轮询中退出，快速扫过进度条不会堆积。
- `PlayerScrubber` 用 `.onContinuousHover` 取得 x，换算时间并取 bucket；预览 120 ms 防抖，加载中显示进度圈，失败显示“无缩略图”；鼠标移出立即隐藏并取消。预览宽 168 pt（320×180 等比），水平位置由 `ThumbnailMath.previewOrigin` 夹在进度条内，垂直在进度条上方 126 pt。

### 13.2 验收

`Scripts/run-thumbnail-preview.sh`：

| 场景 | 结果 |
| --- | --- |
| 本地 25% + 70% 停留 | `thumbnailCacheCount=2`、`thumbnailLastBytes>5000`、PNG 320×180、position 继续到 6.8 s |
| 光标只在画面 | `thumbnailCacheCount=0` |
| WebDAV 50% | 缓存 1 张、PNG 320×180、position 9.9 s |
| 全屏 60% | 缓存 ≥1、窗口截图存在 |

证据：`build/thumbnail-preview/local/window.png`（00:44 预览）、`webdav/window.png`（00:30 预览）、`thumbs-local/00000001.png`。播放管线 60 s soak 仍为 0 decoder drop、fade 43.5 ms；M1、控制栏、交互、缓存、WebDAV 回归全部通过。

### 13.3 已知边界

- 缩略图只解码视频帧，不烧录字幕；这是预览的预期行为。
- 远程首次预览需要一次 range 请求，慢源可能等待数秒（HUD 显示加载圈）；之后的 ±2 s 桶命中缓存。
- 只有控制栏可见时才能 hover 进度条；鼠标移动会先唤出控制栏。
- 2 秒粒度是速度/精度折中，未做邻近桶预取。

## 14. 0.5.6：IINA 风格窗口管理

参考 IINA 的默认键位（`iina/config/iina-default-input.conf` 与 Window 菜单）：

| 功能 | IINA 默认 | OpenFuse 0.5.6 |
| --- | --- | --- |
| 半屏（0.5×视频） | ⌘0 `set window-scale 0.5` | ⌘0 |
| 正常（1×视频） | ⌘1 `set window-scale 1` | ⌘1 |
| 双倍（2×视频） | ⌘2 `set window-scale 2` | ⌘2 |
| 适合屏幕 | ⌘3 `fit-to-screen` | **⌘4**（⌘3 按用户要求留给全屏） |
| 切换全屏 | ⌃⌘F `cycle fullscreen` | **⌘3**，同时保留 ⌃⌘F（播放器内本地 key monitor） |
| 总在最前 | ⌃⌘T `cycle ontop` | ⌃⌘T |
| 缩小/放大窗口 | ⌘- / ⌘= | ⌘- / ⌘= |
| 退出全屏 | Esc `set fullscreen no` | Esc（全屏时）；窗口模式仍关闭播放器 |

实现：

- `MPVEngine.videoSize()` 读取 mpv `width`/`height`，作为 0.5×/1×/2× 的基准；`WindowScaleMath`（Core）计算目标内容尺寸：保持视频比例、夹在 `screen.visibleFrame`（宽 −60、高 −110）内、最小 320×180；`fit` 用视频比例填满可用区域。
- `AppModel` 新增 `isPlayerFullScreen`、`isAlwaysOnTop`、`windowScaleLastAction/ContentSize`；监听 `NSWindow.didEnterFullScreen/didExitFullScreen` 同步菜单标题；`togglePlayerFullScreen()`、`toggleAlwaysOnTop()`、`applyWindowScale(_:)` 作用于当前播放器窗口。全屏时执行尺寸命令会先退出全屏，动画结束后再应用。
- “窗口”菜单通过 `CommandGroup(after: .windowSize)` 添加，播放器不存在时全部禁用；“总在最前”显示勾选。
- 播放器窗口最小尺寸 320×180（SwiftUI frame + `window.contentMinSize`），关闭播放器恢复 980×620，因此 640×360 视频的半屏 320×180 能真正生效。
- Esc 逻辑保持 0.5.4 行为：全屏退出，窗口模式关闭播放器；`f` 仍可切换全屏。

验收 `Scripts/run-window-management.sh`（640×360 测试片）：

```
initial 1180×760
⌘0 320×208   ⌘1 640×360   ⌘2 1280×720
⌘4 1394×785 (16:9)   ⌘- 1255×707   ⌘= 1381×778
⌘3 → isFullScreen=true, 1512×949
Esc → isFullScreen=false
⌃⌘F → isFullScreen=true
⌃⌘T → alwaysOnTop=true level=3; 再按 → false level=0
```

截图：`build/window-management/fullscreen/window.png`。80 个单元测试（WindowScaleMath 4 个）全部通过；缩略图、交互、控制栏、缓存、播放管线回归通过。

已知边界：未实现 IINA 的画中画（⌃⌘P）与 Music Mode（libmpv 渲染路径）；窗口管理作用于唯一的播放器窗口，不支持多窗口。

## 15. 0.6.0：字幕偏移、同文件夹选集、WebDAV 影视资料

### 15.1 字幕时间偏移

- `SubtitleOffsetText` 负责方向文案与解析：`+1.5 → 延后 1.5 秒`、`-1 → 提前 1 秒`，0 → 同步；`parse` 接受 `1.5`、`+1.5`、`-1`、`1,5`、带数字的短语。
- `SubtitleOffsetStore` 独立存 `subtitle-offsets.json`，键为 `mediaKey|trackID`，不修改 `playback.json`，旧播放记录无需迁移。媒体键是 `MediaFingerprint.resumeKey`，字幕键是轨道稳定 ID（外挂为路径/URL，内嵌为 mpv 轨道 ID）。
- `PlayerModel.selectSubtitle` 设置轨道后立即 `restoreSubtitleDelay`；`setSubtitleDelay` 在 mpv `sub-delay` 上即时生效并写回当前轨道。菜单显示“字幕偏移：延后 1.5 秒”，提供 ±0.1、输入、重置；输入面板同时显示方向说明；修改后 HUD 提示 1.4 s。
- 证据：`Scripts/run-three-features.sh` 用 10.0 s cue 的样片验证 +1.5 → 12.0 s 可见、10.2 s 隐藏、-1.0 → 9.5 s 可见；AoT S03E13 简繁 ASS 分别保存 1.5/2.0，重开与来回切换保持。
- 兼容内嵌/外挂 SRT/ASS：偏移只依赖 `sub-delay` 与稳定轨道 ID；重新打开/拖动不会重置。自动下一集是新 PlayerModel，读取下一集自己的键，无记录默认 0。

### 15.2 同文件夹选集

- `FolderVideoBuilder` 只列当前文件直接父目录：本地枚举一层目录；WebDAV 直接复用 `openRemote(entry:siblings:)` 的 PROPFIND 结果；过滤非视频（字幕/图片/NFO）与子目录；按路径去重。
- `VideoNaming` 解析 `SxxExx`、`1x02`、年份、清晰度与版本标签；`folderTitles` 形如 `S1 · E2 — The Kingsroad`；同集多文件保留两份，并追加 `1080p`/`2160p` 等区分；排序按季、集、标题自然序（E2 < E10）。
- 控制栏按钮打开 `FolderListOverlay`（窗口/全屏同一 SwiftUI 层），当前项勾选并通过 `ScrollViewReader` 定位；点击调用 `AppModel.switchToFolderVideo`：先保存进度，再走现有 `open`/`openRemote`/`openJellyfinItem`；`sessionGeneration` 令牌保证快速连点以最后一次为准；窗口不重建，全屏状态保持。
- WebDAV 从浏览进入或续播时都带 siblings，因此“继续观看”打开也得到同一列表。Jellyfin 若能通过 `libraryEpisodes` 定位同季，则显示“本季剧集”。
- 证据：本地 4 项排序/多版本/勾选、切 E10；WebDAV 切 E10 并保持全屏；播放器列表使用 TMDB 集名/剧照（见 15.3）。

### 15.3 WebDAV 目录影视资料

- `TMDBClient` 新增 `details`（movie/tv + external_ids）与 `season`（整季一次）；`OMDbClient` 通过 IMDb ID 取实际 IMDb/烂番茄/Metacritic；`RemoteMetadataService` 从目录内文件名/父目录/Season 目录推断作品与季，先按年份选候选，再拉详情与整季，按 `sourceID+标题+季` 缓存 24 h（`MetadataCache/*.json`）。
- 目录资料只发送片名/年份/IMDb ID，不发送 WebDAV 地址、路径或凭据。NFO（`tvshow.nfo`/`movie.nfo`/`<video>.nfo`）与 `LibraryOverride` 逐字段优先，TMDB 只补缺失字段。无密钥/断网/失败时 `loadDirectoryMetadata` 返回 nil，浏览、开片、选集不受影响。
- 浏览页头部显示海报、标题、年份、简介、评分与“影片详情/剧集详情”；每集行显示 SxxEyy、集名、本集概要、剧照与清晰度；详情浮层显示整剧/电影资料、评分来源与单集列表（含单集 TMDB 评分，未返回则留空）。
- 播放器选集列表复用同一缓存：`configureFolderVideos` 命中 `directoryMetadataCache` 时立即替换集名/概要/剧照，否则异步拉取后更新；剧照缺图时回退作品海报。
- `SettingsView` 新增 TMDB/OMDb 密钥（Keychain，账号 `tmdb-api-key`/`omdb-api-key`，环境变量优先），保存/验证；`--validate-metadata` 验收路径输出“TMDB 正常；OMDb：IMDb 9.2/10 · 烂番茄 89% · Metacritic 86/100”。
- 证据：`Scripts/run-three-features.sh` 用本地 mock TMDB/OMDb 验证 GoT S1（E1/E2/E10、评分、剧照）、AoT S03E13“地下室”、电影《盗梦空间》，以及无密钥时目录/开片/选集回退；截图见 `build/three-features/{got,aot,movie,offline}`。

## 16. 0.6.1：Jellyfin macOS 网格与详情

见 [JELLYFIN-MACOS.md](JELLYFIN-MACOS.md)。要点：卡片比例按类型固定（库/分集 16:9，电影/剧集 2:3）；窗口内 Hero 详情 + 季集选择；社区/影评人/OMDb 评分与 People；当前 MediaSource 的大小/编码/分辨率/音轨/总码率/23.976 fps 与展开参数；AX 点击与间距命中验收。

## 17. 0.7.0：字幕偏移入口、零配置资料、继续观看与加载页

见 [0.7.0-EXPERIENCE.md](0.7.0-EXPERIENCE.md)。要点：底栏字幕偏移复用顶部操作；WebDAV NFO + TVmaze/Wikipedia/Wikidata 零 key 匹配；首页 4 项继续观看与剧照/帧缩略图；点击后立即加载页、可取消/重试；独立进度同步及其凭据/入口移除。

## 18. 0.8.0：整行字幕菜单、⌘3 最大化、资料语言与缩略图
见 [0.8.0-EXPERIENCE.md](0.8.0-EXPERIENCE.md)。
