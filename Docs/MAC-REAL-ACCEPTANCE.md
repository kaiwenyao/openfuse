# macOS 真实媒体库验收：WebDAV 与 Jellyfin

日期：2026-11-20。范围仅 macOS 客户端，基线提交 `e4659b8`，本轮改动见 `git log -1`。

产物：

| 产物 | 路径 |
| --- | --- |
| 应用 | `build/OpenFuse.app` |
| 自包含 zip | `build/OpenFuse-macOS-self-contained.zip`（27 MB） |
| 构建 / 打包 | `Scripts/build-app.sh` / `Scripts/package-app.sh` |
| 单测 | `swift test` → `Executed 51 tests, with 0 failures` |

```bash
Scripts/build-app.sh
open build/OpenFuse.app
Scripts/package-app.sh
swift test
```

## 1. 凭据：Keychain 为唯一持久后端，另有仅会话模式

`CredentialStore`（`Sources/OpenFuseData/Credentials.swift`）本轮重写：

- `save` 默认写入登录 Keychain，写后立刻读回校验；**任何情况下都不再写明文文件**。写入失败时把密码留在进程内存里并抛出错误，来源在本次运行内仍可用。
- 仅会话模式：环境变量 `OPENFUSE_CREDENTIAL_MODE=session`，或添加来源面板里的开关「仅本次会话（不写入 Keychain）」。该模式只在内存保存，退出即失效，磁盘上不留任何副本。
- 旧版明文 `~/Library/Application Support/OpenFuse/credentials.json` 的迁移：逐条写入 Keychain → 读回比对 → 只有校验通过才删除对应旧条目；全部迁完才删除文件；失败的条目原样保留并计数。启动时自动执行，`credentialMigrationSummary` 会显示结果。
- 阻塞式 Keychain 弹窗：读写默认在 `SecKeychainSetUserInteractionAllowed(false)` 下进行。旧构建留下的条目属于另一个 cdhash，读取会要求授权；现在这种读取会快速失败并提示「Keychain 需要授权访问此来源的凭据：请在系统弹窗中允许 OpenFuse，然后再次操作」，用户下一次操作才走带弹窗的交互读取，不会再让应用启动时卡死。

### 假凭据的窗口级验证（Keychain 模式）

本机 `127.0.0.1:8103` 起 `Tools/webdav_fixture.py`（用户 `fake`，密码为一次性假密码）：

1. 从 Finder 启动 → 「添加来源」→ 填名称/地址/用户名/密码，**不勾**「仅本次会话」→「连接并保存」。
2. 保存后：`security find-generic-password -s com.openfuse.webdav -a 10b2292b1d7d56ad` 返回条目（服务名 `com.openfuse.webdav`，账号为来源 id）；support 目录只有 `sources.json`/`library.sqlite*`，**没有 `credentials.json`**。
3. 退出应用（⌘Q），重新从 Finder 启动；来源卡片仍在，点「浏览」直接列出 `Movies`/`Shows`，没有再输入密码 —— 说明重开时确实从 Keychain 取到了密码。
4. 删除来源（卡片垃圾桶）后 `security find-generic-password …` 返回 `44`（条目不存在），`sources.json` 为空。

单元测试 `CredentialStoreTests`（6 项）覆盖 Keychain 往返、覆盖写、仅会话不落盘/不写 Keychain、迁移后删除明文文件、坏文件不动。登录钥匙串被系统锁定时这 3 个 Keychain 用例以明确原因 skip（`XCTSkip`），解锁后全过；本轮最终运行为 51/51 全过。

已知限制：ad-hoc 签名的应用每次重建都会更换 cdhash，旧 Keychain 条目的读取需要用户在弹窗里点一次「始终允许」。正式签名（Developer ID）不存在这个问题。

## 2. WebDAV 真实媒体库

通过正常界面添加：`https://ol.7miaozhong.top/dav/`，用户 `admin`，勾选「仅本次会话」。根目录 → `local/kaiwenyao/baidu/电视剧/Attack on Titan (2013)/Season 03`。

《进击的巨人》S03E13（`Shingeki no Kyojin - S03E13 - The Town Where Everything Began.mkv`，235.1 MB）：

| 项目 | 结果 |
| --- | --- |
| 视频 | HEVC Main 10，`hwdec-current=videotoolbox` |
| 音频 | 唯一音轨 AAC 2.0（日语） |
| 字幕 | 外挂 `zh-Hans.ass`、`zh-Hant.ass`，另有内嵌 English ASS |
| 默认选轨 | 中文（简体）(ASS) |
| 切轨 | 菜单「播放 → 字幕 → 中文（繁體）(ASS)」生效，报告 `selectedSubtitle=…zh-Hant.ass` |
| 45 s | 画面「將它們那巨大的頭顱踩在了地上」，与 ASS 第 45 s 的 cue 完全一致，繁体字形正确、无方框 |
| 303 s | 「什麼 我到底在怕什麼」，与 ASS cue 一致 |
| 1200 s | 「那麼 如果拿回了瑪利亞之牆」，与 ASS cue 一致 |
| 拖动 | 跳转 1:00 / 5:00 / 20:00 后 1–2 s 内出画，位置与字幕同步 |
| 退出 | 菜单「播放 → 返回来源」后停在 `… / Season 03` 的文件列表，不回首页 |
| 继续观看 | 卡片显示 `20:12 / 23:57`；打开后从 20:20 继续，仍选中繁體 |

证据：`Docs/Evidence/mac-real/05-webdav-season3-after-return.jpg`、`06-webdav-zh-hant-45s.jpg`、`07-webdav-zh-hant-303s.jpg`、`08-webdav-zh-hant-1200s.jpg`、`09-home-continue.jpg`。

## 3. Jellyfin 真实服务器

通过正常界面添加：`https://jellyfin.kaiwen.dev`，用户 `root`，勾选「仅本次会话」。库：`百度网盘电视剧`、`百度网盘电影`、`文件夹`。

- 电视剧：`百度网盘电视剧 → 进击的巨人 → 第 3 季 → S03E13 初始的街道`，详情页 →「播放」。直连（Direct）播放同一 MKV：HEVC Main 10、AAC 2.0、外挂简体/繁體 ASS + 内嵌英文 ASS，默认简体，切繁體后 305 s 画面与 ASS cue 一致。
- 退出：回到 `第 3 季` 的剧集网格，不回首页。
- 进度回写：播放前服务器 `UserData.PlaybackPositionTicks=0, Played=false`；退出后为 `3264930000`（5:26），`Played=false`，`LastPlayedDate` 更新。验收结束后用 `POST /Users/{uid}/Items/{id}/UserData` 恢复为 `0 / 未看`，原有观看记录未被改动。
- 继续观看：首页卡片显示 `初始的街道 05:12 / 23:57`；点开后从 322.9 s 继续，并保持繁體字幕（`jellyfin-sub:…:1`）。随后再次把服务器进度恢复为 `0 / 未看`。
- 电影库：`百度网盘电影 → 海边的曼彻斯特` 详情页正常打开（封面、标题、年份、播放按钮）。

证据：`01-jellyfin-libraries.jpg`、`02-jellyfin-season3.jpg`、`03-jellyfin-movie-detail.jpg`、`04-jellyfin-zh-hant-305s.jpg`。

## 4. 《性爱自修室》S01E01：HEVC Main 10 + 唯一 E-AC-3 5.1

WebDAV `…/电视剧/Sex Education (2019)/Season 01/Sex Education (2019) - S01E01 - Episode 1 (1080p NF WEBRip x265 t3nzin).mkv`：

- 视频：HEVC Main 10（`H.265 / HEVC`），VideoToolbox 硬解。
- 音频：**唯一**音轨 E-AC-3 5.1（English），mpv 解码为 `5.1(side)` 48 kHz。
- 本机输出：`MacBook Pro Speakers`（内置，2 声道，48 kHz）是系统默认输出；`current-ao=coreaudio`，输出参数为 `stereo`，即 5.1 被下混为立体声。没有外接多声道设备，因此无法在本机验证 5.1 直通。
- 外挂 `…chs.ass` 出现在字幕列表（另有 29 条内嵌字幕）。

## 5. 与 Infuse 8.5.10 的对照

**本机没有安装 Infuse**：`/Applications`、`~/Applications`、`mdfind -name Infuse`、按 bundle id 的 Spotlight 查询均为空。因此以下对照项无法执行，列为待验证：

- 默认选轨（简/繁 ASS、音轨）与 OpenFuse 是否一致；
- 拖动后的恢复耗时与字幕同步；
- 退出后返回的位置（原目录/原季）；
- 续播位置与字幕选择；
- Pro 权益挡住的具体项目。

OpenFuse 自身的上述行为已在第 2、3 节用真实媒体逐项记录。

## 6. 哪些是从窗口里亲手完成的

窗口内完成（用 macOS 辅助功能驱动真实控件，等价于点按）：

- 从 Finder 启动 `build/OpenFuse.app`；
- 添加两个来源（含「仅本次会话」开关）与假凭据的添加/重开/删除；
- 逐级浏览 WebDAV 目录、打开 Jellyfin 库/剧/季/集与电影详情；
- 播放、切字幕（菜单栏「播放 → 字幕」）、跳转时间（「播放 → 跳转到时间…」）、返回来源、从「继续观看」打开。

未能用自动化确认、需要真人点一次：

- 播放器窗口内的控制栏（播放/暂停、进度条、字幕下拉按钮）。系统合成点击在标题栏按钮和列表行上都正常，唯独播放器浮层不响应；已把 mpv 的 `MPVGLView.hitTest` 改为返回 `nil`（避免 GL 视图拦截鼠标），并新增菜单栏「播放」菜单作为等价入口（暂停/快退快进/字幕/音轨/音频输出/跳转/返回）。控制栏的真实鼠标点击仍待人工确认。

## 7. 已知问题与建议

1. 播放器内嵌控制栏的鼠标点击待人工确认（见上）。
2. ad-hoc 重建后 Keychain 旧条目需要一次授权弹窗；正式签名不受影响。
3. 若把 `OPENFUSE_SUPPORT_DIR` 指到 iCloud/Documents 下的目录，SQLite 初始化偶发卡在 `unixSync/openDirectory`；默认目录（`~/Library/Application Support/OpenFuse`）与 `/tmp` 均正常。本轮验收使用 `/tmp` 下的隔离目录，避免污染用户数据。

## 8. 复现步骤摘要

```bash
# 构建与单测
Scripts/build-app.sh && swift test

# 假凭据 Keychain 测试（本地 fixture）
python3 Tools/webdav_fixture.py --setup --port 8103 --user fake --password '<一次性假密码>'
open build/OpenFuse.app      # 添加来源 → 不勾“仅本次会话” → 退出重开 → 浏览 → 删除

# 真实来源（仅会话凭据）
launchctl setenv OPENFUSE_CREDENTIAL_MODE session
open build/OpenFuse.app      # 添加 WebDAV / Jellyfin，勾选“仅本次会话”
```

窗口内的验收辅助入口：菜单栏「验收 → 保存当前画面与播放报告 / 保存界面截图」，输出写到 `<support>/Acceptance/`，不会进入仓库，也不包含密码或令牌。
