# OpenFuse Mac 实现说明（M1）

## 目标与边界

当前只做 Mac 本地文件播放。媒体库、远程来源、设置页尚未接入，接口位置在下面标出。所有播放验收以 `Fixtures/generated/openfuse-fixture.mkv` 为准。

## 目录

```
Package.swift
Sources/
  CMpv/                 libmpv C 模块（systemLibrary）
  OpenFuseCore/         模型、字幕发现、续播存储、libmpv 封装、OpenGL 视图
  OpenFuseApp/          SwiftUI 应用、首页、播放器、测试参数
  openfuse-probe/       无窗口探针，AVPlayer / libmpv 对照
Tests/OpenFuseCoreTests 字幕发现、语言标签、续播策略
Scripts/
  make_fixtures.sh      生成并校验测试片
  build-app.sh          组装 build/OpenFuse.app
  Info.plist
Tools/
  gen_frames.swift      逐帧生成时间码画面
  gen_audio.py          生成 6 声道报号
  gen_subtitles.py      生成简繁/无标签/缺字体 ASS
  analyze_audio.py      Goertzel 声道校验
  window_capture.swift  列出窗口 ID（截图受系统权限限制）
Docs/                   决策、素材、验收、证据
```

## 数据与会话

- `MediaFingerprint`：路径 + 大小 + mtime；路径作为续播键，替换文件仍保留进度。
- `SubtitleCatalog`：发现同主名和 `Subs/` 下的字幕，解析 `zh-Hans`/`zh-Hant`/`zh_TW`/`jpn` 等标记，拒绝不匹配主名或含未知段的文件。
- `PlaybackStore`：`~/Library/Application Support/OpenFuse/playback.json`，原子写入，按路径保存位置、时长、已看状态、音轨/字幕偏好。`ResumePolicy`：小于 5 s 不续播、距结尾 10 s 内不续播、95% 记为已看。
- `PlayerModel`：一次播放会话。负责选轨、保存、关闭；`MPVEngine` 只做 mpv 生命周期与命令。

## 播放启动顺序（关键）

1. SwiftUI 创建 `PlayerView` → `MPVGLView`。
2. `prepareOpenGL` 建立 GL 上下文并调用 `mpv_render_context_create`，成功后通知引擎。
3. `PlayerModel` 只有拿到 render context 才 `loadfile`。否则 mpv 会永久报 `vo/libmpv: No render context set.`，表现为黑屏、只有声音。
4. 文件加载后添加外挂字幕，刷新轨道，延迟约 1–2 s 等所有外挂轨就绪，再应用保存的轨道或 `zh-Hans` 默认。
5. 退出时保存位置并销毁 render context / mpv handle；下次打开由 `ResumePolicy` 决定起播点。

渲染由 `MPVGLView.draw` 驱动：mpv render API 输出到默认 FBO，`flushBuffer` 上交。测试抓帧在同一 `draw` 中 `glReadPixels`，因此反映真实输出而非外部抽帧。

## 线程

- mpv 事件循环在独立串行队列，`mpv_wait_event` 200 ms 超时。
- 属性变化通过 `DispatchQueue.main` 回到 UI；`time-pos` 限流 20 Hz。
- 命令加锁；`shutdown` 等待事件线程退出后再销毁 handle。
- Swift 5 语言模式以减少 C 回调与旧 AppKit 的迁移噪声；后续可评估 Swift 6 严格并发。

## 媒体库（M3a 已实现）

- `LibraryStore`（SQLite/WAL）：works/seasons/episodes/versions；按 `source_kind + source_id` 整源替换，事务写入，其他来源不受影响。
- `LibraryScanner`：
  - 本地：递归枚举、文件名解析（`Movie (2026)`、`SxxEyy`、`1x02`、`第N季第M集`）、同目录/父目录海报发现、按剧名分组。
  - WebDAV：递归 PROPFIND、目录海报映射、远程路径与同名字幕。
  - Jellyfin：`Recursive=true` 拉取 Movie/Series/Season/Episode；电影额外取 PlaybackInfo 保存多版本。
- `LibraryGroup`：UI/AppModel 按 `kind + 规范化标题` 合并跨来源作品，优先级 Jellyfin > 本地 > WebDAV；详情用来源胶囊切换，原始行不删除。
- `LibraryView`：海报网格、搜索、扫描菜单、电影/剧详情、季选择、集列表、版本 Picker、从库播放。
- 海报引用：`jellyfin:<itemID>|<tag>`、`file:<path>`、`remote:<url>`（WebDAV 远程海报暂未加认证加载器）。

**待做：** TMDB/NFO、集级跨源版本合并、增量扫描/取消、手工纠错、最近添加/继续观看排序、T07 压测。

## Jellyfin 外挂字幕（M4n）

- 夹具 MediaStreams 增加 `IsExternal=true` + DeliveryUrl SRT。
- `remotePlaybackItem` 对每个外挂流带 X-Emby-Token/MediaBrowser 下载到 SubtitleCache，生成 `SubtitleTrack(.downloaded)`；自绘菜单/解析复用。
- 实测 movie-1 HLS HUD 4.7/60.0 显示第一句；自动播放时序仍脆弱。
- 未做：繁体 DeliveryUrl、音频听测、真实 Jellyfin。

## 远程精确 seek（M4m）

- `preciseSeek`：AVPlayer.seek(to:toleranceBefore:.zero,toleranceAfter:.zero, completionHandler) 包装为 async，返回 finished。
- seek 前暂停，完成后等待 300ms；ticker 重新计算字幕 cue。
- WebDAV 远程 seek 10s 实测 HUD 10.0/20.0，第二句字幕同步。
- Jellyfin DeliveryUrl 外挂字幕下载到 `SubtitleCache`；画面待验证。

## 远程 WebDAV 字幕画面修复（M4l）

- 时长从 `player.currentItem.asset`（认证 loader asset）读取，避免新建无认证 AVURLAsset 得到 0。
- `waitUntilReady` 再播放/seek；seek 后 500ms 再暂停。
- `OPENFUSE_AUTOPLAY_PAUSE_AT`：ticker 播放时间跨过 N 秒自动暂停，用于字幕截图。
- 实测远程 HUD 4.6/20.0s 显示第一句字幕；远程 seek 同步仍不稳。

## WebDAV 远程字幕（M4k）

- `playbackItemAsync`：WebDAV 播放前列视频目录，`WebDAVClient.subtitleTracks` 匹配同名字幕，Basic Auth GET 下载到 `SubtitleCache`，转换成 `SubtitleTrack(.downloaded)`。
- 详情/autoplay 改为异步获取播放条目；字幕菜单/解析与本地共用。
- 已验证下载/选择；远程画面因 AVPlayer 时间跳变未截到 cue，待修。

## 跨设备进度同步（M4p）

- `PlaybackStore.merge(records:)`：新 `lastPlayedAt` 优先；JSON 日期改为带毫秒 ISO8601。
- `ProgressSyncTransport`：`LocalProgressTransport`（共享文件，验收）/ `CloudKitProgressTransport`（私有库 `PlaybackProgress` CKRecord）。
- `ProgressSyncService`：拉取 → 合并 → 推送；App `--sync-progress` + env 配置。
- 两 support 目录实测 A 9.917s → B 14.417s；真实 CloudKit 需 entitlements/账号，未验证。
- 未做自动同步/离线队列/Trakt/移动端同步 UI。

## Vision Pro 实际运行（M4o）

- visionOS 27.2 runtime；`OpenFuseVision` target 以 `NavigationSplitView` 侧栏/详情启动。
- `OPENFUSE_AUTOPLAY=1` 自动选择首部作品并打开 `VisionPlayerView` sheet。
- 空间窗口与 HEVC/EAC3 播放实测；沉浸式影院/空间音频/手势未做。
- 五端（Mac/iPhone/iPad/tvOS/visionOS）均已有实际启动证据。

## 移动端字幕自绘（M4j）

- `SubtitleParser`：SRT/VTT/ASS/SSA → cues；去 HTML/ASS 标签、`\N` 换行。
- 本地播放条目用 `SubtitleCatalog` 发现侧载；seed 复制简/繁 SRT。
- `MobilePlayerView`：0.25s Timer 读取当前时间并选 cue，SwiftUI 叠加字幕（系统字体 fallback）；菜单关闭/简体/繁體；测试钩子 seek/pause。
- 与 mov_text 原生轨道二选一（侧载优先）；ASS 定位/样式仍由 Mac libass 提供。
- 未做：远程侧载字幕、ASS 样式、音频听测、visionOS runtime。

## 移动端音轨/字幕轨道（M4i）

- 新 `openfuse-mobile.mp4`：HEVC Main10 + E-AC-3 5.1 + AAC + 简繁 mov_text，20.1s。
- `MobilePlayerView` 用 AVMediaSelectionGroup 枚举 audible/legible；过滤 forced 字幕；菜单选择音轨/字幕；HUD 测试显示当前选择。
- tvOS 27.2 runtime 实际启动 Apple TV 模拟器；`TVRootView` 焦点网格 + autoplay 全屏播放。
- 未确认：字幕文字实际渲染、音频输出、visionOS runtime。

## 流分辨率探测（M3k）

- WebDAV MP4/M4V/MOV：`AuthenticatedAssetLoader` + AVAsset video track naturalSize；MKV 跳过。
- Jellyfin episode：扫描时 `playbackInfo(itemID:)` 取 MediaStreams Video Height；每集一次请求。
- 结果写入版本 resolution；画质筛选覆盖 Jellyfin 剧集/WebDAV MP4。
- 未做：WebDAV MKV、并发/缓存、HDR 标记。

## 本地分辨率探测（M3j）

- MP4：`AVURLAsset` naturalSize/preferredTransform（visionOS 不同步支持，跳过）。
- MKV：Mac `MediaProbe` 调 ffprobe（>1MB 才探测），写回 ScannedVersion.resolution；空文件/10k 压力不触发。
- Jellyfin 电影用 MediaSource height；WebDAV/Jellyfin 单集仍缺。
- 画质筛选 1080p 现覆盖本地电影/剧集。

## iOS 远程播放实测（M4h）

- 测试来源注入：`OPENFUSE_TEST_WEBDAV_*` / `OPENFUSE_TEST_JELLYFIN_*` 环境变量；启动后自动添加/扫描。
- 自动选组：`OPENFUSE_AUTOPLAY_SOURCE=webdav|jellyfin`、`OPENFUSE_AUTOPLAY_TITLE=...`；WebDAV 走认证 loader，Jellyfin 走 PlaybackInfo+token（MP4 直连/HLS）。
- 模拟器实测 WebDAV 7.0/20s、Jellyfin 8.0/20s；音频未听测，HLS 60s 移动截图未取得。
- 测试环境变量含明文密码，仅本地模拟器；生产仍 UI/Keychain。

## iOS 实际运行与续播（M4g）

- iOS 27.2 Simulator 实际安装/启动；iPhone 单栏、iPad 常规宽度 NavigationSplitView。
- 本地 `fileURL` 是 `file://` 字符串，移动端先 `URL(string:)` 再回退 `fileURLWithPath`；此前导致 `playbackItem=nil`。
- 测试钩子：`OPENFUSE_AUTOPLAY=1` 启动即播，`OPENFUSE_AUTOPLAY_STOP_AFTER=N` 自动保存/关闭；HUD 仅钩子显示。
- 实测播放 3.0/20s、保存 4.795s、重启续播 12.0/20s；音频/字幕未验证。
- tvOS/visionOS runtime 未安装，仍为构建验证。

## WebDAV 目录超时恢复（M3i）

- `ScannedLibrary.failedPaths` 记录 PROPFIND 失败目录；scanner 继续其他目录。
- `LibraryStore.replace(preservingRemotePrefixes:)` 保留 remote_path 落在失败前缀下的旧 works，其余刷新；全部失败等价保留整源。
- AppModel 状态显示「N 个目录失败，已保留旧条目」；夹具 `--fail-path` 注入 504。
- 仅目录级；无重试/退避，Jellyfin/本地无等价恢复，扫描中播放未测。

## Jellyfin HLS 转码（M4f）

- `JellyfinClient.hlsURL`：构造 `master.m3u8` + H.264/AAC/TS + api_key/DeviceId。
- 移动端选择：MP4/MOV 直连 + 认证 loader；其他容器走 HLS；续播键统一。
- 夹具从 MKV 预生成 HLS（ffmpeg），Jellyfin 夹具提供带 token 播放列表与无 token 分片；AVPlayer 60s/5.954s 实测。
- 真实 Jellyfin 转码 profile/HTTPS/PlaySessionId 与字幕/音轨未验证。

## Jellyfin 移动端远程播放（M4e）

- `MobileLibraryModel.remotePlaybackItem`：Keychain token → PlaybackInfo → 优先匹配版本 mediaSourceID → streamURL + api_key → `jellyfin://source/item/mediaSource` 续播键；loader 带 `X-Emby-Token`/MediaBrowser Authorization。
- iPhone/iPad 详情「播放服务器版本」异步获取；失败提示 MKV/HEVC 需转码/libmpv。
- 夹具 `jellyfin_fixture.py --mobile-sample` 增加 MP4 movie-mobile；测试 auth→PlaybackInfo→token URL→loader→AVPlayer 6s 5.866s。
- 未做：Jellyfin HLS 转码、MKV/libmpv、字幕/音轨、tvOS/visionOS 调用该路径。

## 认证资源加载与移动端远程播放（M4d）

- `AuthenticatedAssetLoader`（OpenFuseData）：`openfuse-auth://` 自定义 scheme + AVAssetResourceLoader；HEAD 取长度/类型/Accept-Ranges，GET 带 Range 与 Authorization/X-Emby-Token，处理 206/200、偏移与取消。
- 移动端 WebDAV 条目：Keychain 取密码，构造 Basic 头与 `webdav://source/path` 续播键；`makePlayer` 用 loader 创建 AVPlayerItem。本地文件仍直接 AVPlayer。
- 桌面 probe 实测 AVAsset 20s/1280×720、AVPlayer 3.6s；错误密码失败。
- 未做：Jellyfin 远程/HLS、MKV/libmpv、字幕/音轨、移动 runtime 实机验证。

## iPad 分栏与 tvOS/visionOS（M4c）

- iPad 常规宽度：`NavigationSplitView`（侧栏媒体库列表 + 详情），iPhone compact 仍 NavigationStack。
- tvOS：`OpenFuseTV` target，`TVRootView` 焦点网格 `.buttonStyle(.card)`，`TVPlayerView` AVPlayer + 续播。
- visionOS：`OpenFuseVision` target，`NavigationSplitView` 侧栏/详情 + 播放 sheet，默认窗口 1100×760。
- 三端共享 `MobileLibraryModel` 与示例 MP4；tvOS/visionOS 未包含服务器来源 UI。
- 生成工程由 `project.yml` 管理，`Scripts/build-platforms.sh` 构建三端。

## 观看状态、最近播放与防剧透（M3h）

- `AppModel.watchState(for:)`：按季/集聚合组内来源，匹配本地路径、`webdav://source/path`、`jellyfin://source/item/mediaSource` 记录；全看完=已看、有进度=观看中。
- `LibrarySort.recentlyPlayed`：组内最大 `lastPlayedAt` 降序。
- `LibraryWatchFilter` / `LibraryResolutionFilter`：全部/未看/观看中/已看；4K/1080p/720p。分辨率来自版本 `resolution` 或名称；Jellyfin 电影写高度，其他来源暂缺。
- `@AppStorage("openfuse.spoilerProtection")`：详情/单集简介隐藏，点「显示」临时展开。
- 合并键规范化增加 `·` 后缀剥离，修复 WebDAV NFO 标题导致的重复组。

## 跨平台分层（M4a）

- `OpenFuseData`（SwiftPM library）：媒体/库模型、SQLite、扫描、WebDAV、Jellyfin、TMDB/NFO、覆盖、播放记录、凭据、聚合；Foundation/Security/sqlite3，无 AppKit/mpv，可编 iOS/tvOS/visionOS。
- `OpenFuseCore`：macOS 播放层（libmpv/OpenGL），`@_exported import OpenFuseData` 保持旧 import。
- `Platforms/Mobile` + `project.yml`：iPhone/iPad SwiftUI；AVPlayer 本地 MP4/MOV、Files 导入、PlaybackStore 续播；示例 MP4 首次启动入库。
- 生成 `OpenFuseMobile.xcodeproj`（不入库），`Scripts/build-ios.sh` 重建。
- M4b：移动端 `MobileSourcesView` 添加/扫描/删除 WebDAV/Jellyfin；`SourceStore`/`JellyfinSourceStore` + Keychain；Jellyfin 海报按 token 生成；扫描复用 LibraryScanner。
- 未做：移动端远程播放（转码/HLS/鉴权代理）、字幕/音轨/MKV、iPad 分栏、tvOS/visionOS、CloudKit/Trakt。

## 排序、筛选与最近添加（M3g）

- `ScannedWork.addedAt`：本地 mtime、WebDAV modifiedAt、Jellyfin DateCreated；LibraryStore 写入 `added_at`。
- `AppModel.visibleLibraryGroups`：类型筛选 → 搜索 → 排序（title/year/added/episodes），UI 与验收报告共用。
- 首页媒体库 Picker/Menu：全部/电影/剧集、标题/年份/最近添加/集数、搜索框。
- 未做：防剧透、观看状态/分辨率筛选、继续观看专用排序。

## WebDAV NFO 与海报缓存（M3f）

- 扫描时对远程 `.nfo` 发带凭据 GET，`NFOReader.parse(data:baseURL:)` 保留 `posterReference`；movie/tvshow/episode 三种作用域。
- 海报优先级：NFO poster > 同目录/剧集目录 poster/folder/cover；通过 `WebDAVClient.fetch` 下载到 `PosterCache/`（路径哈希命名），库中保存 `file:`；失败回退 `remote:`。
- NFO 完整作品跳过 TMDB；单集 NFO 的标题/简介覆盖文件名解析。
- 缓存未按 ETag 失效，删除来源不清缓存；真实 OpenList 待验证。

## 手动合并/拆分与 TMDB 候选（M3e）

- `LibraryOverride.mergeGroupID`：作品加入指定分组键，或 `split:<id>` 强制独立；`library-overrides.json` 持久化，扫描替换来源后仍生效。
- AppModel 分组使用 `mergeGroupID ?? 启发式键`；合并只允许同类型（电影/剧集），UI「合并到…」「拆分」「恢复自动」。
- 编辑 sheet 通过 `TMDBClient.candidates` 搜索多条结果，点击填入标题/年份/简介/海报 URL；无 `OPENFUSE_TMDB_API_KEY` 时禁用。
- 待做：WebDAV NFO/认证海报、最近添加排序、筛选/防剧透、T07 扫描中播放/超时。

## 手动纠错与可取消扫描（M3d）

- `LibraryOverrideStore`（`library-overrides.json`）：按 work id 保存 title/year/overview/poster；读取库后 `apply(to:)` 合并，扫描替换来源不影响覆盖；详情「编辑信息」sheet 保存/清除。
- 海报输入归一化：URL → `remote:`，本地路径 → `file:`，前缀保留。
- `ScanCancellationToken`：本地/WebDAV/Jellyfin 扫描检查取消；取消后不替换 SQLite，旧库保持；`scanProgress` 显示已处理条目，UI 提供取消按钮。
- 压力脚本生成 10,000 空文件；扫描上限提高到 20,000 个媒体文件（目录不计数）。
- 未做：手动合并/拆分、TMDB 候选、WebDAV NFO/认证海报、最近添加排序、扫描中播放/超时恢复。

## 集级版本合并（M3c）

- `LibraryAggregation.mergedEpisodes(group:store:)`：按 `(season, episode)` 合并组内各来源；同一集收集 `versions`，生成 `MergedLibraryEpisode`/`MergedLibraryVersion`。
- 电影映射为 season 0 / episode 1，与剧集共用版本逻辑。
- `LibraryDetailView`：电影版本 Picker（来源 · 版本名），剧集每集「N 个版本」菜单；选择后 `playMergedVersion` 调用原来源播放链路。
- 续播键仍按来源/条目/版本保存，切版本不串进度。
- 合并键仍为类型 + 规范化标题（去年份/去冒号副标题），待 TMDB id/手动匹配替代。

## 元数据（M3b）

- `TMDBClient`（actor）：`/3/search/movie|tv`，标题+年份查询，进程内缓存；`OPENFUSE_TMDB_API_KEY/BASE_URL/IMAGE_BASE` 配置；无 key 时完全离线。
- `LibraryMetadata.enrich`：本地/WebDAV 扫描后逐作品匹配；Jellyfin 与 NFO 完整作品跳过；写入 TMDB 标题、年份、简介、`remote:` 海报。
- `NFOReader`：本地 `movie.nfo`、`<video>.nfo`、`tvshow.nfo`、单集 NFO；`title/year/plot/poster/thumb`，相对海报路径解析为本地文件；本地优先于 TMDB。
- `PosterRef`：`jellyfin:`、`file:`、`remote:`；UI 分别用 Jellyfin token URL、NSImage、AsyncImage。
- 夹具：`Tools/tmdb_fixture.py`（搜索+海报）、`make_library_fixture.py` 写入 tvshow.nfo。

**待做：** 候选列表/手动 TMDB id、WebDAV NFO 与认证海报缓存、并发/限流/取消、backdrop/演职员/预告片。

## 远程来源（M2 WebDAV 已实现）

- `WebDAVSource`：名称、根 URL、用户名；id 由 URL+用户名哈希；`sources.json` 持久化，密码存 Keychain。
- `WebDAVClient`（actor）：`list(path)` PROPFIND Depth 1、`stat(path)` Depth 0、`fetch(path, range)`；Basic auth；解析 XML 的 `displayname/resourcetype/getcontentlength/getcontenttype/getlastmodified/getetag`；路径按段编码/解码。
- `RemoteEntry`：path、name、url、isDirectory、size、contentType、modifiedAt、etag。
- `WebDAVClient.subtitleTracks(for:siblings:)`：复用本地匹配规则，构造 URL 型 `SubtitleTrack`，id 前缀 `remote:`。
- `MediaItem`：统一本地/远程；远程 fingerprint 键为 `webdav://<sourceID>/<path>`，HTTP 头（Basic）注入 libmpv；`PlaybackRecord` 增加 sourceKind/sourceID/remotePath/remoteURL。
- UI：首页来源卡片 + 添加来源表单；`WebDAVBrowserView` 面包屑/列表/错误重试；打开视频时先取同目录条目再发现字幕。

**安全注意：** 凭据作为 mpv `http-header-fields` 全局注入，跨域 302 时可能被转发。接真实 OpenList 前需改成本机代理，只在 origin 附带 Authorization。Keychain 首次读取可能弹系统授权，自动化用 `OPENFUSE_WEBDAV_PASSWORD` 覆盖。

## Jellyfin Direct（M2b 已实现）

- `JellyfinSource`：名称、根 URL、用户名、userID/serverID；id 为 URL+用户名的哈希；`jellyfin-sources.json` 保存元数据，令牌存 Keychain（`com.openfuse.jellyfin`）。
- `JellyfinClient`（actor）：登录、Views、Items、单条详情、PlaybackInfo、图片 URL、stream URL、Playing/Progress/Stopped 上报。
- `JellyfinItem`/`MediaStream`/`MediaSource`：保留服务器 Id、名称、Type、年份、简介、封面 tag、RunTimeTicks、UserData 位置、版本与轨道。
- `MediaItem.jellyfin`：播放 URL、`jellyfin://<source>/<item>/<mediaSource>` 续播键、`X-Emby-Token` 头、`JellyfinPlaybackContext`（play session、token、runtime、MediaStreams）。
- PlayerModel 将服务器音频/内嵌字幕 `DisplayTitle` 覆盖到 mpv 轨道菜单；上报开始/每 5 s 进度/停止（只发一次）。
- `JellyfinBrowserView`：库→剧→季→集；`JellyfinDetailView`：封面、简介、版本 Picker、播放。

**仍待做：** Library Mode 聚合、外部字幕流、按 MediaStream Index 的严格轨道映射、真实服务器转码/HTTPS/多用户。

## 远程来源接口（后续来源预留）

播放器只依赖 URL 与轨道描述。M2 计划：

```swift
protocol MediaSource {
    var id: String { get }
    func list(path: String) async throws -> [RemoteEntry]
    func stat(path: String) async throws -> RemoteFile
    func openRange(path: String, offset: Int64, length: Int64) async throws -> Data
    func subtitleCandidates(for path: String) async throws -> [RemoteSubtitle]
}
```

WebDAV 需要保留 Unicode/百分号往返，校验 206 与 `Content-Range`，拖动时取消旧预读；Jellyfin 需要 Direct/Library 两种模式、PlaybackInfo 选版本与进度回写。它们都只替换“取流/列目录”，不改变 `PlayerModel` 的轨道与续播逻辑。

## 测试

`swift test` 覆盖纯逻辑；`openfuse-probe` 覆盖引擎；应用内参数（`--open`、`--freeze-at`、`--capture`、`--report`、`--reopen-test`、`--fullscreen`）覆盖端到端。所有报告写到指定路径，便于 CI 收集。

## 待办

M2：WebDAV/OpenList、Jellyfin、Range/缓存/重连、远程字幕、进度回写。
M3：SQLite 库、TMDB、聚合首页、详情、搜索、增量扫描。
M4：CloudKit/Trakt、iPhone/iPad/tvOS。
M5：SMB/Plex/Emby、HDR、投屏、下载、打包与权益。
M6：visionOS 与全矩阵验收。
