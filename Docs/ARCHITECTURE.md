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

## 跨根内容去重（M3p）

- 本地版本 contentKey = SHA-256(size+首尾64KB)，存 versions.content_key。
- versionIdentity 优先 contentKey；跨根同内容版本合并；非全文件哈希，SMB/WebDAV 无指纹。
- 同内容不同标题仍分开。

## 多根本地库（M3o）

- LocalRootStore 持久化 local-roots.json；scanner sourceID 由根路径哈希生成。
- 支持扫描全部/移除根；移除删除该 source 的 works。
- 实测两根共存/移除；跨根内容去重/自动重扫未做。

## SMB MKV 元数据（M5ae）

- SMB scanner 读前 2MB，MatroskaProbe 解析分辨率/HDR；contentKey 不变。
- 实测 1080p/SMB/HDR10；>2MB 头部、MP4、性能未验证。

## 跨来源内容指纹（M5ad）

- ContentFingerprint size+首尾64KB SHA-256；local/WebDAV Range/SMB pread 共用。
- versionIdentity contentKey 单独身份，跨本地/WebDAV/SMB 合并。
- 首尾抽样非全文件哈希；SMB HDR 元数据/远程性能未验证。

## CoreAudio 输出设备选择（M5ac）

- AudioDevices 枚举 UID/名称/输出声道；PlayerModel 菜单与 selectAudioDevice。
- 报告 audioDevice/audioDeviceActive；env OPENFUSE_AUDIO_DEVICE 测试。
- 实测 BuiltInSpeakerDevice/coreaudio/6ch；听测、热插拔、exclusive 未做。

## EDR HDR 直通（M5ab）

- 按 NSScreen EDR 自动 target-colorspace-hint=yes；OPENFUSE_HDR_PASSTHROUGH=0 关闭。
- 报告 screenEDR/targetColorspaceHint/videoOutParams；实测 EDR16、bt.2020/pq/light=display/max-luma1000。
- OpenGL 渲染器无 compute shader/SSBO，HDR peak computation 禁用；测量未做。

## iOS 运行期 MKV 验证（M3r）

- iPhone 18 Pro 模拟器启动后 WebDAV 扫描 HDR MKV；沙盒 SQLite dynamic_range=HDR10/1080p。
- 真机/OpenList/大头部 EBML 未验证。

## 纯 Swift MKV 头部解析（M3q）

- MatroskaProbe 解析 2MB Range EBML：PixelWidth/Height、Colour Transfer/Primaries；截断主元素按可用数据。
- WebDAV iOS 默认使用，macOS OPENFUSE_MKV_HEADER=1 强制；单测/扫描通过。
- 2MB 后 Tracks、畸形 EBML、iOS 运行期扫描未验证。

## E-AC-3 5.1 PCM 验证（M5z）

- 测试模式 OPENFUSE_AO_PCM → ao=pcm/文件/waveheader/5.1；正常 CoreAudio。
- 16s 走查 WAV：48k/6ch/5.1，六路非静音。
- 仅解码验证；扬声器听测、设备路由、downmix 未做。

## 本地损坏文件过滤（M3n）

- MediaProbe ffprobe 返回 playable；过滤损坏版本并移除空 movie/episode/season/work。
- ≤1KB 判损坏；ffprobe 缺失保留；瞬时失败可能误删。
- SMB/WebDAV 损坏过滤未做。

## HDR10 播放/色调映射（M5y）

- MPVEngine tone-mapping=spline、hdr-compute-peak=yes、target-peak=auto。
- 播放报告暴露 primaries/gamma/sig-peak/tone-mapping；实测 bt.2020/pq/sig-peak4.93。
- 仅验证 SDR tone mapping；HDR 直通/真实显示器未验证。

## 远程 HDR 元数据（M5x）

- Jellyfin VideoRange/VideoRangeType → HDR10/HDR10+/HLG/DV/HDR。
- WebDAV ffprobe color_transfer/primaries → HDR10；FileCandidate.dynamicRange 入库。
- 实测 Jellyfin/WebDAV HDR10；实际 HDR 输出/tone mapping 未验证。

## HDR10 元数据（M5w）

- ScannedVersion/LibraryVersion.dynamicRange；SQLite versions.dynamic_range + ALTER。
- MediaProbe ffprobe color_transfer/primaries → HDR10/HLG；UI/报告显示。
- 实测 1080p HDR10；实际 HDR 输出、WebDAV/Jellyfin HDR、DV/HDR10+ 未验证。
- Trakt 初始化改为未配置时不读 Keychain，避免授权弹窗阻塞。

## Trakt 自动轮询（M5v）

- 设备码后 Task 按 interval 轮询 token；pending 继续，成功保存并停止；失败/过期结束。
- 手动检查取消自动任务；设置页关闭取消；测试可跳过 Keychain。
- 夹具实测 1.07s 成功；真实账号/Keychain 未验证。

## Trakt OAuth 设置（M5t）

- SettingsView：Client ID/Secret/API/状态 + 设备码/检查；TraktService.configure。
- 配置 UserDefaults，secret/token Keychain；env 仍为测试覆盖；captureUI 捕获 sheet。
- UI 渲染/协议通过；按钮点击/真实账号/Keychain 签名未验证。

## Trakt 远程历史回填（M4t）

- playbackKeys 生成播放器一致的 fingerprint：jellyfin/emby、webdav、smb、plex、本地。
- Trakt history 匹配后对每个版本键写 finished；Jellyfin 远程 watched 验收。
- WebDAV/SMB/Plex 代码已接未逐一验收；真实账号/Trakt ID 严格匹配未做。

## Trakt 历史导入（M4s）

- TraktClient.history 拉取 movies/shows；AppModel 规范化标题匹配库，按本地 fileURL 标记 finished。
- CLI --sync-trakt/菜单；watched 筛选验证电影+整剧；仅本地、limit100、无分页/ID 严格匹配。
- 真实 Trakt/OAuth UI/远程来源历史未验证。

## Trakt 剧集匹配（M4r）

- TraktQuery(movie/show, season/episode)；AppModel 播放前 prepare；TraktService 使用 prepared query。
- TraktClient scrobble show body 带 episode；夹具 search/show 与剧集断言。
- 实测 示例剧 S01E01 start/stop；真实账号/OAuth UI/历史未做。

## Trakt scrobble（M4q）

- TraktClient：设备码/轮询/搜索/scrobble；TraktService 环境配置，PlayerModel 在加载/保存/结束触发。
- 夹具实测 search/start/stop（99.9%）；仅 movie 搜索，无 OAuth UI/Keychain/历史同步，真实账号未验证。

## Jellyfin/Emby 版本级去重（M5p）

- mergedEpisodes 以 mediaSourceID+name+resolution（回退 remotePath/fileURL/id）合并版本；标签拼接 Jellyfin/Emby。
- 1080p/720p 仍分开；库报告 merged 暴露；单元测试覆盖。
- 真实服务器 ID 形态/跨服务器碰撞/音频轨去重未验证。

## SMB 流并发/SIGPIPE（M5u）

- SMBStreamServer connectionQueue 并发 + 4 连接 semaphore；listener/conn SO_NOSIGPIPE；accept EINTR/退避。
- 两个并发 HTTP Range 与 fixture SHA-256 一致；SMBClient 读仍串行。
- 真实 SMB3/大文件压力/背压未验证。

## SMB 跨季 tvshow NFO/重连（M5o）

- showNFOByDirectory/showPosterByDirectory + showContext 祖先查找；单集/电影 NFO 优先。
- SMBClient.reconnect；扫描 list/fetch、流读取在 STATUS_SHUTDOWN 后重连重试一次。
- 实测 2 作品/3 集、S01E01 NFO 标题、show poster、seek31、无缓存。
- 真实 SMB3/DFS/并发大文件未验证。

## SMB NFO/海报/字幕与句柄复用（M5n）

- SMBClient 按路径缓存 smb2fh，避免每 64KiB open/close。
- Scanner 读取 movie/base/tvshow NFO，缓存 poster/folder/cover；NFO posterReference 解析。
- openSMBItem 匹配同目录字幕、下载 SRT/ASS/VTT 到 SMBSubtitleCache，SubtitleTrack 随 MediaItem.smb。
- 实测标题/海报/字幕/seek31/无整文件缓存；跨季 tvshow NFO 继承/真实 SMB3 未验证。

## SMB 回环 Range 边下边播（M5m）

- SMBStreamServer：BSD socket 127.0.0.1 随机端口，HTTP HEAD/GET、206/Content-Range，64KiB 分块；libsmb2 pread 按需读。
- NWListener 在此环境 EINVAL，改 BSD socket。
- MediaItem.smb playbackURL 为回环 HTTP；smb:// 续播键；关闭播放器停 server；无 SMBCache。
- 实测 seek 30→31s、无缓存；真实 SMB3/大文件/并发未验证。

## SMB 来源（M5l）

- 源码 libsmb2 7.0 + CSMB2 C shim，macOS-only 条件依赖；Package -L/rpath /opt/homebrew。
- SMBClient：parse_url（端口）、connect、list/stat/open/pread；SMBSourceStore/Keychain；递归扫描。
- 播放先全文件下载到 SMBCache，再交给 libmpv；MediaItem.Origin.smb + smb:// 续播键。
- 实测 9.958s；自包含包含 libsmb2；未做 Range 代理/真实服务器/NFO/字幕。

## Plex 详情/版本/音轨（M5k）

- PlexMetadataView 展示 media 版本（分辨率/容器）、音频流（codec/display/channels）；按版本播放。
- openPlexMedia(mediaIndex) / playPlexMetadata + CLI --plex-play；OPENFUSE_PLEX_ITEM/AUTOPLAY。
- 修复 movie 误请求 children 404；实测 9.917s + 外挂字幕。
- 真实 Plex/音频听测/版本级去重未做。

## AirPlay 入口（M5j）

- `AirPlayRoutePicker` 包装 macOS `AVRoutePickerView`，置于播放器控制栏全屏旁。
- 仅 UI/构建验证；无 AirPlay 接收设备，实际路由/HDR/音频未测。
- iOS/tvOS 使用 AVKit 自带路由控件。

## WebDAV MKV 分辨率（M3m）

- 远程 MKV/TS/WebM/AVI 用 ffprobe + Basic Auth + HTTP Range；terminationHandler 读取临时输出，避免 NSTask 等待死锁。
- 高度写入 ScannedVersion.resolution，名称 `1080p · WebDAV`；报告序列化 resolution；1080p 筛选覆盖。
- 仅 macOS；iOS/tvOS/visionOS 扫描端无 ffprobe；真实 OpenList/大文件/HDR 未验证。

## T07 扫描中播放（M3l）

- 新增 CLI `--rescan-local <dir>`，在播放中触发本地重扫。
- 播放器报告 `libraryStatus`；实测 12.0s 播放未中断，扫描完成。
- 损坏单文件不拖垮扫描，但未过滤；不同本地目录会累积作品。
- 未做多根本地库策略、损坏条目过滤、重启字幕更新、WebDAV MKV 分辨率。

## Plex Direct 浏览（M5i）

- AppRoute.plexBrowser + PlexBrowserView：NavigationStack sections → items → metadata；show/season children；movie/episode 播放。
- PlexClient sections/items/children；token 动态海报；openPlexMetadata 复用字幕/mpv。
- 实测 sections 与电影网格；详情/播放点击未自动化，真实 Plex 未验证。

## Plex 多版本（M5h）

- Scanner 遍历 Plex `Media[]`，每个条目生成 ScannedVersion（分辨率/容器/part）。
- 电影/剧集保留全部版本；detail 版本菜单复用；CLI `--library-version N` 验收。
- 夹具 1080p+720p 实测备版 remotePath 4012；真实 Plex 与版本级去重未验证。

## Jellyfin+Emby 聚合去重（M5g）

- 分组按 mergeKey（kind+normalizedTitle）；同源/异源重复作品落同组，sources 合并。
- 兼容夹具实测 raw 4 作品/6 集 → 2 组；组内版本级去重未做。
- Emby 播放上报 Sessions/Playing 与 Progress；真实服务器/Stopped 未验证。

## Emby 来源（M5f）

- JellyfinSource.serverKind=jellyfin/emby；扫描 sourceKind 跟随 kind；MediaItem sourceKind 来自 playback context。
- UI 类型选择、Emby Direct 浏览；CLI --emby-*；续播键 emby://。
- 兼容夹具实测 2 作品/3 集、9.917s；真实 Emby/Jellyfin 与聚合去重未验证。

## macOS 自包含打包（M5e）

- Tools/bundle_runtime.py 递归复制 libmpv 与非系统 dylib（50 个）到 Contents/Frameworks，解析绝对与 @rpath 依赖，改 install name，加 @executable_path/../Frameworks。
- Scripts/bundle-runtime.sh 重建→打包→逐库签名→深验→检查无 /opt/homebrew；package-app.sh 产出 zip。
- lsof 确认 libmpv/libavcodec/libass 从 app 加载，Homebrew 0；打包 app 实际播放 HEVC/EAC3 MKV。
- 未公证/仅 arm64；音频未听测。

## Plex 外挂字幕（M5d）

- PlexPart.Stream 解码；metadata(ratingKey) + subtitleData(streamKey) 带 token。
- PlexSubtitle.tracks 归一化语言/格式，缓存并生成 SubtitleTrack；MediaItem.plex 携带。
- 实测 `Plex 外挂简体|zh-Hans` 下载、mpv:1 选中、9.958s 中文字幕。
- 未做直连浏览、Plex 音轨/版本、真实 Plex。

## Plex scrobble（M5c）

- `saveProgress` 在 ResumePolicy 判定已看完时调用 `reportPlexStop`（幂等），补发 timeline `stopped` 与 `/:/scrobble`。
- 近结尾 59.967s 实测收到 stopped/scrobble；自然 EOF 与真实 Plex 未验证。

## Plex 进度回写（M5b）

- `PlexPlaybackContext` 随 MediaItem；PlayerModel 在加载/保存/结束时上报 `/:/timeline`，结束时 `/:/scrobble`。
- 夹具记录 timeline state/time；实测 playing 0s、paused 59.967s；scrobble 未触发（未真正到结尾）。
- 未做真实 Plex、直连浏览/字幕、结束 scrobble 验证。

## Plex 来源（M5a）

- `PlexClient` JSON API：sections、section/all、metadata children、parts/thumb；`X-Plex-Token`。
- `PlexSourceStore` + Keychain；`PlexLibraryScanner` 生成电影/剧/季/集；海报 `plex:<ratingKey>`，UI 用 token 解析，不落库。
- `MediaItem.Origin.plex` + `plex://` 续播键；库播放走 libmpv。
- Mac UI 添加/扫描/删除 Plex 来源；夹具与验收脚本。
- 未做直连浏览、Plex 进度回写、字幕、真实服务器、Emby/SMB/HDR。

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
