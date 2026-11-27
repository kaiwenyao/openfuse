# OpenFuse macOS 播放时 Cmd+Tab 卡顿修复

问题现象与原因见 [BUG-REVIEW-2026-11-27.md](BUG-REVIEW-2026-11-27.md) 第 5 条。本文件记录实现、实测数据、
回归结果和仍未覆盖的分支。

工作区：从 `ce8ac76` 新建 worktree `openfuse-cmdtab-fix` / 分支 `fix/macos-cmd-tab`，提交前 rebase 到 `origin/main` 的 `5f02d75`（0.9.4）；主工作区里未提交的移动端/WebDAV 改动保持不动。

基线：`5f02d75`（0.9.4）+ 本 worktree（`fix/macos-cmd-tab`），本机 M2 Pro / macOS 27.2.1 /
内建屏 1512×982，片源 `Fixtures/generated/openfuse-fixture.mkv`（1920×1080、24 fps、
HEVC Main 10、E-AC-3 5.1、60 s、内嵌 ASS + 外挂 zh-Hans/zh-Hant/双语 ASS）。

## 结论

在 macOS 交互式 `NSOpenGLView` 播放引擎上，`video-sync=audio` 时把
`video-timing-offset` 从 mpv 默认的 `0.05` 改为 `0`：

- 播放帧的 `mpv_render_context_render` 主线程阻塞从 p50 **34.6–36.5 ms** 降到
  **3.1–3.6 ms**；整次 `draw(_:)` p50 从 **36.6–38.5 ms** 降到 **5.2–6.2 ms**。
- 超过 16.7 ms 帧预算的绘制从 **95–96%（窗口 410/431、全屏 549/574）** 降到
  **3.8–5.1%（22/432、22/574）**。
- 主线程采样中落在 `MPVGLView.draw(_:)` 的样本从 **94%** 降到 **13%**；
  `mpv_render_context_render → _pthread_cond_wait` 的等待样本从
  2181/2642（83%）降到 0。
- 音画同步没有变差：报告里的 `avsync` 从 51–61 ms 变为 2–11 ms；
  `frame-drop-count` 每次运行 2–3 次，与改前相同。
- 暂停组同样消除了等待（render p50 32.8/33.5 ms → 1.8/1.6 ms），说明等待只
  取决于当前是否走同步渲染，而不是视频是否在解码。

`MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME=0` 的定位对照（C 组）也能去掉等待，
但它保留 50 ms 的提前出帧，`avsync` 反而升到 44–65 ms，并让帧在目标时刻前就交换。
因此选 `video-timing-offset=0`，不采用 C 作为默认。

## 机制与选型

1. `MPVEngine` 默认 `video-sync=audio`。libmpv 会提前 `video-timing-offset` 把帧
   交给 render API，`mpv_render_context_render()` 再阻塞到目标呈现时刻
   （`mpv/render.h` 中 `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME` 的说明）。
2. OpenFuse 在 `MPVGLView.draw(_:)` 里同步调用该接口，所以这段等待落在 AppKit
   主线程上。0.9.1/0.9.3 的采样栈
   `CA::Transaction::flush → -[_NSOpenGLViewBackingLayer display] →
   MPVGLView.draw → MPVEngine.render → mpv_render_context_render →
   _pthread_cond_wait` 就是这条路径。
3. `video-timing-offset=0` 让 VO 在目标时刻才把帧交给 render API（实测
   `target_time - now` 从 +30 ms 变为 −5 ms），主线程不再等待；libmpv 仍按音频
   时钟调度，交换仍发生在 vsync。代价是失去 50 ms 的提前量，实测
   `avsync` 与 dropped frame 都未变差。
4. 只对交互式引擎生效：`headless`（`vo=null`）和缩略图引擎（`vo=image`，
   `thumbnailOutput != nil`）以及非 `audio` 的同步模式（`display-resample` 等）
   保持原设置，见 `MPVVideoTimingPolicy`。

### 实现

| 文件 | 改动 |
| --- | --- |
| `Sources/OpenFuseCore/VideoTimingPolicy.swift` | 新增。按 `video-sync` / `headless` / `thumbnailOutput` 决定是否设置 `video-timing-offset`；`OPENFUSE_VIDEO_TIMING_OFFSET` 可在同一构建里切 A/B；`OPENFUSE_BLOCK_FOR_TARGET_TIME=0` 开启 C 组定位对照。 |
| `Sources/OpenFuseCore/RenderTiming.swift` | 新增。可关闭的分段计时：`draw`、`render`、`swap`（`flushBuffer`）、`capture`（截图读回）、`reportSwap`、`targetLead`（`target_time - now`）。每段保留有界环形样本，计算 p50/p95/p99/max/超帧预算次数；后台定时批量写 `timing.log`，不逐帧落盘；应用激活/失活与窗口遮挡事件按时间戳写入同一日志。 |
| `Sources/OpenFuseCore/MPVEngine.swift` | 在 `mpv_initialize` 前应用策略；`render()` 内计时并读取 `MPV_RENDER_PARAM_NEXT_FRAME_INFO` 记录 `targetLead`；C 组时传 `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME=0`；`renderStats` 增加 `videoTimingOffset`、`blockForTargetTime`、`avsync`、`displaySyncActive`、`voDelayedFrameCount` 与完整 `renderTiming` 摘要。 |
| `Sources/OpenFuseCore/MPVGLView.swift` | `draw` 内分段计时；观察 `NSWindow.didChangeOcclusionStateNotification` 与 `NSApplication` 激活通知；卸载时写最终分段摘要。 |
| `Sources/OpenFuseApp/AppModel.swift` | 验收报告增加 `appActive`、`windowOccluded`，并合并引擎的渲染统计。 |
| `Sources/OpenFuseApp/HomeView.swift` | `applicationWillTerminate` 写最终 `render-final`。验收用的 `--report-on-quit` 在销毁播放器前保存切回后的播放报告。 |
| `Tests/OpenFuseCoreTests/VideoTimingPolicyTests.swift` | 策略覆盖：交互式 audio 返回 `0`、环境覆盖、空值保留 mpv 默认、headless/缩略图/其他同步模式不受影响、C 组开关。 |
| `Tests/OpenFuseCoreTests/RenderTimingTests.swift` | 百分位、超预算计数、禁用时零开销、环形容量、事件摘要、`target_time` 的 ns→ms 换算（mpv 0.42 的 `vo_frame.pts` 是 ns，而 `render.h` 文字写的是 µs，代码按实测基准确认并单测）。 |
| `Tools/window_focus.swift` | 按 PID 查询和激活前台进程，并在切换循环结束后请求测试实例正常退出。 |
| `Scripts/run-cmdtab-timing.sh` | 用 A/B/C 对照播放和暂停，可选普通窗口或全屏。分别记录 `Cmd+Tab`、Finder 回退、失败切出和失败切回，汇总切换前后的进度、`avsync`、掉帧增量和分段耗时。 |

诊断开关（默认全关，常规运行只有一次布尔判断）：

```
OPENFUSE_RENDER_TIMING=1            # 或沿用 OPENFUSE_DEBUG_TIMING=1
OPENFUSE_RENDER_TIMING_INTERVAL=5   # 秒；0 只保留最终摘要
OPENFUSE_FRAME_BUDGET_MS=16.7       # 超预算阈值，默认 1000/60
OPENFUSE_VIDEO_TIMING_OFFSET=0.05   # A 组：改前行为
OPENFUSE_VIDEO_TIMING_OFFSET=0      # B 组 / 默认修复
OPENFUSE_BLOCK_FOR_TARGET_TIME=0    # C 组定位对照
```

## 改前改后数据

### 逐帧分段耗时（`render-final`，每组 2 次运行、每次 12 次 Cmd+Tab 切换）

窗口（普通窗口）播放组：

| 方案 | draw p50 | draw p95 | render p50 | render p95 | >16.7 ms 的 draw | avsync | targetLead p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A `video-timing-offset=0.05` | 38.5 ms | 51.1 ms | 36.5 ms | 43.5 ms | 410/431（95%） | 54 ms | +33.0 ms |
| B `video-timing-offset=0`（采用） | 6.2 ms | 16.6 ms | 3.6 ms | 10.1 ms | 22/432（5.1%） | 5 ms | −5.1–−5.2 ms |
| C `BLOCK_FOR_TARGET_TIME=0`（仅对照） | 6.1 ms | 18.1 ms | 3.6 ms | 10.6 ms | 28/436（6.4%） | 55–65 ms | +36.6 ms |

原生全屏播放组：

| 方案 | draw p50 | draw p95 | render p50 | render p95 | >16.7 ms 的 draw | avsync |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A | 36.6 ms | 48.5 ms | 34.6 ms | 42.5 ms | 549/574（96%） | 51–61 ms |
| B | 5.2 ms | 13.8 ms | 3.1 ms | 6.8 ms | 22/574（3.8%） | 2–11 ms |

暂停组（每次运行 12 次切出）：A 的 `render` p50 为 32.8 ms（窗口）/33.5 ms
（全屏），B 为 1.8/1.6 ms；`draw` p50 从 35.8/35.7 ms 降到 4.7/4.6 ms。
暂停组 p95 受一次性截图读回影响（约 167 ms），不作为播放路径指标。

其他计数（播放组，A → B）：`frame-drop-count` 每次 1–3 次，
`vo-delayed-frame-count` 都是 0，`mistimed-frame-count` 两次都未由 mpv 提供，
`swap`（`flushBuffer`）p95 中位数 10.4–11.4 ms → 7.5–9.2 ms，没有向交换阶段
转移长尾。
上述历史播放组由 System Events 发送 `Cmd+Tab`。复核各轮对应的 WindowServer
`appSwitchFWD` 记录，每轮实际切出 12 次，普通窗口和全屏各 2 轮，共 24 次/方案。

`MAIN-STALL` 心跳在每组都记录到一次约 260–380 ms 的冷启动停顿（约启动后
0.27 s，首次 GL/首帧）以及 A 全屏组一次全屏切换约 280 ms 的停顿；B 组切换
期间没有新增停顿。

### 主线程采样（稳定播放、无切换，`sample 5 1`）

| 方案 | 主线程样本 | 落在 `MPVGLView.draw` | 落在 `mpv_render_context_render → _pthread_cond_wait` |
| --- | ---: | ---: | ---: |
| A | 2642 | 2481（94%） | 2181（83%） |
| B | 2792 | 358（13%） | 0 |

这与 0.9.3 调查中的 626/935（67%）方向一致；本次计数含更长的稳定播放窗口，
因此占比更高。

### 音频与画面

- 自动运行把音频写到 PCM（`OPENFUSE_AO_PCM`）：窗口组 WAV 18.0–18.1 s、全屏组
  24.0 s，与应用存活时间一致；`ffmpeg silencedetect` 在 −45 dB、0.5 s 阈值下
  没有报告任何静音段，说明切出、切回期间音频连续。
- `avsync` 在报告时刻 A 为 51–61 ms，B 为 2–11 ms；不设任何环境变量的默认构建
  （`currentAO=coreaudio`、普通音频设备）报告 `videoTimingOffset=0`、
  `avsync≈1–5 ms`、`render p50≈3 ms`，无 `MAIN-STALL`。
- 真实图像回归（应用内 FBO 截图）：默认外挂 ASS（含日文、缺字体中文回退、
  繁体）与 `--select-subtitle SRT` 的普通文本外挂 SRT 均出现在画面底部，
  字体、颜色和位置正常；`Scripts/run-hdr-playback.sh` 通过
  （bt.2020 / pq / spline / sig-peak / 截图存在）。

## 复现与验证命令

```bash
# 构建
Scripts/build-app.sh

# 窗口组 A/B/C：播放/暂停 × 2 轮 × 12 次 Cmd+Tab 切换
ROUNDS=2 SWITCHES=12 Scripts/run-cmdtab-timing.sh

# 原生全屏组
FULLSCREEN=1 VARIANTS="A B" ROUNDS=2 SWITCHES=12 Scripts/run-cmdtab-timing.sh

# 单项验证（同一构建切 A/B）
OPENFUSE_VIDEO_TIMING_OFFSET=0.05 OPENFUSE_DEBUG_TIMING=1 \
  OPENFUSE_RENDER_TIMING_INTERVAL=1 OPENFUSE_AO_PCM=/tmp/a.wav \
  build/OpenFuse.app/Contents/MacOS/OpenFuse \
  --open Fixtures/generated/openfuse-fixture.mkv \
  --report /tmp/a.json --capture-after 3 --quit-after 9
OPENFUSE_VIDEO_TIMING_OFFSET=0 ...   # 同上，B 组

# 稳定播放主线程采样
sample <pid> 5 1 -file /tmp/sample.txt

# SRT 视觉回归用的外挂字幕（放在片源同目录，目录扫描会收录）
cat > Fixtures/generated/openfuse-fixture.srt <<'SRT'
1
00:00:01,000 --> 00:00:10,000
SRT 字幕验证：普通文本外挂字幕应显示在画面底部

2
00:00:10,500 --> 00:00:20,000
SRT 字幕第二句：切出再切回后仍然可见
SRT
```

每次执行 `Scripts/run-cmdtab-timing.sh` 都在 `build/cmdtab-timing/` 下创建独立的
`run.*` 目录。`summary.md` 和 `summary.tsv` 只汇总本次运行。每组保留
`report-before.json`、`report-after.json`、`timing.log`、`sample.txt`、`switches.tsv`、`switches.log`、
`frame.png` 和 `fixture.wav`。前后报告的 `position` 和 `avsync` 均以秒为单位。
任一组缺少必要报告或采样、出现 Finder 回退，或未完成指定的 `Cmd+Tab` 切出和切回时，脚本返回失败。

## 回归

- `swift test`：160 个测试通过（含新增 15 个策略/计时/换算测试）。
- macOS release 构建：`Scripts/build-app.sh` 通过，产物
  `build/OpenFuse.app`（0.9.4，构建号 176）。
- `Scripts/run-hdr-playback.sh`：PASS（HDR10 bt.2020/pq、spline tone mapping）。
- `Scripts/run-episode-switch-pause.sh`：PASS（空格、右键、↓ 音量在换集后
  仍作用于新引擎）。
- `Scripts/run-player-interactions.sh`：音量、视频/黑边/控制条右键、两次右键恢复、
  缓冲中暂停恢复均通过；全屏右键该项在脚本的 System Events 焦点/几何回退下失败
  （报告 `isFullScreen=true` 但点击未到达播放器）。用 `Tools/window_focus.swift`
  按 pid 聚焦后手动重跑同一场景，`paused=true`、`userPaused=true`。
- `Scripts/run-player-responsiveness.sh`：PASS。5 s 延迟打开期间窗口组和原生全屏
  各 10 次 `⌘Tab`、空格暂停、打开中切换和关闭都通过，最大主队列停顿 0–278 ms
  （冷启动 GL 一次）。
- 播放连续性：历史运行的退出时播放记录显示进度继续推进，`fixture.wav` 无静音段。
  更新后的脚本直接从前后报告对照进度、音画同步和掉帧增量。首帧、暂停/恢复、
  跳转、变速、换集与关闭由相关回归脚本覆盖。
- SRT / ASS / SDR / 截图：见上。

审核修正后重跑 `swift test`，160 项通过。ThreadSanitizer 对先前会触发竞争的
两线程测试完成 40,000 次 `flushWindow()`。验收脚本的模拟测试覆盖成功、Finder
回退、采样缺失、暂停组缺失和提前生成退出报告。普通窗口和全屏对照都生成了
切换前后报告，播放组位置继续推进，暂停组位置不变。当前会话中 System Events
拒绝 `osascript` 发送按键（1002），实测切换均计为 Finder 回退，脚本按预期返回失败。
自动快捷键路径的依据是上文已经由 WindowServer 日志复核的历史数据。

仍待验证：

- **屏幕呈现帧**：本环境没有 ScreenCaptureKit 录制通道，`screencapture`
  也没有屏幕录制授权，因此切换栏首帧、目标窗口稳定时间和动画长帧没有像素级
  数据。已完成的是应用内逐帧分段计时、主线程采样和系统切换次数；
  屏幕动画需在允许屏幕录制的机器上按调查文档的“可见切换”项复测。
- **正常 Core Audio 输出**：默认构建已走 `coreaudio` 且报告 `avsync≈1–5 ms`；
  自动化和本次会话无法确认实际扬声器听感，主观听感仍需在有声环境复核
  （本次未改 `ao` 选择）。
- 多显示器、XDR 外接屏、超长时长 soak，以及 `display-resample` 等非默认
  同步模式下的行为保持原实现，未在本次变更范围内。
