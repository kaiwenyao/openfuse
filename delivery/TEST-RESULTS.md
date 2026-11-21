# OpenFuse 0.9.2 · macOS 界面修复交付与验收

基线：`0.9.1`（`04b0160`）。本轮在同一台 Mac 上实现、构建、启动应用并完成真实交互验收。

- 机器：MacBook（arm64），macOS 27.2.1（26B131），Xcode 27.2，屏幕 1512 × 982 pt
- 应用：`build/OpenFuse.app`，版本 `0.9.2`
- 安装包：`delivery/OpenFuse-macos.zip`、`delivery/OpenFuse-macos.zip.sha256`、`delivery/install-openfuse-macos.sh`
- 安装命令：

```bash
cd /Users/ykw/Documents/openfuse/delivery
bash install-openfuse-macos.sh --app OpenFuse-macos.zip
```

离线安装会校验 SHA-256、用本机持久签名身份重签并安装到 `/Applications`，同时备份旧版本，重复执行即为升级。

## 1. 交付内容

### 截图（`delivery/screenshots/`）

| 文件 | 内容 |
| --- | --- |
| `00-before-player-0.9.1.png` | 改动前 0.9.1 播放器：980 pt 宽底栏、205 pt 固定容器、上下大面积黑渐变，标题显示完整文件名并遮挡字幕 |
| `01-player-normal.png` | 0.9.2 普通窗口：顶部居中 560 × 94 pt 悬浮面板，两行布局，字幕区不被遮挡 |
| `02-player-320.png` | 320 pt 小窗：面板收缩至 304 pt，保留播放、时间轴和字幕入口 |
| `03-player-fullscreen.png` | 原生全屏：面板仍在顶部中央（1512 pt 宽容器内原点 476, 64） |
| `04-player-hidden.png` | 播放中空闲自动淡出：面板和标题条均隐藏，画面与字幕完整 |
| `05-player-subtitle-menu.png` | 字幕弹层：整行选轨、当前轨勾选、悬停高亮、字幕偏移与输入入口 |
| `06-webdav-grid.png` | WebDAV 网格：`100% 测试`、`Attack on Titan (2013)`、`Death Note (2006)`、`Fargo (2014)`、`Show 100%25`、`中文 剧集 (2020)` |
| `07-webdav-list.png` | 同一目录的列表视图，文件夹标题规则与网格一致 |
| `08-webdav-fargo-season-card.png` | 点击 Fargo 后：面包屑增加 `Fargo (2014)`，卡片只显示 `Season 01` |
| `09-webdav-season-page.png` | 进入 `Season 01` 后的单季页，当前选集路径保留完整 `entry.path` |
| `10-player-drag-hover.png` | 面板拖到画面中部后悬停时间轴：缩略图向**上**展开 |
| `11-player-reduce-transparency.png` | 系统「减少透明度」开启时，面板切换为不透明深色表面 |
| `12-player-return-season.png` | 从播放器退出后回到原季 `Season 01`，`当前选集` 仍为 S01E01 |
| `13-playback-info.png` | 「播放信息」：完整文件名、来源、AirPlay、音轨、字幕、速度、时长、视频/音频编码、分辨率、缓存和会话日志 |

### 录屏（`delivery/recording/panel-interaction.mp4`）

8 fps，18.9 秒，H.264。连续展示：

1. 按住面板顶部空白拖动条，把面板从顶部拖到画面中部；
2. 鼠标移到时间轴上，缩略图预览随面板位置改为向上展开；
3. 打开字幕菜单（弹层在面板下方），字幕偏移从「同步（0 秒）」变为「延后 0.1 秒」，底部出现偏移提示；
4. 字幕弹层关闭后鼠标移开，面板在空闲后淡出，视频与双语 ASS 字幕继续正常显示。

### 测试证据（`delivery/evidence/`）

每个 `*report.json` 都是应用自己写出的运行报告，包含 `headingTitle`、`showControls`、`chromeHolds`、`panelOrigin`、`panelSize`、`panelContainer`、`subDelay`、`paused` 等字段。

- `volume-drag-report.json`：拖动音量后 `volume=95`，`panelOrigin={310,64}`（面板没有被误拖）
- `timeline-drag-report.json`：拖动时间轴后 `position≈46.4`，`panelOrigin={310,64}`
- `panel-drag-report.json`：从顶部拖动条拖动后 `panelOrigin={510,336}`
- `panel-clamp-report.json`：向右下拖到边界，位置被钳制为 `{612,630}`
- `panel-resize-report.json`：窗口缩到 800 × 500 后，面板被钳制为 `{232,370}`
- `panel-maximize-report.json`：⌘3 最大化后容器 1454 × 920，面板原点 `{447,64}`
- `panel-fullscreen-report.json`：原生全屏容器 1512 × 949，面板原点 `{476,64}`
- `panel-hover-hold-report.json`：鼠标悬停面板时 `showControls=true`，`chromeHolds=["panel-hover"]`
- `keyboard-focus-hold-report.json`：Tab 将焦点移入面板控件后 `chromeHolds=["keyboard-focus"]`
- `panel-leave-hide-report.json`：鼠标离开后 `showControls=false`，`chromeHolds=[]`
- `subtitle-offset-report.json`：通过字幕弹层的「延后 0.1 秒」行修改后 `subDelay=0.1`
- `fullscreen-rightclick-report.json`：原生全屏画面右键后 `paused=true`、`userPaused=true`
- `panel-recording-report.json`：录屏结束时 `subDelay=0.1`、`showControls=false`、`chromeHolds=[]`、面板原点 `{370,337}`
- `webdav-navigation-server.log`：真实 WebDAV 请求日志，见下节

## 2. 文件夹显示名验收

夹具目录：

```text
openlist/
  local/kaiwenyao/baidu/电视剧/
    Attack on Titan (2013)/Season 01/...
    Death Note (2006)/Season 01/...
    Fargo (2014)/Season 01/...
    中文 剧集 (2020)/Season 01/...
    100% 测试/Season 01/...
    Show 100%25/Season 01/...
```

WebDAV 夹具以 `--displayname-mode path` 启动：每个 `<displayname>` 都故意返回整条根相对路径（如 `local/kaiwenyao/baidu/电视剧/Fargo (2014)`），即修复前会出现「整条路径当卡片标题」的服务器行为。

实际用鼠标点击 Fargo → Season 01 → 面包屑「电视剧」返回，服务端请求序列为：

```text
PROPFIND /dav/                                                                   207
PROPFIND /dav/local/kaiwenyao/baidu/%E7%94%B5%E8%A7%86%E5%89%A7/                 207
PROPFIND /dav/local/kaiwenyao/baidu/%E7%94%B5%E8%A7%86%E5%89%A7/Fargo%20(2014)/  207
PROPFIND /dav/local/kaiwenyao/baidu/%E7%94%B5%E8%A7%86%E5%89%A7/Fargo%20(2014)/Season%2001/ 207
PROPFIND /dav/local/kaiwenyao/baidu/%E7%94%B5%E8%A7%86%E5%89%A7/                 207
```

没有出现 `.../Fargo (2014)/Fargo (2014)/...` 或 `.../Season 01/Season 01/...` 这类重复拼接。NFO 探测路径也变成正确的 `.../Season 01/Fargo (2014) - S01E01 - Pilot.nfo`，不再把整条路径拼在目录后面。

同一轮还验证了：

- 网格、列表、单季卡副标题与 VoiceOver 共用同一规则。AX 探针返回 `AXButton | 文件夹，Fargo (2014)`、`AXButton | Season 01`，说明 VoiceOver 读到的是本名而不是整条路径。
- 中文、空格、括号、尾斜杠、字面百分号（`100%`、`Show 100%25`）以及不同父目录下同名 `Season 01` 都有单元测试覆盖。
- `entry.path` 与 `url` 没有被改写；导航、缓存和请求仍使用它们。

## 3. 播放器验收

### 面板尺寸与位置

- 普通 1180 × 760 窗口：面板宽 560、高 94，内容坐标原点 `{310,64}`；位于画面顶部中央，标题条在面板上方，字幕在底部安全区。
- 320 pt 小窗：面板宽 304、高 82；第一行只保留字幕入口、居中播放/快退/快进与「更多」，第二行时间轴完整。
- 原生全屏（1512 × 949）：面板原点 `{476,64}`。
- ⌘3 最大化（1454 × 920）：面板原点 `{447,64}`。
- 窗口缩到 800 × 500：面板从右下角被钳制回 `{232,370}`，始终完整留在窗口内。
- 面板拖到右下边界：原点被钳制为 `{612,630}`（1180 × 732 内容区、560 × 94 面板）。

### 误拖防护

面板拖动只绑定在面板顶部 10 pt 的空白拖动条（中间有 28 × 3 pt 提示条），不绑定整块背景：

- 音量滑块拖动后 `volume=95`，`panelOrigin={310,64}`；
- 时间轴拖动后 `position≈46.4`，`panelOrigin={310,64}`；
- 只有拖动顶部空白条时 `panelOrigin` 才变化（`{510,336}`）。

### 自动隐藏与保持可见

- 鼠标进入面板：`chromeHolds=["panel-hover"]`，等待超过 3.2 秒仍 `showControls=true`。
- 鼠标离开面板：`chromeHolds=[]`，`showControls=false`。
- 字幕弹层打开：`chromeHolds` 包含 `subtitle-popover`，弹层选择与偏移修改期间面板不消失。
- 键盘 ↑/↓、空格、Tab 等操作会刷新 `keyboard` 保持并重新计时；Tab 把焦点移入面板控件后，`ChromeFocusMonitor` 通过窗口 first responder 设置 `keyboard-focus` 保持；拖动时间轴期间 `isScrubbing` 阻止隐藏。
- 键盘焦点报告：按 Tab 三次后等待 4 秒，`showControls=true`、`chromeHolds=["keyboard-focus"]`（`evidence/keyboard-focus-hold-report.json`）。
- 隐藏后移动鼠标会重新显示面板。

### 缩略图预览

- 面板在顶部默认位置时，预览向**下**展开（`previewBelow=true`）。
- 面板拖到画面中部后，预览向**上**展开；`10-player-drag-hover.png` 与录屏均可见。
- 预览仍使用原有 `ThumbnailProvider`、缓存区间和 `PlayerScrubber` 拖动逻辑。

### 字幕、标题与播放信息

- 顶部标题：作品名 + 季集号，例如 `Fargo (2014)` / `S01E01 · The Crocodile's Dilemma`。
- 完整文件名、来源、视频/音频编码、分辨率、音轨、字幕、速度、时长、缓存和会话日志在「播放信息」弹出层。
- 字幕按钮直接打开弹层；整行选轨、当前轨勾选、整行 hover 高亮、提前/延后 0.1 秒、输入秒数和重置均保留。
- 字幕偏移通过真实 AX 行点击从 0 改为 0.1 秒，报告 `subDelay=0.1`、`subDelaySummary="延后 0.1 秒"`。

### 材质与可读性

- macOS 26+：面板使用系统 `glassEffect(.regular, in:)`，再加一层 18% 黑色 tint 保证文字对比度。
- macOS 14/15：同一位置使用 `NSVisualEffectView(material: .hudWindow, blendingMode: .withinWindow)`。
- 系统「减少透明度」真实开启（`defaults write com.apple.universalaccess reduceTransparency -bool true`，验收后恢复）时，面板切换为不透明深色表面；`11-player-reduce-transparency.png` 为实际运行截图。
- 顶部标题条使用 `ultraThinMaterial` + 52% 黑色，视频高亮文字不会透过标题影响可读性。

### 播放行为回归

- ↑/↓ 音量、右键暂停（视频、黑边、控制栏、原生全屏）通过；全屏右键报告 `paused=true`。
- 320 pt 小窗、⌘3 最大化、原生全屏切换后都能找到面板。
- 从 WebDAV 单季页播放 S01E01，按 Esc 退出后回到 `Season 01` 页面，面包屑和「当前选集」保持；`12-player-return-season.png`。
- 顶栏返回按钮点击后回到首页并保留继续观看记录。

## 4. 安装包验证

```text
bash install-openfuse-macos.sh --app OpenFuse-macos.zip \
  --prefix /tmp/openfuse-install-test --no-launch --sign adhoc --lang zh-CN
  [2/5] 正在校验 SHA-256 与应用包…
  [3/5] 正在本地签名…
  [4/5] 正在安装到 /tmp/openfuse-install-test…
  [5/5] OpenFuse 安装完成。
  已安装 0.9.2(04b0160):/tmp/openfuse-install-test/OpenFuse.app
```

临时安装目录已删除。安装包内含 libmpv/FFmpeg 全部依赖，`codesign --verify --deep --strict` 通过，打包后的应用实际启动并播放夹具成功。

## 5. 自动化测试

```text
swift test
  Executed 136 tests, with 0 failures

Scripts/run-webdav-browser.sh
  PASS: WebDAV deep path browsed with a single canonical listing request

Scripts/run-player-interactions.sh
  ok arrow keys change in-app volume: 95
  ok mpv volume follows: 95.000000
  ok right click toggles in video / letterbox / controlbar / fullscreen
  ok two right clicks resume
  ok pause during buffering is kept after recovery
  PASS: volume keys, right-click regions/fullscreen, buffered pause
```

新增/更新的测试文件：

- `Tests/OpenFuseCoreTests/RemotePathTests.swift`：文件夹名回退、中文/空格/括号/尾斜杠/字面百分号、同名文件夹、路径身份不变、文件 basename 回退。
- `Tests/OpenFuseCoreTests/WebDAVTests.swift`：路径型 displayname 的列表与字幕匹配、百分比解码边界。
- `Tests/OpenFuseCoreTests/FloatingPanelTests.swift`：面板宽高、顶部居中、拖动钳制、窗口缩放、预览方向、标题格式化。

## 6. 与 QuickTime 的对照

在同一台 Mac 用 QuickTime Player 打开同一素材的 H.264 转码短片（原始 HEVC 夹具 QuickTime 不支持）：

- QuickTime floating controls 实测约 452 × 60 pt，时间轴约 324 pt，显示已播/总时长；控件固定在画面底部，窗口内不随拖动移动。
- OpenFuse 按本轮需求改为顶部居中、可拖动、两行：第一行运输控制 + 音量/选集/字幕，第二行独占时间轴并显示已播时间与**剩余时间**。宽度 480–560 pt，整体只占 560 × 94 pt，比 0.9.1 的 980 × 205 pt 明显收敛。
- QuickTime 的 AX 控件在暂停/播放后仍保留在辅助功能树中，未观察到可量化的自动隐藏时刻；OpenFuse 的自动隐藏由本轮运行报告和录屏直接验证。

## 7. 待验证

- macOS 14/15 的 `NSVisualEffectView` 分支已编译但本轮机器为 macOS 27，未在 14/15 实机截图。
- AirPlay 接收器、真实 5.1 功放、真实 OpenList 账号不在本轮环境内。
- 录屏由应用自身抓取窗口区域（`--record-screen`），未使用系统 Screen Recording 权限，因此不包含鼠标指针；面板移动、弹层、偏移变化和淡出均由画面内容体现。
