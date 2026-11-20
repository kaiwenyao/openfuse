# 0.4.0：默认明亮主题与 Trakt 移除

日期：2026-11-20 · 版本：0.4.0 · 平台：macOS（本轮只验收 Mac）

## 目标

1. 默认使用明亮主题，用户可在应用内修改主题。
2. 完全移除 https://trakt.tv 同步功能。
3. 推送并产出新的 macOS Release。

## 外观

### 实现

- 新增 [`Sources/OpenFuseApp/Theme.swift`](../Sources/OpenFuseApp/Theme.swift)：
  - `AppTheme`：`light` / `dark` / `system`，默认 `light`，持久化键 `openfuse.appearance`。
  - `Theme`：每个色值由 `NSColor(name:dynamicProvider:)` 提供明亮/深色两份，随当前外观解析。原有 `Theme.background`、`Theme.text` 等静态引用全部保留，无需逐视图改写。
  - 明亮色板：浅灰底 `#F5F6F8`、白面板 `#FFFFFF`、深字 `#111820`、蓝色强调 `#0B6FD1`；深色色板保持原深底浅字。
- [`HomeView.swift`](../Sources/OpenFuseApp/HomeView.swift)：
  - 移除 `.preferredColorScheme(.dark)` 与 `NSApp.appearance = .darkAqua` 的硬编码。
  - 根部按 `AppTheme` 应用 `.preferredColorScheme`，启动时应用 `AppTheme.stored`。
  - 新增自动化参数 `--appearance light|dark|system`，便于截图验收；新增 `--capture-sheet` 用于捕获设置 sheet。
- [`SettingsView.swift`](../Sources/OpenFuseApp/SettingsView.swift)：新增「外观」分段选择器（明亮 / 深色 / 跟随系统），切换即写入偏好并立即应用；播放器仍固定深色背景，避免观影时被明亮界面干扰。

### 验收（macOS）

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 首次启动默认明亮 | 通过 | [home-light.jpg](Evidence/0.4.0/home-light.jpg) |
| 深色外观 | 通过 | [home-dark.jpg](Evidence/0.4.0/home-dark.jpg) |
| 设置页外观选择器 | 通过 | [settings-light.jpg](Evidence/0.4.0/settings-light.jpg) |
| 明亮模式媒体库（扫描本地夹具） | 通过 | [library-light.jpg](Evidence/0.4.0/library-light.jpg) |
| 选择深色后即时换肤（sheet 保持打开） | 通过（AppleScript 点击「深色」后截图） | [settings-live-switch.jpg](Evidence/0.4.0/settings-live-switch.jpg) |
| 重启后保持上次选择 | 通过（`--appearance dark` 后无参数重启仍为深色） | `/tmp/openfuse-persist.png`（本地验收） |
| 默认值落盘 | 删除 `com.openfuse.app` 偏好域后启动，仍为明亮 | 同上，首张截图 |

## Trakt 移除

### 删除

- `Sources/OpenFuseApp/TraktService.swift`（设备码授权、轮询、搜索、scrobble）。
- `Sources/OpenFuseData/Trakt.swift`（`TraktClient`、历史、错误类型）。
- `AppModel` 中的全部 Trakt 状态与流程：`traktClientID/Secret/BaseURL`、设备码轮询、`saveTraktSettings`、`pollTraktToken`、`syncTraktHistory`、播放前 `prepare`、加载/保存/结束时的 start/update/stop。
- 设置页 Trakt 区块、首页「同步 Trakt 历史」菜单、`--trakt-auto-auth` 与 `--sync-trakt` 启动参数。
- `openfuse-probe` 的 `trakt-device` / `trakt-poll` 命令。
- `Scripts/run-trakt-acceptance.sh`、`run-trakt-auto-auth.sh`、`run-trakt-history.sh`、`run-trakt-remote-history.sh`；其余验收脚本中的 `OPENFUSE_TRAKT_*` 测试环境变量。

### 升级清理

首次启动 0.4.0 时执行一次 `purgeLegacyTraktState`：

- 删除 UserDefaults `openfuse.trakt.clientID`、`openfuse.trakt.baseURL`。
- 删除 Keychain `com.openfuse.trakt` 下的 `trakt-token`、`trakt-secret`。
- 写入 `openfuse.trakt.purged` 标记，之后不再重复执行。

### 验收（macOS）

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 源码无 Trakt 客户端/服务/UI/CLI | 通过 | `grep -rn -i trakt Sources` 仅剩升级清理逻辑 |
| Release 二进制无 Trakt API 或 scrobble 字符串 | 通过 | `strings OpenFuse \| grep -i "api.trakt\|scrobble\|device/code"` 无输出；仅剩 `openfuse.trakt.purged` 等清理键 |
| 设置页无 Trakt 区块 | 通过 | [settings-light.jpg](Evidence/0.4.0/settings-light.jpg) |
| 首页菜单无 Trakt 项 | 通过 | [home-light.jpg](Evidence/0.4.0/home-light.jpg) |

## 回归

- `swift test`：54 个单元测试全部通过。
- `Scripts/run-acceptance.sh`：通过（冻结帧 ~9.9s、简繁 ASS、6ch E-AC-3、libmpv 输出、字体回退、20s 续播）。
- `Scripts/build-app.sh release`：成功产出 `build/OpenFuse.app`。
- 本轮未改移动端、tvOS、visionOS 代码，也未运行其构建；主题与 Trakt 变更集中在 macOS 应用层与已删除的共享 Trakt 数据文件。
