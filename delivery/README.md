# OpenFuse 0.9.2 · macOS 交付包

基线：0.9.1（`04b0160`）。本轮修复 WebDAV 文件夹卡片显示名，并把播放器改成紧凑、可拖动的原生悬浮面板。

## 快速开始

```bash
cd /Users/ykw/Documents/openfuse/delivery
shasum -a 256 -c OpenFuse-macos.zip.sha256
bash install-openfuse-macos.sh --app OpenFuse-macos.zip
```

安装器默认装到 `/Applications`，会校验 SHA-256、备份旧版本、使用本机持久签名身份重签。也可直接解压：

```bash
ditto -x -k OpenFuse-macos.zip /Applications
xattr -dr com.apple.quarantine /Applications/OpenFuse.app
open /Applications/OpenFuse.app
```

## 交付文件

| 路径 | 说明 |
| --- | --- |
| `OpenFuse-macos.zip` | 28 MB 自包含 macOS 应用（libmpv + FFmpeg + 依赖，无需 Homebrew） |
| `OpenFuse-macos.zip.sha256` | `5464f2e063bc2309e7b2aa2eabffccd81f3350255ffc51cadb03b0bb7fafe348`（重新打包后以实际文件为准） |
| `install-openfuse-macos.sh` | 安装/升级脚本 |
| `INSTALL.md` | 安装、校验、直接解压与运行要求 |
| `TEST-RESULTS.md` | 逐项验收结果、测试命令、面板几何数据、QuickTime 对照与待验证项 |
| `screenshots/` | 改动前后、普通窗口、320 pt、全屏、隐藏、字幕弹层、网格/列表、拖拽预览、减少透明度、返回原集 |
| `recording/panel-interaction.mp4` | 18.9 秒短录屏：拖面板 → 悬停预览 → 字幕偏移 → 控件淡出 |
| `evidence/` | 运行时报告 JSON 与 WebDAV 服务端请求日志 |

## 核心改动

- `RemoteEntry.folderDisplayName`：单段 `<displayname>` 优先，整条路径/缺失时回退到 `entry.path` 最后一段；网格、列表、单季卡副标题、VoiceOver 同规则。`path`/`url` 不变。
- `RemoteEntry.baseName` / `fileBaseName`：路径型 displayname 下 NFO、外挂字幕和播放标题不再重复拼路径。
- `PlayerChrome`：顶部居中两行悬浮面板，常规 480–560 pt，320 pt 收缩到 304 pt；播放/快退/快进居中，音量、选集、字幕分列；时间轴独占第二行并显示剩余时间。
- macOS 26+ `glassEffect`；macOS 14/15 `NSVisualEffectView` within-window；减少透明度时使用不透明面板。
- 面板只能由顶部空白拖动条移动，并始终限制在窗口内；拖动音量/时间轴不会误拖面板。
- 悬停面板、字幕弹层、键盘操作、拖动时间轴期间保持可见，空闲 3.2 秒后淡出。
- 缩略图预览随面板位置向上/向下展开。
- 标题收敛为作品名 + 季集号；完整文件名、来源、编码和日志在「播放信息」。
- 右键暂停、↑/↓ 音量、Esc 退出、退出后返回原季/选集保持。

## 验证摘要

- `swift test`：136 个测试，0 失败。
- `Scripts/run-webdav-browser.sh`：PASS。
- `Scripts/run-player-interactions.sh`：PASS（音量键、四个区域右键、全屏右键、缓冲中暂停）。
- 真实 WebDAV 夹具（`--displayname-mode path`）：点击 Fargo → Season 01 → 面包屑返回，请求路径无重复拼接。
- 面板几何：普通 `{310,64}`、全屏 `{476,64}`、⌘3 `{447,64}`、拖动钳制 `{612,630}`、缩放后 `{232,370}`。
- 录屏报告：`subDelay=0.1`、`showControls=false`、`chromeHolds=[]`。

详细数据见 [TEST-RESULTS.md](TEST-RESULTS.md)。
