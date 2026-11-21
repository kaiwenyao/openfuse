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
