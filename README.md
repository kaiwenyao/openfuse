# OpenFuse

## 安装（macOS）

```bash
curl -fL --proto '=https' --proto-redir '=https' \
  -o install-openfuse-macos.sh \
  https://github.com/kaiwenyao/openfuse/releases/latest/download/install-openfuse-macos.sh \
  && bash install-openfuse-macos.sh
```

默认装到 `/Applications`，校验 SHA-256、备份回滚、可重复升级；默认使用持久本地签名身份（无需 Apple Developer 账号）。离线安装：`bash install-openfuse-macos.sh --app OpenFuse-macos.zip`。说明见 [docs/INSTALL.md](Docs/INSTALL.md)。

iPhone / iPad 用数据线安装与 7 天续签：`Scripts/install-openfuse-ios.sh --device "设备名"`，前置步骤见 [INSTALL-MAC-IOS.md](Docs/INSTALL-MAC-IOS.md)。

## 当前版本 0.9.5（2026-11-25）

- **改善 macOS 播放视频时用 `Cmd+Tab` 切换应用的卡顿。** 播放器调整出帧时序，减少 libmpv 在窗口主线程上的等待。本地样片中，渲染耗时中位数从约 35 ms 降到 3–4 ms。[修复与验证记录](Docs/MACOS-CMD-TAB-FIX.md) · [PR #2](https://github.com/kaiwenyao/openfuse/pull/2)

## 历史版本 0.9.4（2026-11-25）

- **修复 macOS 字幕时间偏移。** 菜单、输入框、保存和播放使用相同的毫秒精度。设置 `0.04` 秒后，菜单显示「延后 0.04 秒」，重新打开输入框后直接应用会保留该值。
- 粘贴 `−0.1` 会正确提前字幕。已保存的偏移按影片和字幕轨恢复，重置只清除当前轨道的偏移。[PR #1](https://github.com/kaiwenyao/openfuse/pull/1)

## 历史版本 0.9.3（2026-11-25）

- **修复换集后无法暂停。** 在播放页面换集之后，右键任意位置或按空格不再能暂停新视频：播放器安装一次的 `NSEvent` 本地监视器把第一集的 `PlayerModel` 捕获在闭包里，而 `startPlayer()` 换集会新建模型但保留 `.player` 路由与视图身份，`onAppear` 不会再触发，于是右键/空格持续作用于已停止的旧引擎。现在改为在事件到达时从 `AppModel.shared` 解析当前在屏剧集（`route == .player` 守卫），空格、右键、↑/↓、←/→、Esc、⌘3 在换集、自动连播、加载中改选之后都指向新引擎。改动只在 `Sources/OpenFuseApp/PlayerView.swift`，详见 [0.9.3 换集修复](Docs/0.9.3-EPISODE-SWITCH.md)。
- 136 个单元测试；新增 `Scripts/run-episode-switch-pause.sh`（选集面板换集 / 直接开另一文件 / 无换集基线，右键与空格与 ↓ 音量键）PASS；原有 `Scripts/run-player-interactions.sh` 保持 PASS。

## 历史版本 0.9.2（2026-11-21）

- **WebDAV 文件夹卡片只显示本名。** 网格、列表、单季卡副标题和 VoiceOver 统一走 `RemoteEntry.folderDisplayName`：优先使用有效的单段 `<displayname>`，OpenList 把整条路径写进 displayname 或漏传名称时回退到 `entry.path` 的最后一个非空路径段。`entry.path`/`url` 继续用于请求、导航和缓存；同时修复了路径型 displayname 下的 NFO/外挂字幕文件名拼接。覆盖中文、空格、括号、尾斜杠、字面百分号和不同父目录下的同名文件夹。
- **播放器改为紧凑、可拖动的原生悬浮面板。** 两行布局（播放/快退/快进居中，音量、选集、字幕分列两侧；时间轴独占第二行并显示剩余时间），面板从画面顶部中央出现，宽度 480–560 pt 随窗口收缩，320 pt 小窗保留播放、时间轴和字幕入口。macOS 26+ 使用系统 `glassEffect`，macOS 14/15 使用 `NSVisualEffectView` 的 within-window 混合；减少透明度时自动切换不透明面板。面板只能通过顶部空白拖动条移动并始终限制在窗口内；悬停、字幕弹层、键盘操作和拖动时间轴期间保持可见，空闲后淡出。缩略图预览随面板位置向下/向上展开。顶部标题收敛为作品名 + 季集号，完整文件名、来源、编码和会话日志移入「播放信息」。
- 136 个单元测试；WebDAV 深路径、文件夹导航、返回原集、音量键、右键暂停、全屏、窗口缩放和面板交互实测通过。

## 历史版本 0.9.1（2026-11-21）

- **底栏字幕菜单整行交互。** 「关闭字幕」、每条字幕轨和字幕偏移动作都改为原生 Button 的行式布局：文字、勾选标记与右侧空白同属一个完整宽度的矩形命中区；悬停整行高亮，移出清除，当前轨仍勾选，禁用动作不响应。保留键盘与 VoiceOver 标签。
- **⌘3 最大化窗口。** 以播放器所在屏幕 `visibleFrame` 设置整个窗口 frame，保留标题栏/红黄绿按钮和菜单栏/Dock 预留区；不会进入原生全屏，视频比例不变、必要时黑边。从原生全屏按 ⌘3 会先退出全屏，收到 AppKit 退出通知后再最大化；⌘4 适合屏幕、⌃⌘F 原生全屏保持原行为。
- **影视资料跟随 macOS/单 App 语言。** 解析 `AppleLanguages`，区分 zh-Hans/zh-Hant（含地区变体）、ja 等；按字段执行「用户语言 → 同语言变体 → 英文」。Wikipedia 使用对应语言与中文 variant，TVmaze/Bangumi 合并中/日集名；Bangumi 的日文 staff desc 不冒充中文剧情。缓存键包含语言，切换语言重新请求；电影、剧集、分集、目录和播放标题使用同一套结果。纯 WebDAV 仍无需 API key。
- **进度条预览。** 悬停立即显示准确时间；内存命中同步显示、磁盘命中异步读取并跳过抽帧防抖；缩略图有跨重启磁盘缓存 + 80 项 LRU 内存缓存，键由媒体指纹与采样时间组成；新增可关闭事件耗时记录（mouse/memory/disk/decode/shown）。本地冷缓存 P50 166 ms / P95 205 ms，二次启动磁盘 P50 0 ms / P95 1 ms，热内存 P95 0 ms。
- 117 个单元测试；窗口、字幕、Jellyfin、三功能、缩略图回归通过。

# OpenFuse 开发计划

**当前先完成 macOS，只做 WebDAV 与 Jellyfin 两种来源。** 以 Infuse 8.5.10 Mac 的找片、播放、选轨、返回和续播行为作为参照，采用 OpenFuse 原创界面。本机构建结果、源码中发现的问题和下一轮验收见[当前 Mac 交付任务](Docs/MAC-FIRST.md)。

下列全平台记录与最初路线保留作历史参考。旧版测试环境与产物见[阶段快照](Docs/STAGE-2026-11-20.md)，既有功能和测试编号见[验收矩阵](PARITY.md)。

## 当前进度（2026-11-19）

> 注：以下 M4q–M5v 中的 Trakt 条目是历史验收记录；Trakt 同步功能已在 0.4.0 完全移除。

- **M0 引擎与素材：完成。** AVPlayer 无法打开 Matroska（0 轨、0 s、无首帧）；libmpv 0.42.0 可播放、可定位，应用内启用 VideoToolbox 硬解。测试片由脚本生成：HEVC Main 10、E-AC-3 5.1、中日双语 ASS，文件级 24/24 声道报号校验通过。记录：[引擎选型](Docs/ENGINE-DECISION.md)、[测试素材](Docs/TEST-MEDIA.md)。
- **M1 Mac 本地播放：首个可用版本。** 可打开 MKV、出画面/出声、切换外挂简繁 ASS、缺字体回退、拖动、全屏、退出后从上次位置续播，关闭播放器再打开可重建会话。构建与实测见 [M1 验收记录](Docs/M1-ACCEPTANCE.md)。
- **M2 WebDAV + Jellyfin Direct：完成本地验证。** WebDAV 可添加来源、按真实目录浏览、直放、远程 ASS、限速拖动与续播。Jellyfin Direct 可登录、浏览电影/剧/季/集、使用服务器封面与版本、直连播放、保留服务器音轨/字幕命名、回写开始/进度/停止并用服务器位置续播。两者均提供本地协议夹具与端到端脚本。真实 OpenList、百度网盘与真实 Jellyfin 账号未提供，相关组合标为「待验证」。记录：[M2a WebDAV](Docs/M2-WEBDAV.md)、[M2b Jellyfin](Docs/M2-JELLYFIN.md)。
- **M3a 聚合媒体库：完成本地验证。** SQLite 媒体库、本地/WebDAV/Jellyfin 扫描、电影/剧/季/集、跨来源合并展示、Jellyfin 服务器封面、电影多版本、详情、搜索、从媒体库播放与来源切换。记录：[M3a 媒体库验收](Docs/M3-LIBRARY.md)。
- **M3b 元数据：完成本地验证。** TMDB 仅保留开发环境变量兼容；正常用户无需配置，WebDAV 使用 NFO/TVmaze/Wikipedia/Wikidata 公共资料。记录：[M3b 元数据验收](Docs/M3B-METADATA.md)。
- **M3c 集级版本合并：完成本地验证。** 电影合并 Jellyfin 多版本 + 本地 + WebDAV 为 4 个版本；剧集按季/集合并，S01E01 3 个版本、S01E02 2 个；详情用版本菜单选择来源播放。记录：[M3c 版本合并验收](Docs/M3C-VERSIONS.md)。
- **M3d 手动纠错与扫描：完成本地验证。** 详情可改标题/年份/简介/海报并持久化/清除；扫描可取消并显示进度，取消保留旧库；10,000 条目完整扫描 6.52 s，取消后旧库 10,000 条不变。记录：[M3d 编辑/扫描验收](Docs/M3D-EDIT-SCAN.md)。
- **M3e 手动整理：完成本地验证。** 详情可把同类型作品手动合并、拆分或恢复自动分组；分组键持久化；编辑信息可搜索 TMDB 候选并一键填入标题/年份/简介/海报。记录：[M3e 手动整理验收](Docs/M3E-MANUAL.md)。
- **M3f WebDAV 元数据：完成本地验证。** WebDAV 扫描下载 NFO，使用 movie/tvshow/单集 NFO 的标题/简介/海报；海报经 Basic Auth 下载并缓存，海报库不再依赖 TMDB。记录：[M3f WebDAV NFO 验收](Docs/M3F-WEBDAV-NFO.md)。
- **M3g 媒体库排序/筛选：完成本地验证。** 标题/年份/最近添加/集数排序，电影/剧集筛选，搜索组合；`addedAt` 来自本地 mtime、WebDAV mtime、Jellyfin DateCreated。记录：[M3g 排序筛选验收](Docs/M3G-FILTERS.md)。
- **M3 尾项：** T07 扫描中播放/损坏文件已由 M3l 验证；多根本地库累积与损坏条目过滤仍待处理。真实 OpenList/Jellyfin 验证、Infuse 同机对照与人工听测仍缺。
- **M3h 观看状态/防剧透：完成本地验证。** 未看/观看中/已看筛选，最近播放排序，4K/1080p/720p 过滤；防剧透隐藏详情/单集简介；WebDAV NFO 中点标题正确合并。记录：[M3h 观看状态验收](Docs/M3H-WATCH.md)。
- **M4a 跨平台数据层与 iOS 首版：构建完成，运行待验证。** 拆分 `OpenFuseData`（媒体库/WebDAV/Jellyfin/SQLite/记录）供全平台复用；新增 iPhone/iPad SwiftUI 应用、示例 MP4、Files 导入、AVPlayer 播放与续播。iOS Simulator/device generic 构建均成功；本轮无模拟器 runtime，启动/触控/后台恢复标「待验证」。记录：[M4a 移动端验收](Docs/M4-MOBILE.md)。
- **M4b 移动端来源：构建完成，运行待验证。** 设置「媒体来源」支持添加/扫描/删除 WebDAV（OpenList）与 Jellyfin，凭据存 Keychain，库扫描复用 `OpenFuseData`；Jellyfin 海报按 token 生成。远程播放（转码/HLS/鉴权代理/MKV）仍未接。Simulator/device 构建均成功。记录：[M4 移动端验收](Docs/M4-MOBILE.md)。
- **M4c iPad 分栏与 tvOS/visionOS：构建完成，运行待验证。** iPad 常规宽度使用 NavigationSplitView 侧栏+详情；Apple TV 焦点卡片与 AVPlayer；Vision Pro 分栏/详情/播放。三端与 iPhone 共享 `MobileLibraryModel`/示例 MP4；iOS Simulator/device、tvOS Simulator、visionOS Simulator 均构建成功。无 runtime，UI/遥控/手势/空间布局待验证。记录：[M4c 平台验收](Docs/M4C-PLATFORMS.md)。
- **M4d 认证远程播放：完成本地验证。** `AuthenticatedAssetLoader` 为 AVPlayer 注入 WebDAV Basic/Jellyfin Token 头并处理 Range；移动端 WebDAV MP4/MOV 可远程播放与续播。实测 AVAsset 20s/1280×720、AVPlayer 4 秒推进 3.598s，错误密码失败。记录：[M4d 认证播放验收](Docs/M4D-AUTH-PLAYBACK.md)。
- **M4e Jellyfin 移动远程：完成同链路验证。** 详情调用 PlaybackInfo/MediaSource，生成带 api_key 的直连 URL，经认证 loader 交给 AVPlayer；夹具 MP4 实测 20s/1280×720、6 秒推进 5.866s。MKV 仍需转码/libmpv。记录：[M4e Jellyfin 移动端验收](Docs/M4E-JELLYFIN-MOBILE.md)。
- **M4f Jellyfin HLS：完成同链路验证。** 非 MP4 容器走 `master.m3u8` H.264/AAC/TS 转码 URL；同源 MKV 夹具经 HLS 在 AVPlayer 播放 60s，6 秒到 5.954s。真实 Jellyfin 参数待验证。记录：[M4f HLS 验收](Docs/M4F-HLS.md)。
- **M3i WebDAV 超时恢复：完成本地验证。** 单目录 PROPFIND 504 时继续扫描，失败目录下的旧作品保留，其他目录刷新；夹具注入 504，2 作品在失败重扫后仍为 2；状态显示失败目录数。26 个单元测试。记录：[M3i 恢复验收](Docs/M3I-RECOVERY.md)。
- **M4g iOS 实际运行：完成。** iOS 27.2 Simulator 安装并启动 iPhone/iPad；首屏、iPad 分栏、样本 MP4 播放（HUD 3.0/20.0s）、退出保存 4.795s、重启续播 12.0/20.0s 均实测；修复 `file://` URL 当路径解析的 bug。记录：[M4g iOS 运行验收](Docs/M4G-IOS-RUN.md)。
- **M4h 移动端远程实际播放：完成。** iOS 模拟器添加/扫描 WebDAV 与 Jellyfin 并实际播放：WebDAV Basic Auth MP4 HUD 11.0/20s；Jellyfin 选 MKV 后走 HLS，HUD 9.0/60.0s。测试 bootstrap 用内存凭据绕过未签名模拟器 Keychain；生产仍走 Keychain。记录：[M4h 移动远程验收](Docs/M4H-MOBILE-REMOTE.md)。
- **M3j 本地分辨率：完成。** MP4 用 AVFoundation、MKV 用 Mac ffprobe 补齐 1080p；画质筛选「1080p」现显示本地电影与两部剧。记录：[M3j 分辨率验收](Docs/M3J-RESOLUTION.md)。
- **M3k 流分辨率：完成。** WebDAV MP4 用认证 loader 读 720p；Jellyfin 扫描 PlaybackInfo 得到单集 1080p；1080p 筛选现覆盖 Jellyfin 剧集，720p 覆盖 WebDAV MP4。记录：[M3k 流分辨率验收](Docs/M3K-STREAM-RESOLUTION.md)。
- **M4i 移动轨道与 tvOS：完成构建/运行验证。** 移动样本升级为 HEVC Main10 + E-AC-3 5.1 + AAC + 简繁 mov_text；播放器有音轨/字幕菜单，HUD 实测 E-AC-3/简体选中。tvOS 27.2 runtime 安装后 Apple TV 模拟器实际启动、焦点网格与全屏播放（帧 5.625s）。字幕文字与音频输出未确认。记录：[M4i 验收](Docs/M4I-TRACKS-TVOS.md)。
- **M4j 移动字幕自绘：完成。** SRT/ASS 解析 + 0.25s ticker 叠加字幕；简体 seek 4.5s 显示第一句，繁体 seek 10s 显示第二句，简繁切换与 seek 同步实测；修复 HUD 时间停在 0。音轨仍为 E-AC-3 选中但未听测。记录：[M4j 字幕验收](Docs/M4J-SUBTITLES.md)。
- **M4k WebDAV 远程字幕：下载链路完成。** 播放时列 WebDAV 目录、匹配并带认证下载简/繁 SRT 到本地缓存，菜单显示「中文（简体）(SRT)」；远程画面截取因 AVPlayer 时间跳变未取得，本地字幕已由 M4j 验证。记录：[M4k 远程字幕验收](Docs/M4K-REMOTE-SUBTITLES.md)。
- **M4l 远程字幕修复：完成。** 远程时长从播放器当前 asset 读取（20.0s），播放前等待 ready，新增 pause-at 钩子；WebDAV 远程字幕在 4.6/20.0s 实际显示第一句。远程 seek 同步仍不稳。记录：[M4l 验收](Docs/M4L-REMOTE-SUBTITLE-FIX.md)。
- **M4m 远程精确 seek：完成。** AVPlayer 精确 seek + completion，WebDAV 远程 seek 到 10s 后 HUD 10.0/20.0，第二句字幕同步。Jellyfin 外挂字幕 DeliveryUrl 下载管线已加，但本轮未进入播放器，画面待验证。记录：[M4m 验收](Docs/M4M-SEEK-JFSUBS.md)。
- **M4n Jellyfin 外挂字幕：完成。** movie-1 HLS 60s，App 下载 DeliveryUrl SRT 到缓存；播放 4.7/60.0s 显示第一句，菜单「外挂简体中文」。自动播放时序仍脆弱。记录：[M4n 验收](Docs/M4N-JELLYFIN-EXTERNAL-SUBS.md)。
- **M4o Vision Pro 实际运行：完成。** visionOS 27.2 runtime 安装，Apple Vision Pro 模拟器启动 OpenFuse 空间窗口；autoplay 播放 HEVC/EAC3 样本到 24s。至此 Mac/iPhone/iPad/Apple TV/Vision Pro 五端均有实际启动证据。音频与沉浸式空间交互未验证。记录：[M4o 验收](Docs/M4O-VISIONOS.md)。
- **M4p 跨设备续播：完成本地两设备验证。** PlaybackStore 合并（新时间戳优先）、本地共享 JSON transport、CloudKit transport（代码）；A 播放 9.917s → 同步 → B 从 9.9s 继续到 14.417s。真实 iCloud entitlements/账号未验证，Trakt/自动同步/离线队列未做。记录：[M4p 验收](Docs/M4P-PROGRESS-SYNC.md)。
- **M5a Plex 来源：完成本地验证。** Mac 添加 Plex（地址/token）、扫描 2 作品/3 集、海报 token-free 引用、从媒体库播放 Plex 第 1 集并冻结 9.917s；UI/夹具/验收脚本齐全。真实 Plex、直连浏览、进度回写、字幕未做。记录：[M5 Plex 验收](Docs/M5-PLEX.md)。
- **M5b Plex 进度回写：timeline 完成。** playing/paused/stopped 已上报；M5c 补上 finished-save scrobble。
- **M5c Plex scrobble：完成。** saveProgress 判定 95% 看完时幂等上报 stopped + `/:/scrobble`，夹具实测收到 scrobble。真实 Plex 未验证。记录：[M5c 验收](Docs/M5C-PLEX-SCROBBLE.md)。
- **M5d Plex 外挂字幕：完成。** metadata Stream 带 token 下载到缓存，生成 `Plex 外挂简体|zh-Hans`；`--subtitle zh-Hans` 选中 mpv:1，9.958s 画面显示中文字幕。记录：[M5d 验收](Docs/M5D-PLEX-SUBTITLES.md)。
- **M5e macOS 自包含打包：完成。** libmpv + 49 个非系统依赖复制到 `Contents/Frameworks` 并改 `@rpath`；lsof 确认 libmpv/libavcodec/libass 全部从 app 加载，`/opt/homebrew` 依赖 0；打包 app 67MB、zip 27MB，实际播放 MKV/HEVC/EAC3 成功。未公证、仅 arm64。记录：[M5e 验收](Docs/M5E-PACKAGING.md)。
- **M5f Emby 来源：完成本地验证。** 复用 Jellyfin 兼容 API，来源 `serverKind=emby`；UI 类型选择、Emby Direct 浏览、CLI `--emby-*`；扫描 2 作品/3 集、sourceKind=emby、播放 9.917s。真实 Emby 待验证。记录：[M5f 验收](Docs/M5F-EMBY.md)。
- **M5g 聚合去重/Emby 进度：完成本地验证。** Jellyfin+Emby 双来源原始 4 作品/6 集聚合为 2 组、sources 同时含两者；Emby Sessions/Playing（99170000 ticks）与 Progress（101670000）已回写。脚本可复现。记录：[M5g 验收](Docs/M5G-DEDUPE-EMBY-PROGRESS.md)。
- **M5h Plex 多版本：完成本地验证。** 扫描遍历全部 `Media[]`，电影/每集保留 2 个版本；`--library-version 1` 实际播放 720p 备版（part 4012），字幕/进度回归通过。记录：[M5h 验收](Docs/M5H-PLEX-VERSIONS.md)。
- **M5i Plex 直连浏览：完成。** 新增 Plex Direct NavigationStack：sections → 电影/剧 → 季/集 → 详情/播放；实测进入电影 section 并显示条目网格，请求带 token。播放按钮复用已验证的 `openPlexMetadata`。记录：[M5i 验收](Docs/M5I-PLEX-BROWSER.md)。
- **M3l T07 扫描中播放：完成本地验证。** `--rescan-local` 在播放中重扫，播放器到 12.0s 未中断；损坏单文件不拖垮扫描（仍留下不可播条目）。不同本地目录会累积作品，测试改用独立 support。记录：[M3l 验收](Docs/M3L-T07.md)。
- **M3m WebDAV MKV 分辨率：完成。** 远程 MKV 用带 Basic Auth 的 ffprobe Range 探测，版本 `1080p · WebDAV`，1080p 筛选覆盖；terminationHandler 避免等待死锁。iOS 扫描端仍无 ffprobe。记录：[M3m 验收](Docs/M3M-WEBDAV-MKV.md)。
- **M5j AirPlay 入口：完成。** Mac 播放器控制栏加入 `AVRoutePickerView` AirPlay 图标；构建/UI 截图通过。无接收设备，实际投屏标待验证。记录：[M5j 验收](Docs/M5J-AIRPLAY.md)。
- **M5k Plex 详情/版本/音轨：完成。** 详情显示 1080p/720p 与 E-AC-3 5.1/AAC，可按版本播放；`--plex-play 401` 实际播放 9.917s 并选中 Plex 外挂简体；修复电影 children 404。记录：[M5k 验收](Docs/M5K-PLEX-DETAIL.md)。
- **M5l SMB 来源：完成本地验证。** 源码 libsmb2 7.0 + impacket SMB2 夹具：1 作品/1 集，sourceKind=smb，下载缓存 SHA-256 一致，mpv 播放 9.958s；自包含包已带 libsmb2。当前是全文件缓存、非边下边播。记录：[M5l 验收](Docs/M5L-SMB.md)。
- **M5m SMB 边下边播：完成本地验证。** BSD socket 回环 HTTP Range 服务器 + libsmb2 pread；`--seek 30` 后播放到 31.0s，无整文件缓存。NWListener 在当前环境 EINVAL，已改 BSD socket。记录：[M5m 验收](Docs/M5M-SMB-STREAMING.md)。
- **M5n SMB NFO/海报/字幕：完成本地验证。** SMB 句柄复用；扫描读取 NFO 并缓存 poster/folder/cover；播放前列同目录字幕、下载 SRT 并选中 mpv:1；回环 Range seek 31s、无整文件缓存。剧集跨季 tvshow NFO、真实 SMB3 待验证。记录：[M5n 验收](Docs/M5N-SMB-METADATA.md)。
- **M5o SMB 跨季 NFO/重连：完成本地验证。** 剧集继承 tvshow.nfo/海报，单集 NFO 优先；修复扫描中 STATUS_SHUTDOWN 漏掉第二季（重连重试）。夹具 2 作品/3 集，S01E01 NFO 标题、seek31、字幕、无缓存。记录：[M5o 验收](Docs/M5O-SMB-SHOW-NFO.md)。
- **M5p 版本级去重：完成本地验证。** Jellyfin/Emby 同 mediaSourceID+名称+分辨率版本合并为 `Jellyfin/Emby · …`，1080p/720p 仍分开；单元测试 29/29。顺带修复 Emby 测试 env 触发 Keychain。记录：[M5p 验收](Docs/M5P-VERSION-DEDUPE.md)。
- **M4q Trakt：完成夹具验证。** 设备码/轮询/搜索/scrobble start/stop（stop 99.9%）实际请求；播放器按标题匹配电影并上报。真实账号/剧集匹配/历史同步未做。记录：[M4q 验收](Docs/M4Q-TRAKT.md)。
- **M4r Trakt 剧集：完成夹具验证。** 播放剧集时搜索 `/search/show`，scrobble body 带 `episode{season,number}`；电影/剧集 start/stop 均通过。真实账号/OAuth UI/历史同步未做。记录：[M4r 验收](Docs/M4R-TRAKT-EPISODES.md)。
- **M4s Trakt 历史：完成夹具验证。** 拉取 `/sync/history/movies|shows`，匹配本地库并把电影+剧集 3 集标记已看；watched 筛选显示电影与整剧。真实账号/OAuth UI/远程来源标记未做。记录：[M4s 验收](Docs/M4S-TRAKT-HISTORY.md)。
- **M4t Trakt 远程历史：完成 Jellyfin 验证。** 为 Jellyfin/Emby/WebDAV/SMB/Plex 生成播放器 fingerprint key，history 匹配后标记已看；Jellyfin 远程 watched 显示电影+剧集。WebDAV/SMB/Plex 路径代码已接未逐一验收。记录：[M4t 验收](Docs/M4T-TRAKT-REMOTE-HISTORY.md)。
- **M5t Trakt OAuth 设置：完成 UI/协议验证。** 设置页填写 Client ID/Secret/API 地址，保存 UserDefaults + Keychain；设备码/轮询按钮；环境变量仍为测试覆盖。设置页实际渲染，点击未自动化。记录：[M5t 验收](Docs/M5T-TRAKT-OAUTH-UI.md)。
- **M5u SMB 并发：完成本地验证。** 回环 Range 服务器并发连接上限 4，socket 设 SO_NOSIGPIPE；两个并发 Range 请求 SHA-256 与 fixture 片段一致。真实 SMB3/大文件压力待验证。记录：[M5u 验收](Docs/M5U-SMB-CONCURRENCY.md)。
- **M5v Trakt 自动轮询：完成夹具验证。** 设备码后按 interval 自动请求 token，1.07s 成功；手动检查/关闭设置会取消任务。测试跳过 Keychain；真实账号/Keychain 未验证。记录：[M5v 验收](Docs/M5V-TRAKT-AUTO-POLL.md)。
- **M5w HDR10 元数据：完成本地验证。** 1080p10bit HDR10 样片经 ffprobe 识别 bt2020/smpte2084，版本/UI 显示 HDR10；SQLite 迁移 dynamic_range。实际 HDR 输出未验证；WebDAV/Jellyfin HDR 未解析。记录：[M5w 验收](Docs/M5W-HDR.md)。
- **M5x 远程 HDR：完成本地验证。** Jellyfin VideoRange/VideoRangeType 与 WebDAV 远程 MKV ffprobe 均解析 HDR10；版本/报告显示 dynamicRange=HDR10。实际 HDR 输出未验证。记录：[M5x 验收](Docs/M5X-REMOTE-HDR.md)。
- **M5y HDR10 播放：完成色调映射验证。** libmpv 读入 bt.2020/pq（sig-peak 4.93），spline + compute-peak 输出 SDR 彩色条正常；播放报告暴露 HDR 属性。真实 HDR 直通/显示器未验证。记录：[M5y 验收](Docs/M5Y-HDR-PLAYBACK.md)。
- **M3n 损坏过滤：完成本地验证。** ffprobe 判定本地版本可播放性，Broken.Movie 不再入库；空作品逐级移除，扫描中播放仍通过。SMB/WebDAV 损坏过滤未做。记录：[M3n 验收](Docs/M3N-CORRUPT-FILTER.md)。
- **M3o 多根本地库：完成本地验证。** `local-roots.json` 持久化根目录，每个根独立 sourceID；可扫描全部/移除。两根目录共存 rawWorks=2，移除后=1。跨根重复文件未按内容去重。记录：[M3o 验收](Docs/M3O-LOCAL-ROOTS.md)。
- **M3p 跨根去重：完成本地验证。** 本地版本记录 size+首尾 64KB SHA-256 contentKey；同内容跨根版本合并为 1 条（rawWorks=2/groups=1）。非全文件哈希，SMB/WebDAV 无指纹。记录：[M3p 验收](Docs/M3P-LOCAL-DEDUPE.md)。
- **M5z 5.1 解码：完成 PCM 验证。** `OPENFUSE_AO_PCM` 测试模式将 E-AC-3 解码为 48kHz/6声道/5.1，FL/FR/FC/LFE/BL/BR 六路均非静音；但**未做扬声器/耳机听测**。记录：[M5z 验收](Docs/M5Z-AUDIO-PCM.md)。
- **M3q MKV 头部解析：完成本地验证。** 纯 Swift EBML 解析 2MB Range，iOS 远程 MKV 可得到 1080p/HDR10；单元测试 31/31。iOS 运行期扫描未跑。另补 5.1→stereo downmix PCM（2ch 非静音）。记录：[M3q 验收](Docs/M3Q-MKV-HEADER.md)。
- **M3r iOS 运行期 MKV：完成模拟器验证。** iPhone 18 Pro 模拟器启动后扫描 WebDAV HDR MKV，沙盒 SQLite 得到 `1080p · WebDAV` / `dynamic_range=HDR10`，并有截图。真实 OpenList/大头部 EBML 未测。记录：[M3r 验收](Docs/M3R-IOS-MKV-RUNTIME.md)。
- **M5ab HDR 直通：完成 EDR 参数验证。** Built-in Retina EDR=16，mpv 自动 target-colorspace-hint=yes；输出 bt.2020/pq、light=display、max-luma=1000。OpenGL 渲染器禁用 HDR peak computation，肉眼/色度计未测。记录：[M5ab 验收](Docs/M5AB-HDR-PASSTHROUGH.md)。
- **M5ac 音频设备：完成属性验证。** 枚举 CoreAudio 输出设备，播放器菜单可选自动/具体设备，报告确认 selected/active 为 BuiltInSpeakerDevice、AO coreaudio、6 声道。实际听测/热插拔未做。记录：[M5ac 验收](Docs/M5AC-AUDIO-DEVICES.md)。
- **M5ad 跨来源指纹：完成本地验证。** 共享 ContentFingerprint，本地/WebDAV/SMB 同一 HDR 文件合并为 1 个版本（contentKey 一致，sources 三源）。首尾抽样非全文件哈希；SMB HDR 元数据未探测。记录：[M5ad 验收](Docs/M5AD-CROSS-SOURCE-FINGERPRINT.md)。
- **M5ae SMB HDR：完成本地验证。** SMB 扫描读前 2MB，MatroskaProbe 得到 `1080p · SMB`/HDR10，contentKey 保持；SMB HDR 样片验收 PASS。真实 SMB3/大头部/性能未测。记录：[M5ae 验收](Docs/M5AE-SMB-HDR.md)。
- **M5af SMB MP4：完成本地验证。** 纯 Swift MP4Probe 解析 moov/tkhd/colr，SMB MP4 得到 `1080p · SMB`；单测 32/32。尾部/碎片 MP4、HDR colr 未测。记录：[M5af 验收](Docs/M5AF-SMB-MP4.md)。
- **M5ag 尾部/HDR MP4：完成本地验证。** 20s HDR10 MP4（moov 在尾、colr 9/16）经 SMB 头 4MB→尾 8MB 回退解析为 `1080p · SMB`/HDR10；修复 MP4Probe stsd/sample entry 头与 SMB 短读循环。单测 33/33。记录：[M5ag 验收](Docs/M5AG-TAIL-MP4.md)。
- **M5ah 大 MP4 moov 扫描：完成本地验证。** 12.6MB tail-moov HDR MP4 经 SMB 头4MB→尾8MB（中段开始）扫描 moov，得到 `1080p · SMB`/HDR10；单测 34/34。碎片 MP4/moov>8MB 未测。记录：[M5ah 验收](Docs/M5AH-MOOV-SCAN.md)。
- **M6a visionOS 沉浸：完成模拟器验证。** 新增 ImmersiveSpace + RealityKit VideoMaterial 空间屏幕、播放/拖动/关闭控件；显式多场景 Info.plist 修复系统拒绝。模拟器 Metal 不可用导致 VideoMaterial 黑屏，真机待验证。记录：[M6a 验收](Docs/M6A-VISION-IMMERSIVE.md)。
- **M6b visionOS 控制：完成进度回写验证。** 沉浸屏幕支持拖动/缩放；autoclose=6 后 PlaybackStore 写入 7.517s，窗口显示「从 7 秒继续」。模拟器 Metal 仍黑屏，真机手势/空间音频待验证。记录：[M6b 验收](Docs/M6B-VISION-CONTROLS.md)。
- **M6c visionOS full immersion：完成模拟器验证。** `.full` 沉浸实际渲染测试图（00:00:11:22，HEVC/E-AC-3 标识），星点环境 + 3D 播放/关闭球 + 进度条；打开沉浸关闭主窗口，退出重开。真机空间音频/手势待验证。记录：[M6c 验收](Docs/M6C-VISION-IMMERSION.md)。
- **M3s 远程损坏过滤：完成本地验证。** WebDAV/SMB 读 64B 容器签名，Broken.Movie 不再入库；SMB read 重连重试修复 NFO 后读失败。单测 36/36。记录：[M3s 验收](Docs/M3S-REMOTE-CORRUPT.md)。
- **M2c 真实 OpenList：完成本地 Docker 验证。** 官方 OpenList 镜像 + Local 存储，`/dav` 扫描 1 作品/1080p，seek 11.0s、远程简中字幕、Range 206；截图 t=15s 双语字幕同步。百度网盘账号/云跳转未验证。记录：[M2c 验收](Docs/M2C-OPENLIST-REAL.md)。
- **M2d iPhone OpenList：完成模拟器验证。** iPhone 18 Pro 连真实 OpenList Docker，播放到 15.958s，E-AC-3 5.1 + 简中 SRT，进度 12.061s 回写；修复移动端暂停不保存进度。百度网盘/真机未验证。记录：[M2d 验收](Docs/M2D-IOS-OPENLIST.md)。
- **M2e 真实 Jellyfin：完成 Docker 全链路。** Jellyfin 12.4 启动向导/用户/媒体库脚本化，OpenFuse 扫描 1080p、seek 11.106s、6ch/字幕；服务器位置 11.022s/Played=false。修复 12.x Authorization 登录头与 quit-after 未发 Stopped。百度/HTTPS/转码/多用户未验证。记录：[M2e 验收](Docs/M2E-REAL-JELLYFIN.md)。
- **M2f iPhone Jellyfin HLS：完成真实转码。** 真实 Jellyfin 12 MKV 经 libx264/AAC HLS 在 iPhone 播放 12.2/60s；修复 Jellyfin 12 HLS 认证头与 AVURLAsset header/路径映射。画质 416×234、音轨/字幕元数据待优化。记录：[M2f 验收](Docs/M2F-IOS-JELLYFIN-HLS.md)。
- **M5ak 真实 Samba SMB3：完成 Docker 验证。** Samba 4.13.7 共享扫描 1 作品/1080p，seek 11.0/60、字幕 mpv:1；修复根/子路径前导 `/` 兼容，impacket 回归通过。签名/加密/DFS/大文件未测。记录：[M5ak 验收](Docs/M5AK-SAMBA-SMB3.md)。
- **M5al SMB3 签名/加密：完成本地验证。** 强制签名/加密 Samba 下自动回退到 `smb2_set_sign/seal`，会话 SMB3_11、AES-128-CCM 加密、AES-128-CMAC 签名，扫描/seek 11s；impacket 回归通过。DFS/域/大文件未测。记录：[M5al 验收](Docs/M5AL-SAMBA-ENCRYPTED.md)。
- **M2g Jellyfin HLS 质量：完成 1080p/标签验证。** master.m3u8 加 8Mbps/1920×1080，服务器按 maxrate 8000000 转码；HUD 显示服务器音轨/字幕名称（转码 AAC/服务器）。4K/HTTPS/多用户/真机未测。记录：[M2g 验收](Docs/M2G-JELLYFIN-HLS-QUALITY.md)。
- **M5am SMB 大文件：完成本地验证。** 120s/90MB HEVC/E-AC-3 在 Samba 上 seek 62s，回环 URL，RSS≈100MB、无整文件缓存。多GB/并发/DFS未测。记录：[M5am 验收](Docs/M5AM-SAMBA-LARGE.md)。
- **M2h Jellyfin 多用户：完成隔离验证。** 创建 test2，独立配置播放 11.064s；test 位置保持 0，两用户 UserData 不串。UI 用户切换/权限/并发送待。记录：[M2h 验收](Docs/M2H-JELLYFIN-MULTIUSER.md)。
- **M2i Jellyfin 权限：完成隔离验证。** test2 无媒体库时扫描 0，恢复后 2；不泄漏其他用户内容。UI 用户切换/并发/HTTPS 未做。记录：[M2i 验收](Docs/M2I-JELLYFIN-PERMISSIONS.md)。
- **M4u 跨设备 HTTP 续播：完成 Mac→iPhone。** 新增 HTTP transport/`OPENFUSE_SYNC_URL`，Mac 播到11s推送，iPhone 启动拉取并 resume=10.02s、HUD 10.0/20.1；短片片尾保护改为10%时长。HTTP 无TLS/鉴权，CloudKit/真机未测。记录：[M4u 验收](Docs/M4U-HTTP-CROSS-DEVICE.md)。
- **M4v Jellyfin MP4 直连：完成并修正时间戳。** container 按逗号拆分识别 mp4，http(s) 统一 AVURLAsset header；手机样片改为首帧0s、`hvc1`+faststart，直连续播画面11.0s/HUD11.0s对齐。iOS OpenList/SMB MP4 回归通过。记录：[M4v 验收](Docs/M4V-DIRECT-MP4-RESUME.md)。
- **M4w 同步 token：完成鉴权。** HTTP transport 加 Bearer token，fixture 无 token 401；Mac→iPhone resume 11.0s。仍为 HTTP 明文，TLS/并发/CloudKit 真机未做。记录：[M4w 验收](Docs/M4W-SYNC-TOKEN.md)。
- **M4x Jellyfin 用户切换：完成。** Settings 增加用户列表/切换面板，CLI 可无头切换；清旧库后 test2 仍 2 作品、播放进度 11.042s 写入。修复删除来源未清 library 导致重复。记录：[M4x 验收](Docs/M4X-JELLYFIN-USER-SWITCH.md)。
- **M5an SMB >1GB：完成。** 1200s/1.4GB HEVC 文件在 Samba 上 seek 902s，RSS≈154MB、无整文件缓存。>2GB/并发/DFS/域未测。记录：[M5an 验收](Docs/M5AN-SAMBA-MULTIGB.md)。
- **M4y 同步 HTTPS：完成 Mac 验证。** HTTP transport 支持 `OPENFUSE_SYNC_CA` 固定自签 CA；curl 无 CA 拒绝，Mac HTTPS 同步完成。iPhone CA 分发/公共 CA/并发未测。记录：[M4y 验收](Docs/M4Y-SYNC-HTTPS.md)。
- **M4z iPhone HTTPS：完成 CA 固定验证。** 测试 CA 复制到 app Documents，iPhone HTTPS GET/POST 并 resume 11.0s。无 CA 导入 UI/公共 CA/并发未做。记录：[M4z 验收](Docs/M4Z-IOS-SYNC-HTTPS.md)。
- **M5ao SMB >2GB：完成。** 1800s/2.4GB HEVC 文件在 Samba 上 seek 1202s，RSS≈113MB、无整文件缓存。>4GB/并发/DFS/域未测。记录：[M5ao 验收](Docs/M5AO-SAMBA-2GB.md)。
- **M5ap SMB 并发：修复并验证。** 4 槽满时 accept 后直接 close 导致 5/8 Range 重置；改为先取信号量再 accept，8/8 返回 206，播放继续1202s。更高并发/长稳/DFS未测。记录：[M5ap 验收](Docs/M5AP-SAMBA-CONCURRENCY.md)。
- **M5aq SMB 16并发：完成。** 3批×16共48个 Range 全部206、播放继续1202s、RSS 128→112MB。>16/长稳/DFS未测。记录：[M5aq 验收](Docs/M5AQ-SAMBA-CONCURRENCY-16.md)。
- **M6e 实际音频输出：完成客观验证。** iFlyrec/BlackHole 2ch 录到回放 mean -24.5dB；输出切内置扬声器时虚拟设备 -91dB 静音，证明路由生效；源 E-AC-3 6ch。物理5.1/人耳/HDMI未测。记录：[M6e 验收](Docs/M6E-AUDIO-OUTPUT.md)。
- **M5ar SMB 32并发：修复并验证。** listen backlog 16 导致 21/32；改为128后 32/32 Range 206、播放继续1200s、RSS 211MB稳定。>32/长稳/DFS未测。记录：[M5ar 验收](Docs/M5AR-SAMBA-CONCURRENCY-32.md)。
- **M5as SMB 64并发：完成。** 64/64 Range 206、播放继续1202s、RSS 167→158MB；backlog128/4活跃槽可承受。>64/长稳/DFS未测。记录：[M5as 验收](Docs/M5AS-SAMBA-CONCURRENCY-64.md)。
- **M6f 同步设置 UI：完成。** Settings 增加 URL/Bearer Token/CA 导入/保存并同步；URL/CA 存 UserDefaults、Token 存 Keychain，CA 复制到 Application Support；设置驱动 HTTPS 同步验收通过。UI 点击/公共 CA/并发未测。记录：[M6f 验收](Docs/M6F-SYNC-SETTINGS.md)。
- **M5at SMB 长稳：完成。** 2.4GB 播放期间12轮×8 Range共96请求全部206，RSS188→83MB。小时级/DFS未测。记录：[M5at 验收](Docs/M5AT-SAMBA-SOAK.md)。
- **M6g iPhone 同步设置：完成。** 移动端 Sources 增加 URL/token/CA；URL/CA 存 UserDefaults、Token 存 Keychain；无 env URL/CA 时从设置 HTTPS 同步并 resume11.0s。UI 点击/公共 CA/并发未测。记录：[M6g 验收](Docs/M6G-IOS-SYNC-SETTINGS.md)。
- **M6h iPad 布局：完成冒烟验证。** iPad 常规宽度显示 NavigationSplitView（侧栏+详情），截图 YAVG24.6；冷启动约15s、点击播放/横屏/多任务未测。记录：[M6h 验收](Docs/M6H-IPAD-LAYOUT.md)。
- **M6i tvOS 播放：完成。** 修复 autoplay 对 groups 的等待；Apple TV 模拟器实际播放样片1.79s/19s，控制栏可见。遥控导航/远程来源/真机未测。记录：[M6i 验收](Docs/M6I-TVOS.md)。
- **下一项：** M6j/M5au：tvOS 遥控导航/远程来源；物理5.1/HDMI；HDR测量；小时级/DFS；CloudKit/visionOS。

开发入口：

```bash
brew install mpv
Scripts/install-libsmb2.sh   # SMB 来源（无 Homebrew formula）
Scripts/make_fixtures.sh    # 生成 60 s 测试片到 Fixtures/generated/
Scripts/build-app.sh        # 产出 build/OpenFuse.app
swift test                  # 核心单元测试
Scripts/test-webdav.sh              # 本地 WebDAV 协议检查
Scripts/run-webdav-acceptance.sh    # WebDAV 播放/拖动/续播端到端
Scripts/test-jellyfin.sh            # 本地 Jellyfin 协议检查
Scripts/run-jellyfin-acceptance.sh  # Jellyfin 播放/版本/进度/续播端到端
Scripts/run-library-acceptance.sh   # 本地/WebDAV/Jellyfin 扫描、合并、详情、搜索、播放
Scripts/test-tmdb.sh                # TMDB 搜索/海报协议检查
Scripts/run-tmdb-acceptance.sh      # TMDB + NFO 元数据与 WebDAV 海报库
Scripts/run-editing-acceptance.sh   # 手动纠错持久化/清除
Scripts/run-scan-stress.sh          # 10,000 条目扫描、取消与旧库保留
Scripts/run-manual-merge.sh         # 手动合并/拆分与分组持久化
Scripts/run-webdav-metadata.sh      # WebDAV NFO 与认证海报缓存
Scripts/run-library-filters.sh      # 排序/类型筛选/搜索组合
Scripts/build-ios.sh                # iPhone/iPad（XcodeGen + xcodebuild）
Scripts/build-platforms.sh          # iOS/iPadOS + tvOS + visionOS 构建
Scripts/test-auth-asset.sh          # WebDAV Basic Auth 远程 MP4 加载/播放
Scripts/test-jellyfin-mobile.sh     # Jellyfin 认证/PlaybackInfo/token AVPlayer
Scripts/test-jellyfin-hls.sh        # Jellyfin HLS 转码（MKV 源）
Scripts/test-webdav-recovery.sh     # WebDAV 504 目录旧库保留
open build/OpenFuse.app
```

当前分支 `m6i-tvos`（基于 M6h 提交）。Mac 构建时依赖 Homebrew 的 libmpv；`Scripts/package-app.sh` 会把它与 49 个依赖打进 `Contents/Frameworks`，生成可脱离 Homebrew 运行的自包含 app。iOS 构建依赖 XcodeGen 与 Xcode，不需要 libmpv（当前 AVPlayer 路径）。


## 第一个可以日常使用的 Mac 版本

| 用户操作 | 交付时要看见的结果 |
| --- | --- |
| 在文件页添加 OpenList 的 WebDAV 根目录，打开百度网盘 | 可以沿原有目录找到电影或电视剧。浏览一个目录后即可播放，后台继续建立海报库 |
| 添加 Jellyfin，切换到服务器直连浏览 | 独立显示电影库和电视剧库。打开剧、季、集能看到服务器提供的标题、海报、集序和音字幕轨 |
| 打开《性爱自修室》S01E01 | 对标 Pro 的播放体验。HEVC Main 10 MKV 和唯一的 E-AC-3 5.1 音轨能一起播放，Mac 扬声器可听清对白，兼容的多声道设备保留声道 |
| 打开《进击的巨人》，切换外挂字幕 | 第二季的中日双语 ASS 可以渲染汉字和排版。第三季有简繁双轨的集数能手动选轨，拖动后字幕仍对应当前台词 |
| 退出播放器，再从首页继续观看 | 返回原剧集和播放位置，保留音轨与字幕选择。文件夹层级和海报库分类可以分别浏览 |

第一版优先提供个人自用的完整播放能力。免费态提示、Pro 权益界面和购买恢复另设对照用例，使用测试权益切换。收费方式、实际售价和公开发行渠道留作产品决策。

## 初始全平台路线（历史规划）

以下人周是规划估算，假设一名熟悉 Swift 和音视频的工程师全职开发，已有 Mac，以及可用的测试媒体和账号。M0–M3 合计约 **9–16 人周**。跨平台后续阶段按设备、协议和服务分别估算，首轮实测后再给出总排期。

| 阶段 | 前置条件 | 开发工作 | 完成条件 |
| --- | --- | --- | --- |
| M0　参照与选型，1–2 人周 | 参考客户端、同一组可合法测试的素材 | 记录 Mac 的版本、窗口、语言、权限及 Free/Pro 状态。走通首次添加源到退出续播。用两种播放路径试播同一片段，测开发包、硬解、ASS、HDR 和画中画可行性 | 有逐步操作记录、首组参照图、音画测量表、引擎选择记录。缺设备或权益的项目逐项标为待验证 |
| M1　Mac 本地播放，2–4 人周 | M0 的测试媒体和引擎结论 | 建立原生应用、导入文件、播放器、轨道选择、外挂发现、字体回退、时间线拖动、全屏、窗口恢复与本地进度 | 本地通过 T01、T03、T04 的播放部分。重复开关影片和切轨，音频会话、文件句柄、字幕均随会话释放 |
| M2　远程播放，3–5 人周 | M1 有可插入的数据源接口 | 接 WebDAV 与 Jellyfin Direct Mode；完成目录分页、远程鉴权、Range、缓存、重新连接、播放协商和观看进度回写 | T01–T04 对适用来源通过，T05 的直连与转码部分通过。记录点播到首帧的分段耗时。扫描或下载期间拖动仍可优先读取目标位置 |
| M3　Mac 媒体库，3–5 人周 | M2 可稳定枚举文件与服务器条目 | 实现聚合媒体库、TMDB 识别、局部刷新、电影多版本、剧季集、详情、搜索、手工纠错、继续观看。按参照收敛 Mac 核心页面 | 新安装后从添加源走到下集续播；T05 的聚合库部分、T06、T07 和 Mac 核心页面对照通过。用真实目录核验误归类与漏字幕两条回归 |
| M4　家庭设备与状态同步 | M3 的条目标识和进度模型稳定 | iPhone 触控与后台恢复、iPad 分屏与键盘、Apple TV 遥控焦点与 Top Shelf；接入 CloudKit、Trakt、离线队列、账号隔离和家长控制 | T08–T10 及各端导航通过；在两台真机完成从 Mac 暂停到另一设备续播，以及反向手动重看的回写 |
| M5　其余来源与高级播放 | M2 协议接口和 M3 库模型稳定，可与 M4 分支推进 | 按矩阵补齐 SMB 等协议、Plex、Emby、原生网盘、投屏、光盘目录、高动态范围及音频路由、下载传输、外部 API；逐项对照 Free/Pro 状态 | 每个来源至少有一次登录、浏览、播放、拖动、失效恢复的记录。格式与设备组合有真实输出证据；T11–T13 通过 |
| M6　Vision Pro 与全范围验收 | 播放接口稳定即可做原型，收尾依赖 M4、M5 | 窗口及沉浸环境、空间输入、字幕位置与亮度、设备能力降级；复核五端设置、辅助功能、交互细节与适用版本 | T14 及全矩阵适用项都有结果。列出设备、版本、素材摘要、实现提交与差异处置，逐项判断能否宣称一致 |

### 第一周可直接开始的工作

1. 在一台 Mac 上创建空白参考资料库。选一部电影、一部两季剧、一个重复版本、一份无匹配的家庭视频。使用相同的自制封面与标题，固定语言、主题和窗口尺寸。在参考应用依次走文件夹浏览、海报详情、切字幕、退出、续播，记录每一步。
2. 制作带时间码、六声道语音报号和两套中日字幕的短片。保存输入参数和散列。另备 CJK 字体缺失、无语言标签、简繁标签三种字幕。这样可以在没有远程账号的情况下重现最常见的播放问题。
3. 在同一 Mac 上验证 AVPlayer 和 libmpv 候选路径。分别记录本地及远程 MKV 的首帧、实际解码器、音轨输出、时间线拖动、ASS 附件字体，再跑一次 HDR 与画中画。把选型理由和未覆盖组合写入决策记录。
4. 做一条可安装的最小流程。通过系统文件选择器打开测试片，播放、切换字幕、退出、再次打开。将画面与参考截图并排检查，留下首个可重复对比的构建。
5. 在独立测试库准备只读媒体来源和可写观看进度的测试账号。将同一片段放在本地、WebDAV、Jellyfin 三处，让 M2 能定位问题发生在取流、解码还是渲染。

## 技术设计与容易返工的决定

**客户端与播放器。** 候选为 Swift、SwiftUI 和按平台需要嵌入的原生播放视图。应用层维护一份播放会话，记录条目、版本、播放位置、轨道偏好、播放路径和结束原因。原生 AVFoundation/VideoToolbox 路径重点验证硬解、色彩、画中画和系统输出；libmpv、FFmpeg、libass 路径重点验证 MKV、复杂字幕与附件。M0 用实测决定单引擎或双引擎。若要切换路径，交接时间、音量及轨道标识，旧会话停止后再输出声音。分别记录所用构建选项、第三方依赖和分发条件。[mpv 构建与许可说明](https://github.com/mpv-player/mpv/blob/master/Copyright) · [libass](https://github.com/libass/libass)

**远程来源。** 文件来源提供列目录、取属性、打开字节范围及发现同名附件；媒体服务器额外提供库层级、条目 ID、可播放版本、轨道及进度接口。WebDAV 枚举一层目录，保留 Unicode、空格和百分号的往返一致性。签名地址保存在短生命周期会话中，重新解析时校验文件版本。以 206 与 Content-Range 校验分段读，对返回 200、416、限流和过期分别处理。拖动时先取消旧预读，再填目标区间。跨域重定向时只携带目标获准接收的凭据。后台扫描为播放让出连接和带宽。

**Jellyfin 的两种模式。** Direct Mode 首页按需请求服务器视图、条目和详情，打开集数就能播放。Library Mode 分页摄入选定资源库，允许聚合与离线浏览。两种模式都保留服务器的命名、图片和 ID。根据 PlaybackInfo 选择原片、重封装或服务端转码，绑定所选版本及轨道，发送开始、进度和停止事件。转码途中换轨或拖动时以新的时间基准恢复。Plex 与 Emby 分别实现和验证各自的登录、版本选择、用户切换及进度语义。[Firecore 媒体服务器指南](https://support.firecore.com/hc/en-us/articles/360006462093-Streaming-from-Plex-Emby-and-Jellyfin)

**媒体库与索引。** 用 SQLite 区分作品、季集、发行版本、来源文件和用户状态。同一作品可对应多个清晰度和多个文件来源；每个文件保留独立路径、技术信息和字幕。服务器条目以来源实例和服务器 ID 定位。WebDAV 优先用稳定资源 ID，缺少时用路径与文件属性重认领，匹配不唯一时保留候选。扫描按目录分页提交事务，完整枚举后才处理消失条目。超时保留旧记录，新增同名外挂时只重算相邻影片的轨道。手动匹配单独持久化。来源为文件夹时按设置合成本地 NFO、封面与 TMDB；用可查看的来源字段解释为何得到该标题。[媒体库索引](https://support.firecore.com/hc/en-us/articles/27862264977047-Library-Scanning-Indexing) · [本地元数据覆盖](https://support.firecore.com/hc/en-us/articles/4405042929559-Overriding-Artwork-and-Metadata)

**进度与同步。** 状态按用户、作品或集、播放版本存储；观看会话带唯一标识。暂停、拖动、停止、标记未看和重看各有语义。用持久队列和事件标识处理网络重试，避免旧设备退出事件覆盖较新的手动重看。在媒体服务器模式中明确其观看状态的权威来源，逐项实测 Trakt 回传方向。离线先保存本地，重连比对双方版本。Keychain 保管凭据，iCloud 数据与设备专属授权分别处理。通过两个账号、两个设备和一次离线冲突验收。[iCloud 同步范围](https://support.firecore.com/hc/en-us/articles/115000070773-iCloud-Sync) · [多用户行为](https://support.firecore.com/hc/en-us/articles/33562286594071-Multiple-User-Profiles)

**画质、字幕与声音。** 按编码、封装、动态范围、操作系统和输出设备建立播放能力表。记录输入元数据、选用的路径、显示器实际模式、接收端报告的声道和格式。ASS 验证时间戳、内嵌字体、系统回退、双语定位、描边和卡拉 OK 动效；图形字幕按原始画布缩放。使用声道报号片区分立体声下混、多声道 PCM、E-AC-3 Atmos 等结果。借用或取得可验证的真机前，相关行维持待验证。[字幕指南](https://support.firecore.com/hc/en-us/articles/215090967-Using-Subtitles) · [音频能力与输出](https://support.firecore.com/hc/en-us/articles/217735707-Audio-Options-Capabilities)

## 项目风险和取舍

| 风险 | 尽早取得的证据 | 对排期的影响 |
| --- | --- | --- |
| 能正常解码，接上电视后 HDR 或多声道输出异常 | M0 在实际显示器和接收器上测一个 HDR 样本及一套声道样本；记录设备协商结果 | 决定原生播放路径、配套测试设备与高级格式开发顺序 |
| 网盘拖动很慢，后台扫描只会加剧等待 | 在同一文件上比较本地、受控 HTTP 和真实 WebDAV，分开测解析链接、首字节、首帧及拖动 | 先定位瓶颈，再选缓存块尺寸和并发数 |
| 文档只描述功能，未说明按钮位置、默认值和异常行为 | M0 先测所有 Mac 核心流程；其余端进入开发时用相同夹具重复采样 | 缺参照的页面保留待采样状态，单列阻塞设备或 Pro 权益 |
| 外部服务、编解码器授权或分发渠道限制能力 | 用项目自己的开发账号验证 TMDB、字幕、投屏和网盘 API；按实际二进制构建核对许可。如决定上架，再评估原创品牌与商店设计要求 | 缺账号、授权或硬件的功能保留在矩阵，不能计入已完成覆盖率。[TMDB API 说明](https://developer.themoviedb.org/docs/faq) · [Apple 审核指南 §4.1](https://developer.apple.com/app-store/review/guidelines/#copycats) |

使用 OpenFuse 的名称、标识、图标及自行制作或取得授权的素材。使用相同的测试封面、系统字体和系统控件进行视觉比对，参照截图用于内部核验。个人服务器地址、影片、口令、授权令牌、签名链接和含个人信息的截图保存在仓库外。自动化使用本地夹具，实际媒体库使用独立测试账号。
