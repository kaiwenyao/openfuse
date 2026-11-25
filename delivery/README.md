# OpenFuse 0.9.3 · macOS 交付包

基线：0.9.2（`d6268ee`）。本轮修复「在播放页面换集之后，右键任意位置或按空格都无法暂停视频」，并重新打包自包含安装包。

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
| `OpenFuse-macos.zip` | 28 MB 自包含 macOS 应用（libmpv + FFmpeg + 依赖，无需 Homebrew）；`CFBundleShortVersionString=0.9.3`，`OpenFuseCommit=1bb47d0` |
| `OpenFuse-macos.zip.sha256` | `4f901226225cd7b20a94869c1c4bad63f6d20721c1926f34e221d7ee67fcf1f0`（标准 `shasum` 格式，可直接 `-c` 校验） |
| `install-openfuse-macos.sh` | 安装/升级脚本 |
| `INSTALL.md` | 安装、校验、直接解压与运行要求 |
| `TEST-RESULTS.md` | 0.9.3 换集交互验收 + 0.9.2 历史验收证据 |
| `screenshots/`、`recording/`、`evidence/` | 0.9.2 界面改版的历史截图、录屏与运行时报告 |

## 本轮改动

- `PlayerView` 的 `NSEvent` 本地监视器不再按值捕获安装时的 `PlayerModel`：换集会新建模型但保留 `.player` 路由与视图身份，`onAppear` 不会重跑，旧闭包一直在对已停止的引擎调用 `togglePlayPause()`。
- 改为在事件到达时从 `AppModel.shared` 解析当前在屏剧集（`route == .player` 守卫）；空格、右键、↑/↓、←/→、Esc、⌘3 在选集换集、自动连播、加载中改选之后都作用于新引擎。
- 打包脚本的 SHA-256 sidecar 改回标准 `shasum` 格式，`shasum -a 256 -c` 可直接校验。
- 改动只涉及 `Sources/OpenFuseApp/PlayerView.swift` 与 `Scripts/package-release.sh`，播放器布局、面板几何和 mpv 管线不变。

详细根因与复现数据见 [0.9.3 换集修复](../Docs/0.9.3-EPISODE-SWITCH.md)。

## 验证摘要

- `swift test`：136 个测试，0 失败。
- `Scripts/run-episode-switch-pause.sh`：PASS（6 个真实输入用例：无换集基线空格/右键、选集面板换集空格/右键、直接打开另一文件换集空格、换集后 ↓ 音量键）。
- `Scripts/run-player-interactions.sh`：PASS（音量键、视频/黑边/控制栏/全屏右键、缓冲中暂停、两次右键恢复）。
- 打包后自包含 `OpenFuse.app` 实机冒烟：换集后空格暂停，`paused=true`、`userPaused=true`、`mpv v0.42.0`。
- `unzip -t`、`codesign --verify --deep --strict`、`shasum -a 256 -c` 全部通过；离线安装到 `--prefix /tmp/openfuse-install-093 --no-launch --sign adhoc` 成功，版本 0.9.3（`1bb47d0`）。

详细数据见 [TEST-RESULTS.md](TEST-RESULTS.md)。
