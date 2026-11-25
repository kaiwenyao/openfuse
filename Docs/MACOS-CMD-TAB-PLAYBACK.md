# OpenFuse macOS 播放时 Cmd+Tab 卡顿调查与修复方案

调查日期为 2026-11-25，仓库基线为 `ce8ac76`。故障发生在从正在播放视频的 OpenFuse 切到其他应用时。已安装的 0.9.1 和工作区的 0.9.3 都抓到了相同的主线程阻塞路径。首选修复是让 libmpv 的出帧等待离开 AppKit 主线程，同时用屏幕帧、音画同步和字幕验证候选方案。

## 故障表现和复现

1. 在 macOS 打开 OpenFuse，开始播放视频，等待加载完成和画面持续推进。
2. 在 OpenFuse 前台播放时按 `Cmd+Tab`，松开 `Cmd` 切到 Chrome、ChatGPT 或另一个已有普通窗口的应用。切回再重复。从播放器切出的方向是本次报告的主要场景。
3. 用同一个片源、同一组应用和窗口位置做两个对照。先在片源已暂停时切换，再从 OpenFuse 首页切换。记录切换栏何时出现、目标窗口何时显示稳定，以及期间画面是否有明显跳帧。

用户反馈卡顿出现在播放期间，切往哪个应用均可触发。现场日志确认了多次 OpenFuse 与 Chrome 之间的真实 `Cmd+Tab` 切换。用户操作时使用 `/Applications/OpenFuse.app` 0.9.1（168）。可控采样用 `build/OpenFuse.app` 0.9.3（171）、同一个本地 MKV 样片、独立测试数据目录和程序化应用激活。设备为 M2 Pro，系统为 macOS 27.2.1（26B131），使用内建屏幕。

## 采样证据

### 系统快速切换了键盘焦点

对现场日志中 29 次从 OpenFuse 切出的记录，将 WindowServer 发给 Dock 的 `appSwitchFWD` 修饰键状态变化与随后 `SetFrontProcess` 的目标应用配对。两者间隔中位数为 **3 ms**，范围为 **2–10 ms**。对照的 30 次从 Chrome 切出，中位数同为 3 ms，范围为 1–14 ms。这些数字对应系统焦点交接阶段。切换栏首帧、目标窗口实际呈现和动画掉帧需要独立采集。

系统记录了若干窗口排序超时。同类超时曾出现在 OpenFuse 退出后的其他应用切换中，因此应按应用和时间线关联这些记录，暂时把它们作为背景信息。代码中的键盘监听是应用内监听。它处理播放器快捷键，并在命令键分支放行 `Cmd+Tab`。[PlayerView.swift](../Sources/OpenFuseApp/PlayerView.swift#L184)

### 播放时主线程反复等待 libmpv

已安装的 0.9.1 播放采样抓到的主线程栈如下。另一个样本落在同一 `draw(_:)` 的 `NSOpenGLContext.flushBuffer()` 中。

```text
AppKit / Core Animation transaction flush
  _NSOpenGLViewBackingLayer display
    MPVGLView.draw(_:)
      MPVEngine.render(into:)
        mpv_render_context_render
          _pthread_cond_wait
            __psynch_cvwait
```

0.9.3 在同一台机器上以 `sample` 对照。播放与暂停分别取独立进程。暂停样本在报告确认 `paused=true`、`position≈0.917` 且 `hasRenderContext=true` 后才开始。两轮均在采样期间交替激活 Chrome 和 OpenFuse，声音写入临时 PCM 文件。首帧已出现，`video-sync` 为 `audio`。

| 0.9.3 状态 | 主线程样本 | 落在 `MPVGLView.draw(_:)` | 落在 libmpv 条件等待 | 落在 OpenGL 交换缓冲调用 |
| --- | ---: | ---: | ---: | ---: |
| 持续播放 | 935 | 837 | 626（约 67%） | 33 |
| 已确认暂停 | 924 | 0 | 0 | 0 |

样本数代表采样时看到的调用栈频次。约 67% 表示这轮的采样占比，包含睡眠等待。播放组还记录了一次 `MAIN-STALL 255ms`，暂停组没有记录超过心跳阈值的停顿。该心跳按 50 ms 间隔检查并只记录额外延迟超过 250 ms 的事件。现有数据无法把整段 255 ms 归到某个调用。真实快捷键日志与本地受控采样来自不同轮次。[PlaybackTrace.swift](../Sources/OpenFuseApp/PlaybackTrace.swift#L18)

## 相关实现和根因判断

1. libmpv 的更新回调把 `needsDisplay = true` 派发到主队列。AppKit 随后的显示提交调用 `MPVGLView.draw(_:)`。`draw` 同步调用 `engine.render(into:)`，其后执行交换报告、可选截图读回和 `flushBuffer()`。`NSOpenGLContext` 的 `swapInterval` 为 1，交换阶段也可能等待。当前证据中，libmpv 条件等待是主线程最常见的阻塞点。[MPVEngine.swift](../Sources/OpenFuseCore/MPVEngine.swift#L435) · [MPVGLView.swift](../Sources/OpenFuseCore/MPVGLView.swift#L66)
2. 当前默认 `video-sync=audio`。渲染参数没有传 `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME`，因此使用 libmpv 的默认等待行为。SDK 的 `mpv/render.h` 说明，在音频时钟同步下，libmpv 可以提前通知渲染并阻塞到目标呈现时间，等待上限由 `video-timing-offset` 决定。环境中的 mpv 选项默认值为 `0.05` 秒。这个默认值描述单次目标时刻等待的预算，整次窗口切换还经过其他 AppKit 和系统合成步骤。代码同时在 `draw` 和 `CVDisplayLink` 回调里调用 `reportSwap()`，追踪时应区分这两个入口。[MPVEngine.swift](../Sources/OpenFuseCore/MPVEngine.swift#L143) · [MPVEngine.swift](../Sources/OpenFuseCore/MPVEngine.swift#L448) · [MPVGLView.swift](../Sources/OpenFuseCore/MPVGLView.swift#L224)
3. 播放组频繁出现主线程等待，暂停组的采样中为零，系统焦点交接在现场也能迅速完成。最有依据的解释是同步渲染和等待占用了 AppKit 提交画面的时间，使切换期间的窗口显示容易抖动。可见卡顿的改善幅度须用屏幕帧验收。0.5.2 曾为解决 SRT 丢失与 XDR 偏色恢复 `NSOpenGLView`，本次优先从等待时序着手，保留已验证的 8-bit sRGB 呈现和字幕路径。[M7 播放器管线](M7-PLAYER-PIPELINE.md#102-字幕只显示一部分--乱码) · [MPVGLView.swift](../Sources/OpenFuseCore/MPVGLView.swift#L6)

## 修复方案

### 第一阶段 量化渲染等待并做单变量对照

- 给 `mpv_render_context_render`、`reportSwap`、`flushBuffer`、截图读回和整个 `draw` 分别增加诊断计时。用单调时钟和可关闭的 signpost 或低开销聚合记录 p50、p95、p99、最大值以及超出一帧预算的次数。记录应用激活、失活与窗口遮挡变化以配对同一轮采样。常规运行保持低开销，诊断模式优先批量写出，避免每帧同步写磁盘。
- **首选 A/B。** A 组用当前默认设置。B 组在 macOS 交互式 `NSOpenGLView` 播放引擎初始化时，在 `mpv_initialize` 前对有效 `video-sync` 为 `audio` 的引擎设置 `video-timing-offset=0`。从已有的 `headless`、`thumbnailOutput` 和 `video-sync` 选项判定适用范围，保留缩略图、无界面及其他同步模式的现有设置。根据 `mpv/render.h`，这一设置去掉让渲染提前进入阻塞等待的时间，继续由 libmpv 调度出帧。先验证首帧、持续播放、暂停恢复和音画同步，再决定能否作为默认修复。通过同一有声且含同步标记的样片比较 A/V 偏移，使用正常的 Core Audio 输出补测。[MPVEngine.swift](../Sources/OpenFuseCore/MPVEngine.swift#L100)
- **用于定位的替代对照。** 可单独用 `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME=0` 观察等待是否消失。libmpv 对该参数的说明要求同时考虑目标呈现时刻或 `video-timing-offset`，因为单独关闭等待可能改变音画同步。比较时只改一个变量，把交换缓冲、显示链路和 `reportSwap()` 的改动留给独立实验。按分段计时确认是否还存在紧接渲染的 GPU 或系统提交等待。

### 第二阶段 处理第一阶段仍有的可见卡顿

若目标时刻等待下降但视觉卡顿仍能复现，先根据分段计时和屏幕帧定位残余开销。若证据指向应用失活后持续绘制已完全被遮挡的窗口，可按窗口可见性减少冗余提交，切回时呈现最新帧。需要保持后台音频和播放位置持续、部分可见窗口继续出画面，以及窗口恢复时的重绘和截图语义。若试验跳过绘制，按 `mpv/render.h` 确认帧消费和交换报告契约，并覆盖遮挡、最小化、暂停、全屏和多显示器。

若正常可见时的 OpenGL 提交仍产生明显主线程停顿，再评估独立渲染线程与可合成的呈现表面。先确定 AppKit 视图和 drawable 的线程所有权。对同一 libmpv render context 串行化渲染、截图和释放，遵守创建时的 GL 上下文约束，按启动、退出、换集和回调排空验证生命周期。在确定目标帧时间或交换节奏的所有权后再修改 `reportSwap()`。重新采用图层呈现前，以真实 SRT、ASS、SDR、HDR/XDR 片源复测字幕和色彩。[MPVGLView.swift](../Sources/OpenFuseCore/MPVGLView.swift#L161) · [MPVEngine.swift](../Sources/OpenFuseCore/MPVEngine.swift#L210) · [M7 播放器管线](M7-PLAYER-PIPELINE.md#103-保留与放弃)

## 回归验收与交付

以下是修复验收目标。当前报告的实测范围为故障诊断和本地播放、暂停对照。

| 验收项 | 做法和完成条件 |
| --- | --- |
| 可见切换 | 在同一机器、显示器、片源、窗口布局上比较改前改后。普通窗口和原生全屏各做至少 20 次实体 `Cmd+Tab` 切出、切回。播放组与暂停、首页对照分别记录。通过高帧率录制或系统呈现指标观察切换栏首帧、目标窗口稳定显示时间及长帧，比较 p95 和最差轮次。现场稳定复现的停顿应消失或显著减少。记录录制帧率和可能的采集开销。 |
| 主线程 | 两版在同一条件下各跑多轮采样，报告 libmpv 等待栈占比和各阶段耗时。如果采用首选方案，目标时刻等待栈应消失或大幅减少。观察是否有新增的长尾停顿，以及时间是否转移到交换缓冲或 AppKit 提交。 |
| 播放连续性 | 切出再切回后，播放位置继续推进，音频连续，画面、字幕和音频正常。检查首帧、暂停、继续、跳转、变速、换集、快速返回、关闭及媒体重复打开。比较相同片源和播放区间的掉帧增量及对齐情况。本地外，还应覆盖一个已有的远程样片或 WebDAV 测试。 |
| 画面与同步 | 验证外挂 SRT、ASS、代表性的 SDR 和 HDR 片段及播放器截图。用带同步标记的样片核对首帧后、持续播放以及切回后的音画关系。记录画面差异、A/V 偏移和 dropped frame 增量。 |
| 现有回归 | 跑 `swift test`、macOS 构建，以及播放器交互、换集暂停、打开期间响应性、窗口管理和适用的字幕/HDR 验收。现有响应性脚本用应用激活来模拟切换，提供打开和操作回归所需的覆盖，真实按键与屏幕帧单独验收。 |

已有入口为 [run-player-responsiveness.sh](../Scripts/run-player-responsiveness.sh) · [run-player-interactions.sh](../Scripts/run-player-interactions.sh) · [run-episode-switch-pause.sh](../Scripts/run-episode-switch-pause.sh) · [run-window-management.sh](../Scripts/run-window-management.sh) · [run-hdr-playback.sh](../Scripts/run-hdr-playback.sh)。个别 UI 脚本依赖本机辅助功能、输入自动化或屏幕录制能力。执行前查看脚本对前台窗口和应用配置的影响。交付时记录已验证的入口、片源、版本、A/B 指标及受环境限制的检查。

## 本地采样命令

在仓库根目录运行。构建 `build/OpenFuse.app` 并准备 `Fixtures/generated/openfuse-fixture.mkv`，结束其他 OpenFuse 实例后开始测试。可以手动切换应用，同时采样播放器主线程。`play` 保持播放，`pause` 在播放位置达到 0.5 秒后自动暂停。先等测试报告落盘，确认 `hasRenderContext` 和 `paused` 后再采样。示例将音频写到临时 PCM 文件，正式音画验证使用正常音频输出。

```bash
app="$PWD/build/OpenFuse.app/Contents/MacOS/OpenFuse"
fixture="$PWD/Fixtures/generated/openfuse-fixture.mkv"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/openfuse-cmdtab.XXXXXX")"

for mode in play pause; do
  run_dir="$test_dir/$mode"
  mkdir -p "$run_dir/support"
  run_args=()
  if [ "$mode" = pause ]; then run_args=(--freeze-at 0.5); fi

  OPENFUSE_SUPPORT_DIR="$run_dir/support" \
  OPENFUSE_CREDENTIAL_MODE=session \
  OPENFUSE_DEBUG_TIMING=1 \
  OPENFUSE_AO_PCM="$run_dir/fixture.wav" \
    "$app" --open "$fixture" "${run_args[@]}" \
    --report "$run_dir/report.json" --capture-after 3 --quit-after 20 \
    >"$run_dir/stdout.log" 2>"$run_dir/timing.log" &
  app_pid=$!

  for attempt in $(seq 1 24); do
    if [ -s "$run_dir/report.json" ]; then break; fi
    sleep 0.25
  done
  if [ -s "$run_dir/report.json" ]; then
    python3 - "$run_dir/report.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    report = json.load(file)
print({key: report.get(key) for key in ('paused', 'position', 'hasRenderContext', 'videoSync')})
PY
    printf '在 %s 状态下切出和切回 OpenFuse\n' "$mode"
    sample "$app_pid" 5 3 -file "$run_dir/sample.txt"
  fi
  wait "$app_pid"
done
printf '%s\n' "$test_dir"
```

查看 `sample.txt` 的主线程调用树，分别统计 `MPVGLView.draw(_:)`、`mpv_render_context_render` 的等待分支和 `CGLFlushDrawable`。用相邻周期的 `timing.log` 核对首帧与主线程心跳。复查现场快捷键路由时，可以查询 WindowServer 的 `appSwitchFWD` 和 `SetFrontProcess` 日志，按时间配对释放与目标焦点。用屏幕帧记录补齐目标窗口实际呈现的数据。

修复任务可直接复制 [Agent 提示词](MACOS-CMD-TAB-FIX-PROMPT.md)。

修复实现、A/B 实测数据与回归结果见 [MACOS-CMD-TAB-FIX.md](MACOS-CMD-TAB-FIX.md)。
