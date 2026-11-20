# OpenFuse 开发计划

目标是让使用 Infuse 的人换到 OpenFuse 后，能用熟悉的入口、操作顺序和播放设置完成同一件事，得到相同的画面、声音、字幕、媒体库和续播结果。对标包含 Infuse Pro。验收同时看界面和实际输出，例如影片详情显示「5.1」后，还要在六声道测试片上逐个听到正确的声道。

以 **2026-11-19 查阅的 Infuse 8.5.10** 为首个固定参照。覆盖 macOS、iOS、iPadOS、tvOS 和 visionOS。Mac 先交付，因为它可以用一台机器验证 WebDAV、Jellyfin 和本地文件三条路径。后续参考版本单独登记变更，已有用例保留基线版本。这个提交交付的是开发与验收计划，初始状态为待实现、待实机对照。[Infuse 发布记录](https://firecore.com/releases)

**两份文档配合使用。** 本页安排实现顺序、技术决策和每阶段的交付条件。[功能与验收矩阵](PARITY.md)列出对照对象、界面测量方法和可以直接执行的测试。

## 当前进度（2026-11-19）

- **M0 引擎与素材：完成。** AVPlayer 无法打开 Matroska（0 轨、0 s、无首帧）；libmpv 0.42.0 可播放、可定位，应用内启用 VideoToolbox 硬解。测试片由脚本生成：HEVC Main 10、E-AC-3 5.1、中日双语 ASS，文件级 24/24 声道报号校验通过。记录：[引擎选型](Docs/ENGINE-DECISION.md)、[测试素材](Docs/TEST-MEDIA.md)。
- **M1 Mac 本地播放：首个可用版本。** 可打开 MKV、出画面/出声、切换外挂简繁 ASS、缺字体回退、拖动、全屏、退出后从上次位置续播，关闭播放器再打开可重建会话。构建与实测见 [M1 验收记录](Docs/M1-ACCEPTANCE.md)。
- **M2 WebDAV + Jellyfin Direct：完成本地验证。** WebDAV 可添加来源、按真实目录浏览、直放、远程 ASS、限速拖动与续播。Jellyfin Direct 可登录、浏览电影/剧/季/集、使用服务器封面与版本、直连播放、保留服务器音轨/字幕命名、回写开始/进度/停止并用服务器位置续播。两者均提供本地协议夹具与端到端脚本。真实 OpenList、百度网盘与真实 Jellyfin 账号未提供，相关组合标为「待验证」。记录：[M2a WebDAV](Docs/M2-WEBDAV.md)、[M2b Jellyfin](Docs/M2-JELLYFIN.md)。
- **M3a 聚合媒体库：完成本地验证。** SQLite 媒体库、本地/WebDAV/Jellyfin 扫描、电影/剧/季/集、跨来源合并展示、Jellyfin 服务器封面、电影多版本、详情、搜索、从媒体库播放与来源切换。记录：[M3a 媒体库验收](Docs/M3-LIBRARY.md)。
- **M3b 元数据：完成本地验证。** TMDB 搜索（env key）补片名/年份/简介/海报，本地 NFO（movie/tvshow/episode）优先且可跳过 TMDB，WebDAV 作品扫描后可用 TMDB 海报进入海报库。真实 TMDB key 未提供，夹具验证。记录：[M3b 元数据验收](Docs/M3B-METADATA.md)。
- **M3c 集级版本合并：完成本地验证。** 电影合并 Jellyfin 多版本 + 本地 + WebDAV 为 4 个版本；剧集按季/集合并，S01E01 3 个版本、S01E02 2 个；详情用版本菜单选择来源播放。记录：[M3c 版本合并验收](Docs/M3C-VERSIONS.md)。
- **M3d 手动纠错与扫描：完成本地验证。** 详情可改标题/年份/简介/海报并持久化/清除；扫描可取消并显示进度，取消保留旧库；10,000 条目完整扫描 6.52 s，取消后旧库 10,000 条不变。记录：[M3d 编辑/扫描验收](Docs/M3D-EDIT-SCAN.md)。
- **M3e 手动整理：完成本地验证。** 详情可把同类型作品手动合并、拆分或恢复自动分组；分组键持久化；编辑信息可搜索 TMDB 候选并一键填入标题/年份/简介/海报。记录：[M3e 手动整理验收](Docs/M3E-MANUAL.md)。
- **M3f WebDAV 元数据：完成本地验证。** WebDAV 扫描下载 NFO，使用 movie/tvshow/单集 NFO 的标题/简介/海报；海报经 Basic Auth 下载并缓存，海报库不再依赖 TMDB。记录：[M3f WebDAV NFO 验收](Docs/M3F-WEBDAV-NFO.md)。
- **M3g 媒体库排序/筛选：完成本地验证。** 标题/年份/最近添加/集数排序，电影/剧集筛选，搜索组合；`addedAt` 来自本地 mtime、WebDAV mtime、Jellyfin DateCreated。记录：[M3g 排序筛选验收](Docs/M3G-FILTERS.md)。
- **尚未完成：** 防剧透、观看状态/分辨率筛选、继续观看排序、T07 扫描中播放/超时恢复、真实 OpenList/Jellyfin 验证、Infuse 同机对照与人工听测、其他 Apple 平台。
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
- **下一项：** M4o：visionOS runtime 实际启动（约 86%）、音频听测、外挂简繁切换、自动播放时序稳定化、CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率。

开发入口：

```bash
brew install mpv
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

当前分支 `m4n-jellyfin-subs`（基于 M4m 提交）。Mac 构建依赖 Homebrew 的 libmpv；iOS 构建依赖 XcodeGen 与 Xcode，不需要 libmpv（当前 AVPlayer 路径）。自包含打包留到发行阶段。


## 第一个可以日常使用的 Mac 版本

| 用户操作 | 交付时要看见的结果 |
| --- | --- |
| 在文件页添加 OpenList 的 WebDAV 根目录，打开百度网盘 | 可以沿原有目录找到电影或电视剧。浏览一个目录后即可播放，后台继续建立海报库 |
| 添加 Jellyfin，切换到服务器直连浏览 | 独立显示电影库和电视剧库。打开剧、季、集能看到服务器提供的标题、海报、集序和音字幕轨 |
| 打开《性爱自修室》S01E01 | 对标 Pro 的播放体验。HEVC Main 10 MKV 和唯一的 E-AC-3 5.1 音轨能一起播放，Mac 扬声器可听清对白，兼容的多声道设备保留声道 |
| 打开《进击的巨人》，切换外挂字幕 | 第二季的中日双语 ASS 可以渲染汉字和排版。第三季有简繁双轨的集数能手动选轨，拖动后字幕仍对应当前台词 |
| 退出播放器，再从首页继续观看 | 返回原剧集和播放位置，保留音轨与字幕选择。文件夹层级和海报库分类可以分别浏览 |

第一版优先提供个人自用的完整播放能力。免费态提示、Pro 权益界面和购买恢复另设对照用例，使用测试权益切换。收费方式、实际售价和公开发行渠道留作产品决策。

## 交付路线

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
