# 功能性问题清单（2026-11-27）

审查基线为 `ce8ac76`（0.9.3），并已对照 0.9.5（`eb6cbf2`）更新状态。本文合并并取代此前的四份问题文档：`MACOS-CMD-TAB-PLAYBACK.md`、`MACOS-CMD-TAB-FIX-PROMPT.md`、`MACOS-SUBTITLE-OFFSET-BUG.md`、`MACOS-SUBTITLE-OFFSET-FIX-PROMPT.md`。只记录用户能感知到的问题，不含性能、安全和代码风格方面的建议。

修复轮次：分支 `fix/bug-review-2026-11-27`，基线 `fa11eb6`（0.9.5 之后）。第 4、5 条保持 0.9.4 / 0.9.5 的修复不动，其余 7 条本轮处理完毕：第 1、2、3、7 条在本机实测通过；第 8 条只做到代码路径与单测（本机 Keychain 不会对 OpenFuse 拒绝写入，制造不出真实的写入失败）；第 6、9 条（iOS）因本机没有可启动的模拟器运行时而只完成代码修复与构建验证。原因与待验证方法见对应小节。

## 怎么查的

- `swift test`：审查时为 136 个单元测试，本轮基线已是 160 个；加入本轮新增用例后为 179 个，全部通过。
- 实际运行 `build/OpenFuse.app`。数据目录用 `OPENFUSE_SUPPORT_DIR` 指向临时目录，不会碰到个人数据。用到的启动参数有 `--open`、`--resume-first`、`--reopen-test`、`--capture-ui`，以及本轮新增的 `--route-log`、`--close-after`、`--cancel-loading-after`、`--retry-loading-after`、`--webdav-session-only`、`--show-update-password`、`--webdav-credential-report`。
- 其余问题是追代码逻辑确认的。iOS 端没有在模拟器里运行过：本轮环境里 `xcrun simctl list runtimes` 为空，所有设备都报 `runtime profile not found`，无法启动任何模拟器，因此 iOS 两条只有构建与代码层验证。

## 汇总

| # | 严重程度 | 问题 | 状态 |
| --- | --- | --- | --- |
| 1 | 高 | 从「继续观看」打开的视频，关闭后卡在加载页 | 已修复（`8f59139`），实测通过 |
| 2 | 中 | 打开 WebDAV、Jellyfin 或本地文件失败时，界面没有提示 | 已修复（`8f59139`），实测通过 |
| 3 | 中 | 「仅本次会话」的 WebDAV 来源重启后显示「用户名或密码不正确」 | 已修复（`8f59139`），实测通过 |
| 4 | 中 | 字幕偏移的显示精度不够，负号和部分输入被解析错 | 已在 0.9.4 修复 |
| 5 | 中 | 播放时 ⌘Tab 切换应用卡顿 | 已在 0.9.5 修复 |
| 6 | 中 | iOS：来源页里的 WebDAV 浏览器点视频，可能打不开播放器 | 已修复（`8f59139`），模拟器不可用，未实测 |
| 7 | 低 | 来源被删后点它的历史记录，提示「文件不存在」 | 已修复（`8f59139`），实测通过 |
| 8 | 低 | 添加 WebDAV 时 Keychain 写入失败，用户看不到警告 | 已修复（`8f59139`），代码路径与单测通过，写入失败场景未能实测 |
| 9 | 低 | iOS：添加 Jellyfin 失败时，表单照样关闭 | 已修复（`8f59139`），模拟器不可用，未实测 |

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

### 已采用的修复

修复提交 `8f59139`：

- 新增 [PlayerRoutePolicy.swift](../Sources/OpenFuseCore/PlayerRoutePolicy.swift)：`PlayerReturnRoutePolicy.route(current:existing:isPlaceholder:)` 决定要记的返回路由（加载页是占位页，永远不作为目的地；已经存下的页面不被它覆盖），`PlaybackLoadingState.showsLoadingPage(isLoading:error:)` 决定 `.loading` 还该不该显示加载页。
- [AppModel.swift](../Sources/OpenFuseApp/AppModel.swift) 的 `resume()` 在把路由改成 `.loading` **之前**调用新的 `rememberPlayerReturnRoute()`，先记下当时所在的页面；`startPlayer()` 遇到 `.loading` 时走同一条规则，不覆盖已存的值，没存过就退回首页。
- `startPlayer()` 在 `route = .player` 之后把 `isLoadingPlayback` 设为 false、清空 `loadingError`，并把新增的 `loadingFailure` 复位，避免任何路径再看到假的加载中。
- [HomeView.swift](../Sources/OpenFuseApp/HomeView.swift) 的 `RootView` 在 `.loading` 路由下用 `showsLoadingPage` 兜底：既不在加载、也没有错误时直接显示 `MainShellView { HomeView }`，和首页完全一致。
- 新增 [Scripts/run-close-return-route.sh](../Scripts/run-close-return-route.sh)，并给 AppModel 加了一个只在验收时启用的路由日志：`--route-log <path>` 以 10 Hz 采样，状态变化时追加一行 JSON（`route`/`loading`/`error`/`player`）。截图只能证明某一刻的画面，日志才能精确说明关闭后落在哪一页。同一批验收钩子还有 `--close-after`、`--cancel-loading-after`、`--retry-loading-after`。

### 验证结果

文档里的复现命令（数据目录指向临时目录）：

```bash
S="$(mktemp -d)"; APP=build/OpenFuse.app/Contents/MacOS/OpenFuse
OPENFUSE_SUPPORT_DIR="$S" "$APP" --open "$PWD/Fixtures/mobile/openfuse-mobile.mp4" --quit-after 5
OPENFUSE_SUPPORT_DIR="$S" "$APP" --resume-first --reopen-test --route-log "$S/route.jsonl" \
  --capture-ui "$S/after-close.png" --ui-after 8 --quit-after 10
```

- 截图 `$S/after-close.png` 显示的是首页（「继续观看」卡片在），不再是加载页，见 [01-resume-close-returns-home.jpg](Evidence/bug-review-2026-11-27/01-resume-close-returns-home.jpg)。
- 路由日志：4 秒左右播放器关闭后连续记录 `{"route":"home","loading":false,"player":""}`，修复前这里会是 `{"route":"loading","loading":true}"`。
- `Scripts/run-close-return-route.sh` 四种情况全部通过：

```
ok   resume played before closing: yes
ok   resume close returns to the home page: home
ok   no loading spinner after resume close: false
ok   local file played before closing: yes
ok   local close returns to the home page: home
ok   cancel: the loading page was really shown: yes
ok   cancel during loading returns to the home page: home
ok   failed resume shows the loading page: yes
ok   failed resume stays on the loading page: loading
ok   failed resume: error message kept after 重试: 网络错误：无法连接服务器。
PASS: resume close, local close, cancel during loading, retry after failure
```

（从 WebDAV 目录/Jellyfin 详情页播放再关闭回到原处这一条，脚本用「加载中点取消」「加载失败后重试」两项覆盖 `.loading` 的进入与退出；返回原目录/详情页由 `playerReturnRoute` 记的是 `.browser`/`.jellyfinBrowser` 保证，`Scripts/run-webdav-browser.sh` 继续验证浏览器层级不丢。）

截图：[03-cancel-during-loading.jpg](Evidence/bug-review-2026-11-27/03-cancel-during-loading.jpg)、[04-retry-keeps-error-page.jpg](Evidence/bug-review-2026-11-27/04-retry-keeps-error-page.jpg)。

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

### 已采用的修复

修复提交 `8f59139`：

- [MainShellView.swift](../Sources/OpenFuseApp/MainShellView.swift) 新增全局提示条 `StatusToast`：显示 `statusMessage`，6 秒后自动消失，右上角 × 可手动关闭；`.task(id: message)` 让新消息重置计时，全部用普通 SwiftUI（不依赖任何只在某个系统版本可用的呈现修饰符），macOS 14/15/26 都是同一条横条。
- [AppModel.swift](../Sources/OpenFuseApp/AppModel.swift) 增加 `showStatus(_:)`、`showKeychainNotice(_:account:service:retry:)`、`dismissStatus()`、`retryCredentialAccess()`；`statusMessage` 的 `didSet` 会清掉上一条提示的按钮，避免「重试」残留在无关的提示上。
- Keychain 需要授权时走 `showKeychainNotice`：提示里的「重试」先调用 `CredentialStore.loadInteractive`（系统弹窗这时才会出现），再自动重跑被打断的那次打开。
- [BrowserView.swift](../Sources/OpenFuseApp/BrowserView.swift) 的 `play(_:)` 在 `openRemote` 返回后检查 `model.player?.item.remotePath`：没打开就在目录上方显示失败原因（`playErrorBanner`，和目录错误页同一套图标/配色），列表行也改走同一个 `play()`，两条入口不再各写一份。
- Jellyfin 一侧沿用 `openJellyfinItem` 已有的 `statusMessage` 赋值，不需要逐个改调用点。

### 验证结果

- WebDAV：`OPENFUSE_CREDENTIAL_MODE=session` 添加来源后重启，凭据被删掉，点视频时同时看到顶部提示条与页内横幅「需要输入 Fixture 的密码」，见 [05-webdav-play-failure-toast-and-banner.jpg](Evidence/bug-review-2026-11-27/05-webdav-play-failure-toast-and-banner.jpg)。复现命令：

```bash
S=build/bug-review-2026-11-27/toast-webdav   # 见下方「本轮验证记录」
OPENFUSE_SUPPORT_DIR="$S/support" OPENFUSE_BROWSER_PLAY_FIRST=1 OPENFUSE_BROWSER_PLAY_AFTER=0.5 \
  OPENFUSE_BROWSER_DROP_CREDENTIAL=1 \
  build/OpenFuse.app/Contents/MacOS/OpenFuse \
  --webdav-url "http://127.0.0.1:$PORT/dav/" --webdav-name Fixture --webdav-user admin \
  --webdav-pass test --webdav-browse --webdav-browse-path Shows \
  --capture-ui "$S/after-click.png" --ui-after 6 --quit-after 7
```

（`OPENFUSE_BROWSER_PLAY_FIRST` / `OPENFUSE_BROWSER_DROP_CREDENTIAL` 是验收钩子：前者按真实 `play(_:)` 路径点第一个视频，后者在列出目录之后、点播放之前用 `CredentialStore.delete` 删掉凭据，等价于「凭据被删除了」。）

- Jellyfin：测试服务器在，但条目 id 不存在时点播放，顶部出现「Jellyfin 条目不存在」，见 [06-jellyfin-play-failure-toast.jpg](Evidence/bug-review-2026-11-27/06-jellyfin-play-failure-toast.jpg)。
- 「重试」按钮的 Keychain 分支：本机 Keychain 不会对 OpenFuse 拒绝授权，无法制造 `needsAuthorization`，只做了代码层与单测验证（`StatusNoticeKind.keychainAuthorization.offersCredentialRetry`）。

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

### 已采用的修复

修复提交 `8f59139`：

- [WebDAV.swift](../Sources/OpenFuseData/WebDAV.swift) 新增 `WebDAVError.missingCredential(sourceName:)`，文案「需要输入 \(来源名) 的密码」；`loadDirectory` 取不到密码时改抛它，`openRemote`（条目与路径两个入口）取不到密码时用同一句文案，不再说「请重新添加来源」。
- [RemoteFailurePolicy.swift](../Sources/OpenFuseCore/RemoteFailurePolicy.swift) 的 `RemoteDirectoryRecovery.action(for:)` 把错误分类成「重试」或「输入密码」。
- [BrowserView.swift](../Sources/OpenFuseApp/BrowserView.swift) 的目录错误页遇到 `enterPassword` 时显示「输入密码」按钮；按钮打开 `AddSourceSheet(existing:)`，标题变成「更新 <名称> 的密码」，地址和用户名按来源预填并锁定（来源 id 由这两项决定），提交沿用同一份 `addSource` 流程（先 `list()` 校验，再按「仅本次会话」开关写入）。表单关闭后在**当前目录**重新 `load(path:)`，层级不变。
- [HomeView.swift](../Sources/OpenFuseApp/HomeView.swift) 的来源卡片右键菜单新增「更新密码…」，走同一个表单（`AppModel.requestPasswordUpdate(for:)` 和 `passwordUpdateSource`，由 `MainShellView` 统一呈现）。

### 验证结果

复现（`OPENFUSE_CREDENTIAL_MODE=session` + `--webdav-session-only` 添加来源，进程退出后凭据只在内存里，重启即丢失）：

- 目录页显示「需要输入 Fixture 的密码」和「输入密码」按钮，见 [07-missing-credential-page.jpg](Evidence/bug-review-2026-11-27/07-missing-credential-page.jpg)。
- 点「输入密码」后的表单按来源预填了名称、地址、用户名，见 [08-prefilled-password-form.jpg](Evidence/bug-review-2026-11-27/08-prefilled-password-form.jpg)。
- 提交同一份逻辑后目录能重新列出（`--webdav-credential-report` 的输出）：

```json
{
  "firstLoad" : "需要输入 Fixture 的密码",
  "firstRecovery" : "enterPassword",
  "secondEntries" : 1,
  "secondLoad" : "ok",
  "source" : "Fixture",
  "submit" : "ok"
}
```

- Keychain 模式的来源不受影响：`Scripts/run-webdav-browser.sh` 用的就是不勾「仅本次会话」的来源，本轮仍然通过（见下「本轮验证记录」）。

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

### 已采用的修复

修复提交 `8f59139`（**未能在模拟器实测**，见下）：

- [MobileRootView.swift](../Platforms/Mobile/MobileRootView.swift) 去掉挂在根视图上的 `.fullScreenCover(item: browserPlayback)`。
- [MobileWebDAVBrowserView.swift](../Platforms/Mobile/MobileWebDAVBrowserView.swift) 把这个覆盖层挂到浏览器自己身上：浏览器在「媒体来源」sheet 里，根视图已经在 present 那个 sheet，iOS 会丢弃第二次全屏呈现（控制台会打印 "already presenting"）。改到浏览器上之后，呈现由 sheet 自己的 hosting controller 发起。
- 关闭播放器回到原目录：`browserPlayback` 置 nil 只是收掉覆盖层，`RemotePathState` 导航栈没有被改动。

### 验证情况

- 本机没有可启动的 iOS 运行时：`xcrun simctl list runtimes` 输出为空，`xcrun simctl list devices` 里所有设备都是 `unavailable, runtime profile not found using "System" match policy`，`xcrun simctl boot "iPhone 16 Pro"` 直接报 `Invalid device`。因此**没能**在模拟器里复现或确认「打不开」。
- 能做的：`Scripts/build-ios.sh` 构建通过（`** BUILD SUCCEEDED **`），说明改动本身可编译。
- 判断依据：这条按文档给的方案一改（挂到浏览器视图自己身上），是在既有 sheet 之上弹全屏覆盖层的标准做法；若原来的位置本来能工作，改动后仍然是同一个 `fullScreenCover(item:)`、同一份 `MobilePlayerView`，行为只会从「从根视图发起」变成「从 sheet 内容发起」。
- 待验证方法（有模拟器时）：`Scripts/build-ios.sh` + `xcrun simctl install booted build/mobile-derived/Build/Products/Debug-iphonesimulator/OpenFuse.app`，用 `OPENFUSE_BROWSE_ACCEPTANCE=1` 打开来源 sheet，`OPENFUSE_BROWSE_SCRIPT` 里带 `probe`（会分别记录 MP4/MKV 的 `requiresMPV`），随后脚本会自动依次播放 MP4 与 MKV；也可以手动：媒体来源 → WebDAV → 子目录 → 点 MP4 / MKV，看是否进入全屏、关闭后是否回到同一目录。

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

### 已采用的修复

修复提交 `8f59139`：

- [RemoteFailurePolicy.swift](../Sources/OpenFuseCore/RemoteFailurePolicy.swift) 新增 `PlaybackSourceKind.isRemote`（`webdav`/`jellyfin`/`emby`/`smb`/`plex`）和 `LoadingFailureKind`。`PlaybackRecord.isRemote` 只认 webdav/jellyfin，是首页封面用的窄集合，不能拿来做这个判断。
- [AppModel.swift](../Sources/OpenFuseApp/AppModel.swift) 的 `performResume` 在这条链的最后加了一个分支：远程类型而来源已经不存在时直接 `finishLoadingFailure(..., kind: .sourceRemoved)`，提示「这个视频所在的来源「名称」已被移除」（来源名称已随来源一起消失时用「这个视频所在的来源已被移除」），不再把远程 URL 当本地文件去检查。
- [PlayerLoadingView.swift](../Sources/OpenFuseApp/PlayerLoadingView.swift) 按 `loadingFailure.offersRemoveFromHistory` 显示「从历史中移除」（替代「重试」），调用新的 `AppModel.removeFailedRecordFromHistory()`（复用 `removeRecent` + `cancelLoading`）。

### 验证结果

```bash
# 1) 播放一次生成历史记录   2) 清空 sources.json 模拟来源被删   3) 再点这条历史记录
OPENFUSE_SUPPORT_DIR="$S/support" OPENFUSE_WEBDAV_PASSWORD=test "$APP" --resume-first --route-log "$S/route.jsonl" \
  --capture-ui "$S/removed-source.png" --ui-after 5 --quit-after 6
cat "$S/route.jsonl"
{"error":"","loading":false,"player":"","route":"home","t":0}
{"error":"这个视频所在的来源已被移除","loading":false,"player":"","route":"loading","t":0.9}
```

- 加载页显示提示和「从历史中移除」「返回首页」两个按钮，见 [09-removed-source-history.jpg](Evidence/bug-review-2026-11-27/09-removed-source-history.jpg)。
- 按钮的处理函数复用已有的 `removeRecent`（`PlaybackStore.remove(path:)` + `refreshRecent`）与 `cancelLoading`，两条都有现成的调用方；本轮没有对按钮做自动点击（没有 UI 自动化），只验证了错误分类、文案与按钮出现。

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

### 已采用的修复

修复提交 `8f59139`，两条都做了：

- 第 2 条的全局提示条会让这条警告显示出来（`addSource` 仍然写 `statusMessage`）。
- 更重要的是 `addSource` 现在返回 `SourceAddOutcome(source:warning:)`（[SourceStore.swift](../Sources/OpenFuseData/SourceStore.swift)），弹窗不再靠全局字符串猜结果：`SourceFormStep.step(for:statusMessage:)` 把结果分成「关闭」「原位显示错误」「停留显示警告」三种，[AddSourceSheet](../Sources/OpenFuseApp/BrowserView.swift) 有警告时先显示警告和「知道了」，用户确认后才关闭，提交按钮同时隐藏，避免重复提交。

### 验证结果

- 单测覆盖三种结果（`PlayerRoutePolicyTests` 的 `testSourceFormClosesOnlyWhenNothingNeedsSaying`、`testSourceFormShowsTheFailureInPlace`、`testSourceFormStaysOpenForAKeychainWarning`）。
- **没能实测「Keychain 写入失败」这一步**：本机 Keychain 不对 OpenFuse 拒绝写入。用 `security add-generic-password -T /usr/bin/security` 造出的「只信任 security 命令行」条目，OpenFuse 仍然能更新成功（macOS 27 里这类条目的 ACL 仍允许其它 App 访问），`security lock-keychain` 会要求用户密码、属于会破坏本机会话状态的操作，因此没有采用。所以「警告确实弹出」只做了代码路径 + 单测验证；`--webdav-credential-report` 已把 `addSource` 的 `warning` 写进报告，有拒绝授权的环境时可以直接看 `warning` 字段。

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

### 已采用的修复

修复提交 `8f59139`（**未能在模拟器实测**，原因同第 6 条）：

- [MobileLibraryModel.swift](../Platforms/Mobile/MobileLibraryModel.swift) 的 `addJellyfin` 改为返回 `Bool`（成功才返回 true，失败时把原因写进 `status`）。
- [MobileSourcesView.swift](../Platforms/Mobile/MobileSourcesView.swift) 的 `MobileAddSourceForm` 保存按钮按 WebDAV 那一支的写法处理：成功才 `dismiss()`，失败时 `errorText = model.status ?? "登录失败"`，表单保持打开，`isSaving` 复位。

### 验证情况

- `Scripts/build-ios.sh` 构建通过。
- 没有可启动的 iOS 运行时（`xcrun simctl list runtimes` 为空），因此没能实测。待验证方法：模拟器里「媒体来源 → 添加 Jellyfin → 错误密码 → 保存」应留在表单并显示「添加 Jellyfin 失败：…」；正确密码 → 表单关闭、来源出现在列表。

---

## 本轮验证记录

环境：macOS 27.2（arm64），Xcode 27.2 / iOS SDK 27.2，基线 `fa11eb6`，分支 `fix/bug-review-2026-11-27`。所有 UI 验收都用 `OPENFUSE_SUPPORT_DIR` 指向临时目录，不碰个人数据。

### 单元测试与构建

| 命令 | 结果 |
| --- | --- |
| `swift test` | 179 个用例全部通过（基线 160 + 本轮新增 19，含 `PlayerRoutePolicyTests`） |
| `Scripts/build-app.sh` | `built build/OpenFuse.app` |
| `Scripts/build-ios.sh` | `** BUILD SUCCEEDED **` |

### 脚本验收

`Scripts/run-close-return-route.sh`（本轮新增）：

```
ok   resume played before closing: yes
ok   resume close returns to the home page: home
ok   no loading spinner after resume close: false
ok   local file played before closing: yes
ok   local close returns to the home page: home
ok   cancel: the loading page was really shown: yes
ok   cancel during loading returns to the home page: home
ok   failed resume shows the loading page: yes
ok   failed resume stays on the loading page: loading
ok   failed resume: error message kept after 重试: 网络错误：无法连接服务器。
PASS: resume close, local close, cancel during loading, retry after failure
```

`Scripts/run-episode-switch-pause.sh`：`PASS: right-click / space / volume keys follow episode switches`。

`Scripts/run-webdav-browser.sh`：`PASS: WebDAV deep path browsed with a single canonical listing request (/dav/Shows/Season%201/)`。

`Scripts/run-player-interactions.sh`（本轮修掉了它的一个环境依赖，全屏那一项在本机是既有问题，见下节）：

```
ok   arrow keys change in-app volume: 95
ok   mpv volume follows: 95.000000
ok   right click toggles in video: True
ok   pause in video recorded as user intent: True
ok   right click toggles in letterbox: True
ok   right click toggles in controlbar: True
ok   two right clicks resume: False
ok   right click toggles in fullscreen: True
ok   fullscreen window was used: True
ok   pause during buffering is kept after recovery: True
ok   buffering pause recorded as user intent: True
ok   buffering finished while staying paused: False
PASS: volume keys, right-click regions/fullscreen, buffered pause
```

### 脚本会碰到的窗口与应用设置

- 三个既有脚本都会启动 `build/OpenFuse.app` 的窗口，并用 AppleScript / System Events 发送真实按键和鼠标事件（`run-player-interactions.sh` 还会 `defaults write com.openfuse.app openfuse.player.volume`）；这需要辅助功能权限，运行时不要同时操作鼠标键盘。
- 新增的 `run-close-return-route.sh` 不用 AppleScript、不写 `defaults`、不发合成事件：截图来自应用自身 `captureUI`（不需要屏幕录制权限），断言来自 `--route-log`，全部状态都在 `build/close-return-route/` 下的一次性数据目录里。

### `run-player-interactions.sh` 的两处环境问题

1. **缺夹具**：它的「pause during buffering」一段直接从 `build/cache-features/root` 取流，而这个目录只有在跑过 `Scripts/run-cache-features.sh` 之后才存在。本轮给它加了兜底：目录不存在时用同一条 ffmpeg 命令生成 `Shows/fast.mp4`（与 `run-cache-features.sh` 完全一致），此后这一段通过。
2. **全屏那一项在本机是既有失败**：`right click toggles in fullscreen` 在基线 `fa11eb6` 上同样失败（新建 worktree、干净构建基线后单独跑该项，3/3 失败）。原因是在 2560x1440 上进入全屏 Space 的动画超过脚本给的 4 秒，合成点击落在桌面 Space 被丢弃；把等待拉到 6 秒并在点击前先把光标移进视频区后，该项在本轮构建上连续两次通过（基线同样操作 2/3 通过）。因此本轮只调整了脚本的等待与光标预热，没有改播放器的输入处理，也没有放宽断言。

### 截图证据

都在 `Docs/Evidence/bug-review-2026-11-27/`：

- `01-resume-close-returns-home.jpg`（第 1 条：续播后关闭回到首页）
- `02-local-close-returns-home.jpg`（第 1 条：本地文件关闭回到首页）
- `03-cancel-during-loading.jpg`、`04-retry-keeps-error-page.jpg`（第 1 条：加载中取消 / 失败后重试）
- `05-webdav-play-failure-toast-and-banner.jpg`（第 2 条：顶部提示条 + 页内失败原因）
- `06-jellyfin-play-failure-toast.jpg`（第 2 条：Jellyfin 播放失败的提示条）
- `07-missing-credential-page.jpg`、`08-prefilled-password-form.jpg`（第 3 条：需要输入密码 / 预填表单）
- `09-removed-source-history.jpg`（第 7 条：来源被移除提示与「从历史中移除」）

原始 PNG 与命令日志在 `build/bug-review-2026-11-27/`（`build/` 不入库）。

### 本轮没能验证的部分

| 项 | 原因 |
| --- | --- |
| 第 6 条 iOS 全屏播放（改动前后） | 本机没有可启动的 iOS 运行时：`xcrun simctl list runtimes` 为空，所有设备报 `runtime profile not found`，`simctl boot` 报 `Invalid device`。只验证了 `build-ios.sh` 能构建。 |
| 第 9 条 iOS 添加 Jellyfin 失败留在表单 | 同上。 |
| 第 8 条「Keychain 写入失败时弹出警告」 | 本机 Keychain 不对 OpenFuse 拒绝写入，无法制造真实的写入失败；没有采用锁定登录钥匙串这类会破坏本机会话状态的做法。改为单测 + 返回值路径验证。 |
| 第 2 条提示条里「重试」按钮的 Keychain 授权分支 | 同上，无法制造 `needsAuthorization`。 |
| 第 3 条表单提交的按钮点击 | 用 `--webdav-credential-report` 走同一份提交逻辑验证（报告里 `submit: ok` + `secondLoad: ok`），没有做按钮的合成点击。 |
| 第 7 条「从历史中移除」按钮点击 | 只验证了提示与按钮出现；处理函数复用已有的 `removeRecent` / `cancelLoading`。 |
| 第 1 条「WebDAV 目录/Jellyfin 详情页播放后关闭回到原处」 | 脚本用加载中取消 / 失败后重试覆盖了 `.loading` 的进出；返回原处依赖 `playerReturnRoute` 记录 `.browser` / `.jellyfinBrowser`，由代码路径与 `run-webdav-browser.sh` 的层级断言间接覆盖。 |
