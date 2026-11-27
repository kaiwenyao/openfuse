# 功能性问题清单（2026-11-27）

审查基线为 `ce8ac76`（0.9.3），并已对照 0.9.5（`eb6cbf2`）更新状态。本文合并并取代此前的四份问题文档：`MACOS-CMD-TAB-PLAYBACK.md`、`MACOS-CMD-TAB-FIX-PROMPT.md`、`MACOS-SUBTITLE-OFFSET-BUG.md`、`MACOS-SUBTITLE-OFFSET-FIX-PROMPT.md`。只记录用户能感知到的问题，不含性能、安全和代码风格方面的建议。

## 怎么查的

- `swift test`：136 个单元测试全部通过。
- 实际运行 `build/OpenFuse.app`（0.9.3）。数据目录用 `OPENFUSE_SUPPORT_DIR` 指向临时目录，不会碰到个人数据。用到的启动参数有 `--open`、`--resume-first`、`--reopen-test` 和 `--capture-ui`。
- 其余问题是追代码逻辑确认的。iOS 端没有在模拟器里运行过，相关条目标为「疑似」。

## 汇总

| # | 严重程度 | 问题 | 状态 |
| --- | --- | --- | --- |
| 1 | 高 | 从「继续观看」打开的视频，关闭后卡在加载页 | 确认（实测） |
| 2 | 中 | 打开 WebDAV、Jellyfin 或本地文件失败时，界面没有提示 | 确认 |
| 3 | 中 | 「仅本次会话」的 WebDAV 来源重启后显示「用户名或密码不正确」 | 确认 |
| 4 | 中 | 字幕偏移的显示精度不够，负号和部分输入被解析错 | 已在 0.9.4 修复 |
| 5 | 中 | 播放时 ⌘Tab 切换应用卡顿 | 已在 0.9.5 修复 |
| 6 | 中 | iOS：来源页里的 WebDAV 浏览器点视频，可能打不开播放器 | 疑似 |
| 7 | 低 | 来源被删后点它的历史记录，提示「文件不存在」 | 确认 |
| 8 | 低 | 添加 WebDAV 时 Keychain 写入失败，用户看不到警告 | 确认 |
| 9 | 低 | iOS：添加 Jellyfin 失败时，表单照样关闭 | 疑似 |

以下几类检查后没有发现问题：

- 快速连续操作和重复点击：播放请求用 `sessionGeneration` 和 `loadingGeneration` 防止竞态，目录加载用 `loadToken` 去重。
- 用户操作导致的崩溃：没有找到。只有本地数据库打不开时，`fatalError` 会直接终止 App（[AppModel.swift:204](../Sources/OpenFuseApp/AppModel.swift#L204)），这属于环境异常。
- 主窗口文案未翻译、布局错乱：没有发现。

---

## 1. 从「继续观看」打开的视频，关闭后卡在加载页（高）

### 现象

在首页点一条「继续观看」，视频正常开始播放。之后点关闭、按 Esc，或者点「返回来源」，界面都没有回到首页，而是停在「正在准备播放…」：标题仍是刚才那集，加载圈一直转。只有点「取消」或左上角的 × 才能离开。从首页续播是最常用的入口，所以每次都会遇到。

### 复现

```bash
S="$(mktemp -d)"; APP=build/OpenFuse.app/Contents/MacOS/OpenFuse
OPENFUSE_SUPPORT_DIR="$S" "$APP" --open "$PWD/Fixtures/mobile/openfuse-mobile.mp4" --quit-after 5
OPENFUSE_SUPPORT_DIR="$S" "$APP" --resume-first --reopen-test --capture-ui "$S/after-close.png" --ui-after 8 --quit-after 10
open "$S/after-close.png"
```

第二条命令先续播第一条记录，4 秒后关闭播放器，8 秒时截图。截图里看到的是加载页，不是首页。

### 原因

1. `resume()` 先把路由设为 `.loading`，用来显示加载页（[AppModel.swift:674](../Sources/OpenFuseApp/AppModel.swift#L674)）。
2. `startPlayer()` 只要当前路由不是 `.player`，就把它记作返回路由：`playerReturnRoute = route`（[AppModel.swift:379-380](../Sources/OpenFuseApp/AppModel.swift#L379)）。所以这里记下的是 `.loading`。
3. 关闭时，`closePlayer()` 和 `onClose` 都执行 `route = playerReturnRoute ?? .home`（[AppModel.swift:404](../Sources/OpenFuseApp/AppModel.swift#L404)、[AppModel.swift:657](../Sources/OpenFuseApp/AppModel.swift#L657)），结果回到了加载页。
4. 续播成功后，`isLoadingPlayback` 一直没有复位，`loadingError` 是 nil，所以 `PlayerLoadingView` 一直显示加载圈。

### 解决方案

- 在 `startPlayer()` 里记录返回路由时跳过 `.loading`，改为记录用户进入加载页之前所在的页面。具体做法：在 `resume()` 进入 `.loading` 前，先把当时的 `route` 存进 `playerReturnRoute`；`startPlayer()` 遇到 `route == .loading` 时，不覆盖已经存下的值。如果什么都没存，就退回 `.home`。
- 播放器成功启动时，把 `isLoadingPlayback` 设为 false，并清空 `loadingError`，避免以后任何路径再回到这个状态时看到假的加载中。
- 兜底：`RootView` 在 `.loading` 路由下，如果 `isLoadingPlayback == false` 且没有错误，直接显示首页。

### 验收

- 上面的复现命令截图应显示首页。
- 新增一条脚本回归：从首页续播并关闭，回到首页；从 WebDAV 目录里播放并关闭，回到原目录；从 Jellyfin 详情页播放并关闭，回到详情页。
- 在加载中点取消、加载失败后点重试，行为保持不变。

---

## 2. 打开失败时界面没有提示（中）

### 现象

- 在 WebDAV 浏览页点一个视频。如果取不到密码（第一次被 Keychain 拒绝授权，或者凭据被删除了），行尾的加载圈闪一下就消失：什么都没打开，也没有任何提示。
- 在 Jellyfin 详情页或媒体库里点播放时也一样：令牌缺失、服务器没有返回可播放版本、网络错误，都没有任何反馈。
- Keychain 的引导文案「请在系统弹窗中允许 OpenFuse，然后再次操作」也看不到，用户不知道要再点一次。

### 原因

这些失败都只写进了 `AppModel.statusMessage`：

- [AppModel.swift:583-586](../Sources/OpenFuseApp/AppModel.swift#L583)
- [AppModel.swift:462](../Sources/OpenFuseApp/AppModel.swift#L462)
- [AppModel.swift:1321-1366](../Sources/OpenFuseApp/AppModel.swift#L1321)
- [AppModel.swift:337](../Sources/OpenFuseApp/AppModel.swift#L337)

全部界面代码里，只有两个地方会读这个字段，而且只在失败时把它填进表单：

- 「添加 WebDAV」弹窗（[BrowserView.swift:908](../Sources/OpenFuseApp/BrowserView.swift#L908)）
- 「Jellyfin 登录」弹窗（[JellyfinView.swift:366](../Sources/OpenFuseApp/JellyfinView.swift#L366)）

此外，只有经过「继续观看」时，`performResume` 才会把这个字段转成加载页上的错误（[AppModel.swift:718-719](../Sources/OpenFuseApp/AppModel.swift#L718)）。

### 解决方案

- 在 `MainShellView` 层加一个全局的提示条或 toast，订阅 `statusMessage`：有值时显示，几秒后自动清除，用户也可以手动关掉。这样所有现有的失败提示都能显示出来，不需要逐个改调用点。
- WebDAV 浏览页的 `play(_:)` 和 `row(_:)` 在 `openRemote` 返回后检查：如果没有启动播放器（`model.player` 不是这个条目），就把 `statusMessage` 显示在当前目录上方，和 `errorMessage` 走同一个样式。
- 更好的做法是让 `openRemote` 和 `openJellyfinItem` 返回结果，比如 `Result<Void, OpenError>` 或 `Bool`，由调用的页面决定怎么展示，不再依赖全局字符串。
- 遇到 Keychain 需要授权的情况时，提示里直接放一个「重试」按钮，点了会调用 `CredentialStore.loadInteractive`，让系统弹出授权窗口。

### 验收

- 删除 Keychain 中某个 WebDAV 来源的凭据，然后在浏览页点视频，应看到「缺少密码」的提示，提示里要有重新输入或重试的入口。
- 让 Jellyfin 测试服务器返回 500 或断网，再点播放，应看到错误提示。

---

## 3. 「仅本次会话」的 WebDAV 来源重启后显示「用户名或密码不正确」（中）

### 现象

1. 添加 WebDAV 时勾选「仅本次会话（不写入 Keychain，退出后需重新输入）」。
2. 退出 App 再打开，点进这个来源。

目录页显示「用户名或密码不正确」，看起来像是账号填错了。界面上没有地方能重新输入密码，只能用同一个地址和用户名重新添加。来源 ID 由地址和用户名生成，所以重新添加会覆盖旧的，不会出现两个。

### 原因

- 会话凭据只存在内存里，重启后 `password(for:)` 返回 nil。
- 这时 `loadDirectory` 抛出的是 `WebDAVError.unauthorized`（[AppModel.swift:564-567](../Sources/OpenFuseApp/AppModel.swift#L564)），而这个错误的文案是「用户名或密码不正确」（[WebDAV.swift:82](../Sources/OpenFuseData/WebDAV.swift#L82)）。
- 来源列表里也没有编辑凭据的入口。

### 解决方案

- 新增 `WebDAVError.missingCredential`，文案为「需要输入 \(来源名) 的密码」。`loadDirectory` 取不到密码时抛这个错误，`openRemote` 里同样的位置也改用它。
- 目录错误页遇到 `missingCredential` 时，显示「输入密码」按钮。点击后弹出已经预填好地址和用户名的表单，复用 `AddWebDAVSheet` 的提交逻辑，校验通过后回到当前目录，并保留目录层级。
- 来源卡片的右键菜单里加「更新密码…」。

### 验收

- 按上面的步骤复现，应看到「需要输入密码」和输入入口。输入正确密码后能列出目录，在同一个会话里播放不再要求输入。
- Keychain 模式的来源不受影响。

---

## 4. 字幕偏移的显示精度和输入解析（中，已在 0.9.4 修复）

### 现象

- 偏移设为 `0.04` 秒时字幕实际已经偏移，菜单却显示「同步（0 秒）」，输入框预填 `0.0`。
- 偏移为 `0.15` 秒时，菜单显示「延后 0.2 秒」，输入框预填 `0.1`；直接点「应用」，偏移会被改成 0.1 秒。
- 输入 `−0.1`（U+2212 数学负号）会被解析成 +0.1 秒，`-.1` 被解析成 +1 秒，「提前 0.1 秒」被解析成延后 0.1 秒。

### 原因

- 菜单文案先把偏移舍入到 0.1 秒，输入框按 `%.1f` 预填，但 mpv 实际按毫秒精度生效，所以显示和实际不一致，原样「应用」还会改变偏移。
- 解析只处理了全角正负号，用正则找第一个数字片段，所以 U+2212 的负号会丢失，`-.1` 匹配成 `1`，方向词被忽略。

### 已采用的修复

修复提交为 `1093bfe`，随 0.9.4 发布：

- [SubtitleOffset.swift](../Sources/OpenFuseData/SubtitleOffset.swift) 新增 `normalized` 和 `valueText`：菜单、输入框、存储和 mpv 统一用毫秒精度，只有实际为 0 时才显示「同步」。
- `parse` 改为整串锚定匹配：支持 U+2212、全角负号、逗号小数、`.1` 这种省略整数部分的写法，以及「提前」「延后」方向词；只匹配到一部分的输入会被拒绝，不再悄悄取出别的数字。
- `PlayerModel` 恢复旧记录时也走 `normalized`。

### 回归

`Tests/OpenFuseCoreTests/SubtitleOffsetTests.swift` 已覆盖以上样例。以后改字幕偏移相关代码时，要运行：

```bash
swift test --filter 'SubtitleOffsetTests|SubtitleCatalogTests|PlaybackClockTests'
```

---

## 5. 播放时 ⌘Tab 切换应用卡顿（中，已在 0.9.5 修复）

### 现象

在 OpenFuse 里持续播放视频时，按 ⌘Tab 切到其他应用会明显卡顿。暂停时或在首页切换都不会出现。

### 原因

- 渲染链路是：libmpv 更新回调 → 主队列设置 `needsDisplay` → AppKit 调用 `MPVGLView.draw(_:)` → `mpv_render_context_render`。
- 在默认的 `video-sync=audio` 下，libmpv 会提前 `video-timing-offset`（默认 0.05 秒）把帧交给渲染接口，渲染调用再阻塞到目标呈现时刻。
- 这段等待发生在 AppKit 主线程上。0.9.3 播放时，约 67% 的主线程样本落在 libmpv 的条件等待里，暂停时为 0，所以切换应用时窗口合成会抖动。

### 已采用的修复

修复提交为 `a3f8dcd`，随 0.9.5 发布，详细记录见 [MACOS-CMD-TAB-FIX.md](MACOS-CMD-TAB-FIX.md)：

- macOS 上用 `NSOpenGLView` 的交互式播放引擎在 `video-sync=audio` 时，把 `video-timing-offset` 设为 0。具体规则在 `VideoTimingPolicy` 里。
- 效果：渲染阻塞的中位数从约 35 ms 降到约 3 ms；超出一帧预算的绘制从约 95% 降到约 5%；音画同步没有变差。
- 新增 `RenderTiming` 分段计时诊断。

### 回归

改动播放渲染链路时，要运行：

- `swift test`，其中包括 `RenderTimingTests` 和 `VideoTimingPolicyTests`；
- `Scripts/run-player-responsiveness.sh`
- `Scripts/run-player-interactions.sh`
- `Scripts/run-episode-switch-pause.sh`

---

## 6. iOS：来源页里的 WebDAV 浏览器点视频，可能打不开播放器（中，疑似）

### 现象（推断）

在 iPhone 或 iPad 上打开「媒体来源」，进入一个 WebDAV 来源，点一个视频。播放器的全屏覆盖层可能不会出现，看起来就是点了没反应。

### 原因

- WebDAV 浏览器 `MobileWebDAVBrowserView` 在 `showSources` 这个 sheet 里面（[MobileRootView.swift:36](../Platforms/Mobile/MobileRootView.swift#L36)）。
- 点视频后设置的是 `model.browserPlayback`，而它对应的 `fullScreenCover` 挂在根视图上（[MobileRootView.swift:112](../Platforms/Mobile/MobileRootView.swift#L112)）。
- 同一个视图已经弹出 sheet 时，SwiftUI 一般不会再弹出另一个覆盖层，控制台会打印 "already presenting"。
- 仓库里有浏览器验收脚本覆盖了这条路径，需要在模拟器里实测确认。

### 解决方案

- 把播放器的 `fullScreenCover(item: $model.browserPlayback)` 挂到 `MobileSourcesView` 的 `NavigationStack` 上，或者挂到 `MobileWebDAVBrowserView` 自己身上，让它从最上层的 sheet 弹出。
- 或者点视频时先关闭来源 sheet，等 sheet 完全关闭后再设置 `browserPlayback`。这样会丢失浏览位置，不推荐。

### 验收

在模拟器里：来源 → WebDAV → 进入一个子目录 → 点 MP4 和 MKV。两种文件都应进入全屏播放；关闭播放器后，应回到原来的目录。

---

## 7. 来源被删后点它的历史记录，提示「文件不存在」（低）

### 现象

某条 WebDAV 或 Jellyfin 的「继续观看」记录，对应的来源已经被删除。点它之后，加载页报「文件不存在：xxx」，看起来像是本地文件丢了。

### 原因

`performResume` 在来源里找不到对应的 `sourceID` 时，会落到最后的 `else` 分支，执行 `open(url: record.url)`，把远程记录当成本地文件去检查（[AppModel.swift:714-716](../Sources/OpenFuseApp/AppModel.swift#L714)）。

### 解决方案

- 在 `performResume` 里先按 `record.sourceKind` 分类。如果是远程类型（`webdav`、`jellyfin`、`emby`、`smb`、`plex`）而来源不存在，直接调用 `finishLoadingFailure`，提示「这个视频所在的来源「\(名称)」已被移除」。
- 错误页上加「从历史中移除」按钮，调用 `removeRecent`。

### 验收

添加一个 WebDAV 来源，播放一个文件生成历史记录，然后删除这个来源，再点这条历史记录，应看到上面的提示和移除按钮。

---

## 8. 添加 WebDAV 时 Keychain 写入失败，用户看不到警告（低）

### 现象

添加 WebDAV 来源时连接成功，但 Keychain 写入失败。弹窗立即关闭，用户以为密码已经保存了。重启后才发现需要重新输入（表现同第 3 条）。

### 原因

警告「来源已保存到本次会话，但 Keychain 写入失败」写进了 `statusMessage`（[AppModel.swift:501-504](../Sources/OpenFuseApp/AppModel.swift#L501)），而成功分支直接 `dismiss()`，这条消息没有任何地方显示（见第 2 条）。

### 解决方案

- 第 2 条的全局提示条做好后，这条警告自然就能显示。
- 更稳妥的做法：`addSource` 返回 `(source, warning)`。有警告时，弹窗先停留，在原位显示警告和「知道了」按钮，用户确认后再关闭。

### 验收

用会写入失败的 Keychain 环境（比如拒绝授权）添加来源，应看到警告。

---

## 9. iOS：添加 Jellyfin 失败时，表单照样关闭（低，疑似）

### 现象（推断）

在 iOS 的「添加 Jellyfin」表单里填错地址或密码，点「保存」后表单照样关闭，来源没有添加成功，原因也不清楚。

### 原因

这次未提交的改动里，WebDAV 那一支改成了失败时留在表单并显示 `errorText`，但 Jellyfin 那一支还是无论成功与否都调用 `dismiss()`（[MobileSourcesView.swift:250-252](../Platforms/Mobile/MobileSourcesView.swift#L250)）。失败原因只写进了 `model.status`，需要确认它有没有在其他地方显示。

### 解决方案

把 `addJellyfin` 改成返回 `Bool` 或来源本身。保存按钮像 WebDAV 那一支一样处理：成功才关闭，失败时设置 `errorText = model.status ?? "登录失败"`，表单保持打开。

### 验收

在模拟器里用错误的密码添加 Jellyfin，表单应保持打开，并显示错误；用正确的密码添加，表单关闭，来源出现在列表里。
