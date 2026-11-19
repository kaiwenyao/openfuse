# M1 验收记录：Mac 本地播放

日期：2026-11-19。分支：`m1-local-playback`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮交付一个能在 Mac 上启动、打开 MKV、实际出画面/出声、切外挂字幕、拖动、退出并续播的 OpenFuse 构建，以及可复现的构建与测试命令。

## 构建与启动

```bash
cd ~/Documents/openfuse   # 或你的仓库路径
brew install mpv                       # 提供 libmpv 0.42.0；ffmpeg 用于生成测试片
Scripts/make_fixtures.sh               # 生成 60 s 夹具（首次约 2–3 分钟）
Scripts/build-app.sh                   # 输出 build/OpenFuse.app
open build/OpenFuse.app                 # 首页
```

带文件启动与自动取证：

```bash
build/OpenFuse.app/Contents/MacOS/OpenFuse \
  --open "$PWD/Fixtures/generated/openfuse-fixture.mkv" \
  --subtitle zh-Hant --freeze-at 9.9 \
  --capture /tmp/frame.png --capture-after 12 \
  --capture-ui /tmp/ui.png --ui-after 11 \
  --report /tmp/report.json --quit-after 14
```

参数：`--seek`、`--subtitle <tag>`、`--freeze-at`、`--capture`（渲染帧）、`--capture-ui`（窗口）、`--report`、`--reopen-test`、`--fullscreen`、`--quit-after`。`OPENFUSE_SUPPORT_DIR` 可把播放记录隔离到临时目录，`OPENFUSE_MPV_LOG=v` 打开 mpv 日志。

## 一键复现

```bash
Scripts/run-acceptance.sh
# PASS: frozen ~9.9 s frames, zh-Hans/zh-Hant selection, 6ch E-AC-3, libmpv output,
#       font-fallback cue, resume from 20 s
```

脚本会生成素材（若缺失）、构建、跑单元测试，然后依次抓简体、繁体、缺字体帧与一次续播；断言位置、选中轨、输入 6 声道、输出路径和渲染帧存在，产物在 `build/acceptance/`。

## 已通过

| 用例 | 操作 | 结果 | 证据 |
| --- | --- | --- | --- |
| 打开与播放 | 系统文件选择器/`--open` 打开 60 s MKV | 出画面，VideoToolbox 硬解（`hwdec-current=videotoolbox`），时长 60.000 s | `Evidence/03-hevc-main10-frame.jpg` |
| 画面时间码 | 抓取应用真实渲染帧 | 帧内 00:00:13:11 / t=13.458 s，同次报告 `position=13.458` | 同上 |
| 音轨 | E-AC-3 5.1 单音轨 | 输入 48 kHz 6ch 5.1(side)，CoreAudio 输出 2ch stereo（MacBook Pro 扬声器）；文件级 24/24 声道报号检测通过 | `reports/m1-zh-hans.json` 的 `audioParams`/`audioOutParams`；`reports/audio-channel-map.json` |
| 外挂字幕发现 | 同目录三份 ASS | 菜单列出「中文（简体）(ASS)」「中文（繁體）(ASS)」「未知语言 (ASS)」与内嵌轨 | 播放器截图 |
| 简繁切换 | `--subtitle zh-Hans` / `zh-Hant`，冻结在 9.917 s | 同一帧出现不同字形：「测试/測試」「显示/顯示」「字体/字型」 | `Evidence/04-subtitle-zh-hans.jpg`、`05-subtitle-zh-hant.jpg` |
| 字体回退 | NOTE 样式指定未安装字体，冻结在 4.417 s | 中文与英文均正常显示，未出现方框 | `Evidence/06-subtitle-font-fallback.jpg` |
| 拖动与字幕同步 | 打开后 seek 到 7.2 s，再在 9.9 s 冻结 | 字幕为 8.0–11.5 s 的第二句，画面 9.917 s，一致 | 04/05 图 |
| 退出续播 | 播放到 23.04 s 退出 | `playback.json` 保存 25.000 s（退出时实时位置）；再次打开从 25.0 继续，4 s 后报告 28.458 s；字幕/音轨偏好保留 | `reports/m1-resume-before.json`、`m1-resume-after.json`、`playback-store.json` |
| 关闭再打开（同进程） | `--reopen-test`：4 s 关闭播放器，5.5 s 重新打开 | 新会话从上次位置继续，渲染上下文重建成功，无崩溃 | `/tmp/run-cycle2.log`（本地运行记录） |
| 全屏 | 启动 3 s 后进入全屏 | 窗口 `isFullScreen=true`，尺寸 1512×949，硬解仍为 videotoolbox | `reports/m1-zh-hans.json` 同结构报告 |
| 窗口尺寸记忆 | `setFrameAutosaveName` | 重开应用保留上次窗口尺寸/位置 | 代码与实机重启 |
| 单元测试 | `swift test` | 8 个测试全部通过（字幕发现/语言标签/续播策略/替换文件保持进度） | 终端输出 |

## 证据说明

- `Evidence/01-home-continue-watching.jpg`：首页「继续观看」卡片，显示 00:25 / 01:00 与进度条。
- `Evidence/02-player-controls.jpg`：播放器控制层。窗口快照无法包含 `NSOpenGLView` 的图层，视频区域为黑色属于截图方式限制；真实画面见 03–06 的渲染帧。
- `03`–`06`：由播放器在绘制后直接 `glReadPixels` 抓取，是应用实际输出，而不是从文件另抽的静帧。
- `reports/*.json`：同一轮运行的状态报告，已把绝对路径替换为仓库相对路径。

## 与参照的已知差异 / 未验证

1. **Infuse 对照缺失**：本机没有 Infuse 8.5.10，首页、详情、控制层的坐标/字号/动画尚未按参照测量；当前 UI 是自有设计，不宣称像素一致。
2. **听感**：只能确认解码、声道映射、输出路由与下混参数；Mac 扬声器与 5.1 接收器上的人耳听测待人工完成。
3. **字幕自动选轨**：当前规则为「保存的选择 → zh-Hans 外挂 → 任意中文 → 内嵌」，尚未与 Infuse 的默认语言策略逐项对照。
4. **字幕菜单文案**：外挂轨显示「中文（简体）(ASS)」，内嵌轨显示服务器/文件标题；Infuse 的具体格式待采样。
5. **性能**：尚未做 20 次冷/热缓存首帧、拖动 P95；仅记录单次打开与定位结果。
6. **窗口快照**：macOS 27 的 `CGWindowListCreateImage` 已移除，窗口级截图只能由应用自身 `cacheDisplay` 完成，OpenGL 层不进图；渲染帧另测。
7. **打包**：`build/OpenFuse.app` 依赖 `/opt/homebrew` 的 libmpv 与 FFmpeg，未做自包含打包；GPL/LGPL 与签名留到发行阶段。
8. **播放会话释放**：同进程关闭/重开验证过一次，未做 100 次循环与内存/句柄峰值统计。
9. **其他平台**：iOS/iPadOS/tvOS/visionOS 尚未开始。
10. **未接入**：WebDAV/OpenList、Jellyfin、海报库、搜索、设置、播放列表、AirPlay/PiP。

## 下一项

进入 M2：先做 WebDAV/OpenList 的列目录、Range 读取、外挂字幕发现与播放中拖动，再做 Jellyfin Direct/Library 与进度回写。M2 分支从 `m1-local-playback` 拉出。
