# Infuse 8.5.10 功能与验收矩阵

本表服务于[开发计划](README.md)。每项先在同一系统、设备、账号状态和媒体下操作 Infuse，再操作 OpenFuse。官方资料用来确定覆盖面，实机记录用来确定默认值、交互路径和可见输出。以下是待执行的规格和测试；本次建库只核对了公开文档。

## 如何判断「一模一样」

1. **固定输入。** 每次记录参考应用版本与 build、系统版本、设备和显示器、逻辑分辨率、显示缩放、语言、主题、内容源、文件散列、连接条件及权益。首次安装、缓存命中和已经看过三种起始状态分别采样。跨平台时为每个端建立自己的参照。
2. **采集页面。** 用同一套确定性资料库记录首次启动、添加源、首页、文件列表、媒体库、搜索、电影详情、剧季集、播放控制层、音轨/字幕菜单、设置、下载及权益页。每页覆盖空、载入、正常、错误和重新进入等适用状态。测量控件位置、字号、行距、卡片比例、可见项数、截断、滚动位置和焦点顺序。用录屏确定转场时长、手势阈值、浮层自动隐藏和返回后的焦点。
3. **比较结果。** 以同尺寸截图叠加、图像差异图、辅助功能树和操作录像定位差异。仅遮盖时钟、动态海报和自有品牌等事先列出的区域。每项写出期望、实测、影响、责任阶段、复测结果。建议初始排错阈值为静态布局坐标差超过 1 个逻辑点，转场差超过参考录制的 1 帧；阈值以内的可见差异仍可登记。播放画面、声道与字幕另测。
4. **关闭差异。** 每条按「待采样 → 参照已记录 → 已实现 → 对照通过」推进。设备缺失、第三方授权缺失、实测差异分别标记。平台无此功能时保存来源或实机证据。任何已知差异都单列；阶段结束统计已通过、适用总数、未知及差异数。宣称覆盖整个固定版本前，所有适用项须完成复测；已接受的产品差异仍要在发布说明逐项披露。

建议记录格式为一行一个测试组合，可直接复制此表。源文件放在个人测试目录，Git 中保留脱敏结果、合成夹具描述和构建标识。

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T03 | Mac／待填／Pro | 可再分发的双语 ASS 样片／本地／首次打开 | 待采样，含字幕出现及消失的时间码 | 待实现 | 待填 | 待采样 |

### 本轮执行记录（2026-11-19，M1 本地播放）

只记录已经实际跑过的组合；没有 Infuse 同机对照的格子保持「待采样」，不把 OpenFuse 单侧结果当通过。全部证据与命令见 [M1 验收记录](Docs/M1-ACCEPTANCE.md)。

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T01（本地部分） | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 60 s HEVC Main 10 + E-AC-3 5.1 夹具／本地／首次打开 | Infuse 未安装，待采样 | `m1-local-playback`：出画，VideoToolbox 硬解；输入 6ch 5.1，CoreAudio 输出 2ch；抓帧 13.458 s 与报告一致 | Evidence 03；reports/m1-zh-hans.json | 部分通过（人耳听测、Infuse 对照待做） |
| T03（本地播放部分） | 同上 | 同目录 zh-Hans／zh-Hant／无标签 ASS；缺字体 NOTE 样式 | 待采样 | 三轨均被发现；9.917 s 冻结时简繁字形不同；4.417 s 缺字体仍出中文；拖动后字幕与时间码一致 | Evidence 04–06；reports/m1-zh-hans.json、m1-zh-hant.json、m1-font-fallback.json | 部分通过（参照逐帧比对、PGS 等未测） |
| T04（外挂与切轨部分） | 同上 | 同一集简繁两份 ASS + 不匹配主名的对照 | 待采样 | 简繁切换成功；不匹配文件被单元测试拒绝；增量刷新与服务端已收录后的刷新未实现 | Evidence 04–05；`swift test` | 部分通过（M3 增量刷新待做） |
| 续播（T08 本地前置） | 同上 | 本地夹具，退出后重开 | 待采样 | 25.000 s 保存；重开从 25.0 s 继续，4 s 后 28.458 s；字幕偏好保留 | reports/m1-resume-before/after.json、playback-store.json | 本地通过；跨设备待 M4 |
| 关闭重开 | 同上 | 同进程内关闭播放器再打开 | 待采样 | 渲染上下文重建，新会话从保存位置继续，无崩溃 | 运行日志 | 通过（一次） |

### M2a WebDAV 执行记录（2026-11-19）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T02（WebDAV Range） | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 60 s 夹具／本地 WebDAV 夹具，700 KB/s 限速 | Infuse 未安装，待采样；参照需补签名地址过期、限流、断流、无 Range | 初始 GET 在 9,175,040 字节取消，新 Range 从 14,531,875 字节继续，冻结 41.042 s | `reports/m2-webdav-range-log.jsonl`、Evidence 11 | 本地通过；真实服务待验证 |
| T01（远程部分） | 同上 | 同片／WebDAV 直连／首次打开 | 待采样 | 60.000 s、HEVC Main 10、VideoToolbox、E-AC-3 5.1；远程 `zh-Hans` 自动选中；9.958 s 帧与字幕一致 | `reports/m2-webdav-play.json`、Evidence 09 | 部分通过（真实 OpenList/听测待做） |
| T04（远程外挂与切轨） | 同上 | 同目录三份 ASS／WebDAV | 待采样 | 远程 `zh-Hant` 切换成功，9 loci 字形与本地一致 | `reports/m2-webdav-zh-hant.json`、Evidence 10 | 部分通过 |
| 续播（远程） | 同上 | 播放到 25.083 s 退出，从首页记录重开 | 待采样 | 从 25.08 继续，6 s 后 30.583 s；来源与字幕偏好保留 | `reports/m2-webdav-resume.json` | 本地通过；跨设备待 M4 |
| 添加/浏览 | 同上 | 本地 WebDAV 根目录、Unicode 与 `100% 测试` 目录 | 待采样 | 来源卡片、Movies/Shows 浏览、Unicode 往返、401 拒绝错误密码 | Evidence 07–08；`Scripts/test-webdav.sh` | 本地通过；真实 OpenList 待验证 |

### M2b Jellyfin Direct 执行记录（2026-11-19）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T05（Direct 部分） | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 60 s 夹具／本地 Jellyfin 夹具／登录 test | Infuse 未安装，待采样 | 登录、2 个媒体库、电影/剧/季/集；PlaybackInfo 返回 2 个版本；直连播放 60 s、HEVC Main 10、VideoToolbox | `reports/m2-jellyfin-episode.json`、`m2-jellyfin-movie.json` | 部分通过（真实服务器、Library Mode 待做） |
| T01（Jellyfin 直连） | 同上 | 同片／Jellyfin `ep-1` | 待采样 | 9.917 s 冻结帧；服务器标题「第 1 集」；服务器音轨/字幕命名保留 | Evidence 15、18 | 部分通过（听测/真实服务器待做） |
| 版本选择 | 同上 | 电影两个 MediaSources | 待采样 | 选择 `ms-movie-compact`，服务端只流该 MediaSourceId | 服务端日志、`reports/m2-jellyfin-movie.json` | 本地通过 |
| 进度回写 | 同上 | 播放→暂停→退出 | 待采样 | Playing → Progress（4.7/9.7/9.917 s）→ Stopped（9.917 s），PlayMethod=DirectPlay | `reports/m2-jellyfin-server-log.jsonl` | 本地通过；冲突规则待 T08 |
| 服务器续播 | 同上 | 清空本地库，重开同一集 | 待采样 | 从服务器 9.917 s 起播，6 s 后 15.375 s | `reports/m2-jellyfin-resume.json` | 本地通过；跨设备待 M4 |
| 浏览 UI | 同上 | 电影库/电视剧库 | 待采样 | 封面、服务器名称、来源卡片 | Evidence 13–14 | 部分通过（像素对照待做） |

### M3a 媒体库执行记录（2026-11-19）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T06（目录与分组，部分） | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地 1 电影 + 2 剧 4 集；WebDAV/Jellyfin 同结构 | Infuse 未安装，待采样 | 本地扫描 3 作品/4 集；加 Jellyfin 原始 5/7；加 WebDAV 7/9；合并为 3 组，来源胶囊切换 | `reports/m3-library-*.json`、Evidence 19–21 | 部分通过（误匹配/重复版本/手工纠错未测） |
| T05（Library 聚合部分） | 同上 | Jellyfin 媒体库/剧/季/集 | 待采样 | Recursive 扫描保留服务器 Id/名称/封面/季集；电影 2 个版本；详情与播放 | Evidence 20–23；`m3-library-aggregate.json` | 部分通过（真实服务器、TMDB 待做） |
| 媒体库详情/搜索 | 同上 | 电影、剧集 | 待采样 | 剧集季选择、S01E01/02、简介；搜索「示例」只剩示例剧 | Evidence 21–22 | 部分通过 |
| 媒体库播放 | 同上 | 本地/WebDAV/Jellyfin 各一集 | 待采样 | 本地 9.958 s 冻结帧、外挂简体；WebDAV/Jellyfin 从库播放 sourceKind 正确 | `reports/m3-library-play.json`、Evidence 24 | 本地通过；真实服务待验证 |
| T07（首轮+恢复） | MacBook Pro M2 Pro／macOS 27.2.1 | 10,000 个空 MKV/嵌套目录；WebDAV 504 目录 | 待采样 | 10,000 扫描 6.52s、取消保留旧库；WebDAV 单目录 504 后 2 作品仍为 2 并显示失败目录数；未测扫描中播放/单文件失败 | `reports/m3d-scan-stress.json`、`reports/m3i-webdav-recovery.txt` | 部分通过 |

### M3b 元数据执行记录（2026-11-19）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T06（元数据部分） | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地夹具 + tvshow.nfo；TMDB 协议夹具 | Infuse 未安装，待采样 | 本地 3 作品：TMDB 2 匹配、NFO 1 覆盖；标题/年份/简介/海报正确 | `reports/m3b-tmdb-local.json`、Evidence 25、28 | 部分通过（真实 TMDB/手动匹配待做） |
| 海报库（WebDAV + TMDB） | 同上 | WebDAV 夹具 2 作品，无自带海报 | 待采样 | 扫描后 2 个作品均使用 TMDB 远程海报，海报网格可见 | `reports/m3b-tmdb-webdav.json`、Evidence 26 | 本地通过；真实 OpenList/TMDB 待验证 |
| 详情元数据 | 同上 | TMDB 电影 | 待采样 | 详情显示 TMDB 标题、简介、海报 | Evidence 27 | 部分通过 |

### M3c 集级版本合并执行记录（2026-11-19）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| T06（多版本，部分） | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地 + Jellyfin + WebDAV 同一电影/剧 | Infuse 未安装，待采样 | 电影 1 集 4 版本（Jellyfin 2 / 本地 / WebDAV）；剧集 S01E01 3 版本、S01E02 2 版本 | `reports/m3-library-aggregate-webdav.json` 的 `merged`、Evidence 29–30 | 部分通过（手动拆分/合并未做） |
| 版本选择/播放 | 同上 | 合并后的电影与剧集 | 待采样 | 电影版本 Picker；剧集每集版本菜单；选择后走对应来源播放 | Evidence 29–30 | 本地通过；像素对照待做 |

### M3d 手动纠错与扫描执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 手动元数据 | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地 3 作品 | Infuse 未安装，待采样 | 改标题/2024/简介/海报，重启后仍生效；清除恢复原值 | Evidence 31、`reports/m3d-edit-*.json` | 本地通过；合并/拆分未做 |
| 扫描取消/进度 | 同上 | 10,000 条目 | 待采样 | 扫描中显示 10,000 项与取消；取消空库 0、已有库保留 10,000 | Evidence 32、`reports/m3d-scan-stress.json` | 本地通过 |

### M3e 手动整理执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 手动合并 | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地 3 组（电影 + 2 剧） | Infuse 未安装，待采样 | 将《示例剧》并入《另一部剧》组，3→2 组；S01E01 出现 2 个版本 | Evidence 33、`reports/m3e-merge-applied.json` | 本地通过 |
| 拆分/恢复 | 同上 | 合并后的组 | 待采样 | 拆分当前作品，2→3 组；分组键与元数据覆盖可持久化 | `reports/m3e-merge-split.json` | 本地通过；扫描后保留未单测 |
| TMDB 候选 | 同上 | 编辑信息 sheet | 待采样 | `test-tmdb.sh` PASS，movie/tv 候选各 1 条；UI 点击填入字段 | 终端 | 部分通过（sheet 未截图、真实 key 未验证） |

### M3f WebDAV NFO 执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV NFO | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地 WebDAV 夹具含 movie/tvshow/集 NFO | Infuse 未安装，待采样 | 标题/年份/简介/单集标题来自 NFO；TMDB 不覆盖 | `reports/m3f-webdav-nfo.json`、Evidence 34–35 | 本地通过；真实 OpenList 待验证 |
| 认证海报缓存 | 同上 | WebDAV poster.jpg | 待采样 | 带 Basic Auth 下载 2 张海报到 PosterCache，库中 `file:` 引用且文件存在 | 脚本断言、Evidence 34 | 本地通过 |

### M3g 排序/筛选执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 类型筛选 | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地 3 组（电影+2 剧） | Infuse 未安装，待采样 | 电影筛选只剩 1 部；报告 visible 一致 | `reports/m3g-filter-movies.json`、Evidence 36 | 本地通过 |
| 集数排序 | 同上 | 同上 | 待采样 | 剧集按集数：《示例剧》2 集在《另一部剧》1 集前 | `reports/m3g-filter-series.json` | 本地通过 |
| 搜索+排序 | 同上 | 同上 | 待采样 | 「示例」只剩《示例剧》 | `reports/m3g-filter-search.json` | 本地通过 |

### M4a 移动端构建执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| iOS Simulator 构建 | MacBook Pro M2 Pro／macOS 27.2.1／Xcode 27.2 | `Fixtures/mobile/openfuse-mobile.mp4` | Infuse 未安装 | `xcodebuild -destination 'generic/platform=iOS Simulator'` → BUILD SUCCEEDED | `reports/m4-ios-build.txt` | 构建通过；运行待验证 |
| iOS device 构建 | 同上 | 同上 | 待采样 | `generic/platform=iOS` Release → BUILD SUCCEEDED | 同上 | 构建通过；真机待验证 |
| 移动 UI/播放/续播 | 同上 | 20s H.264/AAC 示例 | 待采样 | 无模拟器 runtime；启动、布局、触控、后台恢复、音频均未执行 | — | 待验证 |

### M3h 观看状态/防剧透执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 观看状态筛选 | MacBook Pro M2 Pro／macOS 27.2.1／自建 | 本地+Jellyfin+WebDAV，示例剧 S01E01 9.917s | Infuse 未安装，待采样 | 「观看中」只剩《示例剧》 | `reports/m3h-watch-in-progress.json` | 本地通过 |
| 最近播放排序 | 同上 | 同上 | 待采样 | 《示例剧》排第一 | `reports/m3h-watch-recent.json` | 本地通过 |
| 画质筛选 | 同上 | Jellyfin 电影 1080p/720p 版本 | 待采样 | 1080p 只剩电影；单集/本地无分辨率元数据 | `reports/m3h-watch-resolution.json` | 部分通过 |
| 防剧透 | 同上 | 《示例剧》观看中 | 待采样 | 详情/单集简介隐藏，点「显示」展开 | Evidence 37 | 本地通过 |

### M4b 移动端来源执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 移动端来源管理 | MacBook Pro M2 Pro／Xcode 27.2 | WebDAV/Jellyfin 夹具 | Infuse 未安装 | 添加/扫描/删除 UI；Keychain 存密码/token；扫描复用数据层 | `reports/m4-ios-build.txt` | 构建通过；UI/Keychain 待运行验证 |
| 移动端构建 | 同上 | 同上 | 待采样 | Simulator + device generic 均 BUILD SUCCEEDED；25/25 测试 | 同上 | 构建通过 |
| 移动端远程播放 | 同上 | Jellyfin/WebDAV 媒体 | 待采样 | 未接转码/HLS/鉴权代理，remote 条目提示待接入 | — | 待验证/未完成 |

### M4c iPad/tvOS/visionOS 构建执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| iPad 分栏 | MacBook Pro M2 Pro／Xcode 27.2 | 示例 MP4 + 媒体库 | Infuse 未安装 | 常规宽度 NavigationSplitView 侧栏+详情；构建成功 | `reports/m4-ios-build.txt` | 构建通过；布局待运行验证 |
| tvOS | 同上 | 示例 MP4 | 待采样 | 焦点网格 + AVPlayer；BUILD SUCCEEDED | 同上 | 构建通过；焦点/播放待真机或 runtime |
| visionOS | 同上 | 示例 MP4 | 待采样 | NavigationSplitView + 播放 sheet；BUILD SUCCEEDED | 同上 | 构建通过；空间布局待 runtime |

### M4d 认证远程播放执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV 认证加载 | MacBook Pro M2 Pro／macOS 27.2.1 | Basic Auth WebDAV + 20s MP4 | Infuse 未安装 | AVAsset 20.0s、1 视频轨、1280×720 | `reports/m4d-auth-asset.json` | 通过 |
| AVPlayer 实际播放 | 同上 | 同上 | 待采样 | 4 秒后 position 3.598s，无错误 | `reports/m4d-auth-play.json` | 通过（桌面 AVPlayer；移动端同链路待 runtime） |
| 错误密码 | 同上 | 同上 | — | asset load 报错 | 测试脚本 | 通过 |
| 移动端 UI/播放 | 同上 | iOS/tvOS/visionOS | 待采样 | Simulator/device 构建成功；无 runtime 未启动 | `reports/m4-ios-build.txt` | 构建通过；运行待验证 |

### M4e Jellyfin 移动远程执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Jellyfin 远程 MP4 | MacBook Pro M2 Pro／macOS 27.2.1 | 夹具 movie-mobile，H.264/AAC 20s | Infuse 未安装 | 认证/PlaybackInfo/api_key URL/loader；AVAsset 20s/1 轨；AVPlayer 6s 到 5.866s | `reports/m4e-jellyfin-remote.json`、`m4e-jellyfin-remote.txt` | 通过（桌面同链路） |
| 移动端 UI | 同上 | iOS/tvOS/visionOS | 待采样 | Simulator/device 构建成功；无 runtime 未启动 | `reports/m4-ios-build.txt` | 构建通过；运行待验证 |
| MKV/字幕/音轨 | 同上 | 现有 MKV 夹具 | 待采样 | 未接转码/libmpv/字幕/音轨 | — | 待验证/未完成 |

### M4f Jellyfin HLS 执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| MKV→HLS 播放 | MacBook Pro M2 Pro／macOS 27.2.1 | 同源 MKV 60s（HEVC/E-AC-3）→ H.264/AAC TS | Infuse 未安装 | Jellyfin HLS URL；AVPlayer 6s 到 5.954s，duration 60 | `reports/m4f-hls.json`、`m4f-hls.txt` | 通过（夹具转码） |
| 真实 Jellyfin 转码 | 同上 | 本地 Jellyfin 尚未配置 | 待采样 | 构造 URL 未在真实服务器验证 | — | 待验证 |

### M4g iOS 实际运行执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| iPhone 首屏 | iPhone 18 Pro Simulator／iOS 27.2 | 内置 H.264/AAC 20s | Infuse 未安装 | 1 作品/1 集，海报/标题正常 | Evidence 38 | 通过 |
| iPad 分栏 | iPad Pro 13-inch M5 Simulator／iOS 27.2 | 同上 | 待采样 | NavigationSplitView 侧栏 + 详情占位 | Evidence 41 | 通过 |
| 播放 | iPhone Simulator | 同上 | 待采样 | HUD 3.0/20.0s，画面时间码推进 | Evidence 39 | 通过 |
| 退出/续播 | 同上 | 自动 5s 关闭后重启 | 待采样 | 保存 4.795s；重启 3s 后 HUD 12.0/20.0s | Evidence 40、`reports/m4g-ios-run.txt` | 通过（画面；音频未听测） |
| 四平台构建 | Xcode 27.2 | 同上 | — | iOS/iPadOS/tvOS/visionOS/device 全部 BUILD SUCCEEDED | `reports/m4-ios-build.txt` | 构建通过 |

### M4h 移动端远程播放执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV 移动远程 | iPhone 18 Pro Simulator／iOS 27.2 | Basic Auth WebDAV + 20s MP4 | Infuse 未安装 | App 内添加/扫描/播放；服务器 HEAD/GET Range 206；HUD 11.0/20.0s | Evidence 42、`reports/m4h-mobile-remote.txt` | 通过（音频未听测） |
| Jellyfin 移动远程 | 同上 | Jellyfin MKV 60s + HLS | 待采样 | 登录/扫描/PlaybackInfo/master.m3u8；HUD 9.0/60.0s | Evidence 43 | 通过（音频未听测） |
| 移动 HLS 60s | 同上 | MKV→HLS 夹具 | 待采样 | Jellyfin movie-1 选中，移动端 AVPlayer HLS 9.0/60.0s | Evidence 43 | 通过 |
| 音频/字幕/音轨 | 同上 | 素材含 E-AC-3/ASS | 待采样 | 未做人工听测/字幕/音轨切换 | — | 待验证 |

### M3j 本地分辨率执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 本地 1080p 探测 | MacBook Pro M2 Pro／macOS 27.2.1 | 4 个本地 MKV | Infuse 未安装 | ffprobe 写回 4/4 版本 1080p | `reports/m3j-resolution.txt` | 通过 |
| 画质筛选 | 同上 | 本地 3 作品 | 待采样 | 「1080p」显示 3 作品（此前仅 Jellyfin 电影） | Evidence 44 | 通过 |
| 四平台构建 | Xcode 27.2 | 同上 | — | iOS/iPadOS/tvOS/visionOS/device 构建成功 | — | 通过 |

### M3k 流分辨率执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Jellyfin 单集分辨率 | MacBook Pro M2 Pro／macOS 27.2.1 | Jellyfin 夹具 | Infuse 未安装 | movie/ep-1/ep-2 均 1080p；1080p 筛选含电影+剧集 | Evidence 45、`reports/m3k-resolution-jellyfin.json` | 通过 |
| WebDAV MP4 分辨率 | 同上 | Basic Auth WebDAV 20s MP4 | 待采样 | 720p；720p 筛选命中 | `reports/m3k-resolution-webdav.json` | 通过 |
| WebDAV MKV 分辨率 | 同上 | MKV | 待采样 | AVFoundation 不支持，未取 | — | 待验证 |
| 四平台构建 | Xcode 27.2 | 同上 | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4k 远程字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV 字幕发现/下载 | iPhone 18 Pro Simulator／iOS 27.2 | WebDAV MP4 + 简/繁 SRT | Infuse 未安装 | 列目录、匹配、Basic Auth GET 200，缓存至 SubtitleCache | `reports/m4k-remote-subs.txt` | 通过 |
| 远程字幕画面 | 同上 | 同上 | 待采样 | 菜单选中简体；时间跳变未截到 cue | Evidence 51 | 部分通过/待修 |
| 本地字幕回归 | 同上 | 本地 SRT | 待采样 | M4j 简体/繁体/seek 截图通过 | Evidence 49–50 | 通过 |
| 四平台构建 | 同上 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4n Jellyfin 外挂字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 外挂字幕下载 | iPhone 18 Pro Simulator／iOS 27.2 | Jellyfin DeliveryUrl SRT | Infuse 未安装 | 带 token GET 200，缓存 | `reports/m4n-jellyfin-external-subtitle.txt` | 通过 |
| 外挂字幕画面 | 同上 | movie-1 HLS 60s | 待采样 | HUD 4.7/60.0，第一句字幕显示，菜单「外挂简体中文」 | Evidence 54 | 通过 |
| 音频 | 同上 | HLS 音频 | 待采样 | 未听测 | — | 待验证 |
| 四平台构建 | Xcode 27.2 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4m 远程 seek/Jellyfin 字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV 精确 seek | iPhone 18 Pro Simulator／iOS 27.2 | WebDAV MP4 + SRT | Infuse 未安装 | seek 10s，HUD 10.0/20.0，第二句字幕同步 | Evidence 53 | 通过 |
| 远程字幕同步 | 同上 | 同上 | 待采样 | 拖动后重算 cue，显示「第二句…」 | 同上 | 通过 |
| Jellyfin 外挂字幕 | 同上 | DeliveryUrl SRT | 待采样 | 下载管线已写；autoplay 返回主页，画面未验证 | `reports/m4m-seek-jfsubs.txt` | 部分通过/待验证 |
| 四平台构建 | 同上 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4n Jellyfin 外挂字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 外挂字幕下载 | iPhone 18 Pro Simulator／iOS 27.2 | Jellyfin DeliveryUrl SRT | Infuse 未安装 | 带 token GET 200，缓存 | `reports/m4n-jellyfin-external-subtitle.txt` | 通过 |
| 外挂字幕画面 | 同上 | movie-1 HLS 60s | 待采样 | HUD 4.7/60.0，第一句字幕显示，菜单「外挂简体中文」 | Evidence 54 | 通过 |
| 音频 | 同上 | HLS 音频 | 待采样 | 未听测 | — | 待验证 |
| 四平台构建 | Xcode 27.2 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4l 远程字幕画面执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV 远程时长 | iPhone 18 Pro Simulator／iOS 27.2 | WebDAV MP4 + SRT | Infuse 未安装 | 时长 20.0s（此前 0.0） | `reports/m4l-remote-subtitle.txt` | 通过 |
| 远程字幕显示 | 同上 | 同上 | 待采样 | pause-at 4.5s，HUD 4.6/20.0，显示第一句字幕 | Evidence 52 | 通过 |
| 远程 seek 同步 | 同上 | 同上 | 待采样 | seek 不稳定，未证明；用 pause-at 验证 | — | 待修 |
| 四平台构建 | 同上 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4n Jellyfin 外挂字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 外挂字幕下载 | iPhone 18 Pro Simulator／iOS 27.2 | Jellyfin DeliveryUrl SRT | Infuse 未安装 | 带 token GET 200，缓存 | `reports/m4n-jellyfin-external-subtitle.txt` | 通过 |
| 外挂字幕画面 | 同上 | movie-1 HLS 60s | 待采样 | HUD 4.7/60.0，第一句字幕显示，菜单「外挂简体中文」 | Evidence 54 | 通过 |
| 音频 | 同上 | HLS 音频 | 待采样 | 未听测 | — | 待验证 |
| 四平台构建 | Xcode 27.2 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4m 远程 seek/Jellyfin 字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| WebDAV 精确 seek | iPhone 18 Pro Simulator／iOS 27.2 | WebDAV MP4 + SRT | Infuse 未安装 | seek 10s，HUD 10.0/20.0，第二句字幕同步 | Evidence 53 | 通过 |
| 远程字幕同步 | 同上 | 同上 | 待采样 | 拖动后重算 cue，显示「第二句…」 | 同上 | 通过 |
| Jellyfin 外挂字幕 | 同上 | DeliveryUrl SRT | 待采样 | 下载管线已写；autoplay 返回主页，画面未验证 | `reports/m4m-seek-jfsubs.txt` | 部分通过/待验证 |
| 四平台构建 | 同上 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |

### M4n Jellyfin 外挂字幕执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 外挂字幕下载 | iPhone 18 Pro Simulator／iOS 27.2 | Jellyfin DeliveryUrl SRT | Infuse 未安装 | 带 token GET 200，缓存 | `reports/m4n-jellyfin-external-subtitle.txt` | 通过 |
| 外挂字幕画面 | 同上 | movie-1 HLS 60s | 待采样 | HUD 4.7/60.0，第一句字幕显示，菜单「外挂简体中文」 | Evidence 54 | 通过 |
| 音频 | 同上 | HLS 音频 | 待采样 | 未听测 | — | 待验证 |
| 四平台构建 | Xcode 27.2 | — | — | 全部 BUILD SUCCEEDED | — | 通过 |
| 移动端 UI | 同上 | iOS/tvOS/visionOS | 待采样 | 构建成功；无 runtime 未启动 | `reports/m4-ios-build.txt` | 构建通过；运行待验证 |




## 功能清单

每行是若干可拆分的验收项。M0 要沿参考应用的全部可达菜单补录设置、默认值、权限、内容依赖及 Free/Pro 差异。为协议、云服务、编解码格式与设备组合各建子项。官方技术规格与分平台发布记录保留为盘点入口。[产品技术规格](https://firecore.com/infuse) · [分平台版本记录](https://firecore.com/releases)

| 功能 | 实现与对照范围 | 重点验收 | 阶段 |
| --- | --- | --- | --- |
| 首次启动与文件 | 引导、添加本地文件与文件夹、直链、拖放、共享、收藏、文件管理、来源编辑和重连 | 撤销系统文件权限、错误密码、失效书签、只读来源操作；远程删除功能使用一次性测试副本 | M1–M5 |
| 首页与导航 | 自定义列表、继续观看、最近添加、收藏的显示/隐藏与排序、侧栏或标签栏、上下文菜单 | 同一资料库和排序下，首屏内容、进入层数、菜单顺序、返回位置、首页重开结果 | M3–M6 |
| 目录与网络 | WebDAV(S)、HTTP(S)、SMB、NFS、FTP、FTPES、FTPS、SFTP、UPnP/DLNA；局域网发现和手动添加 | 每个协议分别测列目录、读流、拖动、字幕可发现性及能力限制；中文、空格、多级路径、断线恢复 | M2、M5 |
| 媒体服务器 | Jellyfin、Emby、Plex 的 Direct/Library、账户与来源切换、版本选择、服务端播放列表及观看进度 | 服务端海报和自定义中文名，冷启动请求量，库大时的分页，直放/转码及轨道切换 | M2–M5 |
| 原生云盘 | 按固定版技术规格逐个登记供应商，包括百度、阿里、115、123、光鸭，以及 Google Drive、OneDrive、Dropbox、Box、pCloud、MEGA、Yandex Disk；单列 iCloud Drive 的系统入口 | 逐供应商实测授权、限流、令牌更新、临时地址和账号退出；另测经 OpenList 访问同一资源 | M5 |
| 媒体识别与组织 | TMDB、本地 NFO/XML、分季和特别篇、同名不同年、家庭视频、同片多版本、内嵌和外部图片、手工纠错 | 扫描打断后恢复、目录改名、季集合并、多版本回放、清缓存及增量刷新保留手工覆盖 | M3 |
| 资料库操作 | 搜索、排序与筛选、类型、分辨率、观看状态、合集、播放列表、海报与列表模式、防剧透、评分源排序 | 重复标题、中文关键词、组合筛选为空、拖动排序、跨源查询与重启持久化 | M3–M5 |
| 详情与连续播放 | 剧情、人员、海报、评分、预告片、季集、版本、章节、片头片尾标记、下一集、循环/随机 | 同剧缺集、看完季末、从头重看、有无跳过标记、长按选版本及记忆范围 | M3–M5 |
| 容器与视频 | 按格式表分别测试封装与编码；覆盖 MKV、MP4、MOV、TS/M2TS、WebM、ISO/IMG、BDMV、VIDEO_TS，及 H.264、HEVC、AV1、VP9、VVC 等。链接文件及 M3U/M3U8 播放列表单列 | 首帧、末段拖动、变帧率、交错、损坏或未知流、光盘主片与章节；播放列表还要核对相对路径及顺序 | M1、M5 |
| 显示与渲染 | 原比例、缩放、倍速、预览、帧率匹配、SDR、HDR10/10+、HLG、Dolby Vision P5/P8、升频和 AI 放大 | 记录每种输入在兼容和普通显示器的实际输出、亮度、色偏、丢帧与功耗；与同机参照比对 | M1、M5 |
| 音频 | AAC、AC-3、E-AC-3、DTS 系列、TrueHD、FLAC、PCM 等；内外音轨、音频延迟、耳机、扬声器和 HDMI | 实际输出声道、对白下混、E-AC-3 Atmos 和多声道 PCM 各自验证；切设备后画面与音频恢复 | M1、M5 |
| 字幕 | SRT、ASS/SSA、WebVTT、PGS/SUP、VobSub 等及官方格式表余项；内外轨、简繁语言标签、强制字幕、自动选轨、OpenSubtitles、轨道偏移、样式覆盖 | 附件字体和 CJK 缺字体回退、双语行位置、图形字幕缩放、字幕延迟、HDR 字幕亮度、切集后选择是否正确 | M1–M5 |
| 控制与系统集成 | 键盘、手势、遥控器、画中画、后台音频、锁屏控制、外接屏、AirPlay、Google Cast | 各端支持情况以实机为准；测锁屏恢复、切路由、投屏字幕和返回设备后续播 | M1、M4–M6 |
| 离线与传输 | 下载、队列、取消、续传、空间回收、同集字幕与离线播放、系统导入和浏览器传输 | 断网可播已完成下载；空间耗尽、中途退出、版本变化时可恢复；本地清理只影响目标副本 | M4–M5 |
| 观看状态与多用户 | iCloud、Trakt、服务端进度、评分、收藏、首页布局、手工匹配、家长控制、用户切换 | 离线重看、并发会话、重复回写、换人后首页和搜索隔离，资源受限时从深链进入也遵守可见范围 | M4–M5 |
| 扩展与权益 | 深链、x-callback 操作和局域网 Now Playing；分级权益、恢复购买、家庭共享、设置和辅助功能 | 使用 OpenFuse 自己的标识与 URL scheme；对照通知、参数、成功/失败回调的次序及内容。购买相关用沙盒场景核验 | M4–M6 |

跨端设置逐项记录适用范围，尤其是 macOS 多显示器、iPhone 后台音频、tvOS 首页与系统用户，以及 visionOS 沉浸影院的屏幕大小、角度和座位。云端进度、历史与收藏分别验收。第三方 API 的回调、权限与默认开关按公开契约复核。[设置总览](https://support.firecore.com/hc/en-us/articles/360015608854-Settings-Overview) · [沉浸环境](https://firecore.com/blog/infuse-83-immersive-mode-on) · [第三方接口](https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services)

## 首批端到端用例

测试账号的服务器可写状态与日常观看账号隔离。商业影片用于个人环境复验，自动化使用同编码、同结构的合成素材。下面引用的集数标识用户遇到过的场景，测试本身可以独立复现。

| ID | 起始条件与操作 | 检查结果和证据 |
| --- | --- | --- |
| T01　原片和唯一音轨 | 使用 HEVC Main 10、E-AC-3 5.1 单音轨 MKV，经本地、WebDAV、Jellyfin 原片入口各播一次，拖到中段，再切音频输出。以《性爱自修室》S01E01 做个人复验 | 三次都出画出声，Jellyfin 记录原片播放。六声道报号片核对声道映射，Mac 扬声器核对白。记录音轨、输出路由、首帧和拖动恢复时间 |
| T02　网盘远程拖动 | 提供可控的 WebDAV 服务和带签名的媒体地址，拖到 80%，令当前地址过期，再模拟一次限流、断流和不支持 Range 的服务端 | 支持范围读取时检查目标字节段及恢复位置，旧预读停止；其余情况对照参照端提示、重试行为和可达位置。诊断记录隐藏凭据 |
| T03　双语 ASS | 准备含英文内轨、无语言标签外挂、带 zh 标签外挂及缺字体样片。固定三处有中文、日文、数字的时间码；播放、拖动、全屏、再次打开。用《进击的巨人》第二季有外挂的集复验 | 对照轨道标签和选择记忆，逐帧比对指定台词的行数、基线、描边、字符与入出点。用画面证据验证字体；菜单显示出轨道后仍需检查渲染 |
| T04　第三季简繁与增量刷新 | 为同一集添加与视频同主名的 zh-Hans.ass 和 zh-Hant.ass，再只更新其中一份。分别测试独立目录扫描和 Jellyfin 已收录后的刷新；另放一份主名不匹配的对照字幕 | 能切换两条并看到不同字形，同一集元数据更新后可重读。分开记录服务端声明的轨道、客户端识别的附件和实际加载结果 |
| T05　Jellyfin 模式与选轨 | 建立两个独立资源库，服务器自定义片名和封面；分别冷启动 Direct 与 Library。用受控带宽选择服务器转码，在中段切字幕、切音轨、暂停退出 | 直连按需浏览，聚合库可使用缓存。标题和海报与服务器一致。播放记录包含路径、版本、轨道、版本切换后的时间点及唯一有效的结束事件 |
| T06　目录和海报分组 | 两部不同剧、同一剧的三个独立发布目录、一部电影、一组教程及一个重复清晰度。按文件夹打开，再进海报库，校正一次误匹配，杀进程后重新扫描 | 文件夹保留实际层级；剧、季、集与期望清单对应，电影独立。记录未匹配项、重复版本、手工修改保留情况 |
| T07　扫描压力 | 合成 10,000 个条目，先扫描一半并中断，恢复期间播放一集，重启后新增一份外挂，同时让另一个目录暂时超时 | 已完成页可浏览；记录恢复请求、重复条目、误删数量、目标条目更新耗时、播放停顿次数和索引大小 |
| T08　跨设备续播 | A 暂停在 12:30，B 接着看，到 14:00 后退出；A 离线选择从头重看，回到线上，再重复发送一次停止事件 | 比对作品、播放版本、续播位置、已看状态、下一集及两台设备最终一致性。冲突规则同时用参照端实测记录 |
| T09　家庭用户与权限 | 两个测试用户分别收藏不同影片；限制其中一方查看某目录，切换用户后经搜索、首页、深链进入并打开家长设置 | 对照每个入口的可见内容与验证步骤；播放进度、收藏和凭据按用户隔离 |
| T10　移动端、电视与离线 | iPhone 下载到一半切后台，恢复后断网播放；在 iPad 分屏切字幕并进入画中画；Apple TV 用遥控器由首页到下一集再返回 | 保存焦点路径和横竖屏截图，核对下载文件与字幕完整性、系统控制响应、退回后的焦点及断网提示 |
| T11　显示与投屏 | 固定 SDR、HDR10、Dolby Vision P5/P8 和带 Atmos 元数据的 E-AC-3 片段，分别用兼容与普通显示器。选择参考端支持的 AirPlay/Cast 组合，再断开 | 记录接收设备、动态范围、声道、实际投屏字幕、回到本机的播放位置；每个组合独立给出通过或差异 |
| T12　其余来源与格式 | 为每种协议和云供应商配置测试源，对同一片段验证授权、列目录、拖动及过期；ISO、BDMV、播放列表和其余编码按技术规格逐项执行 | 产生「来源 × 文件 × 平台」结果，记录层级、章节、顺序和回退；账号暂不可用时维持待验证 |
| T13　权益与对外接口 | 沙盒分别加载无权益、Pro、过期和恢复成功状态；通过深链启动临时播放列表、关闭播放器，再在启用与关闭 Now Playing 时发现服务 | 对照入口、提示、恢复后的能力、成功/失败回调次数和可见字段。实际定价独立登记 |
| T14　Vision Pro | 用凝视和捏合从资料库进入沉浸环境，调整屏幕与座位、切轨、退出到窗口 | 真机记录焦点、屏幕位置、字幕遮挡、环境切换时连续性及退出后的时间点 |

## 质量测量与发布判定

- **可比的性能。** 在同一设备交替运行两个应用，冷缓存和热缓存分开。对首屏、首帧、随机拖动分别先测 20 次并记录中位数及 P95；报告网速、RTT、媒体码率和输入源。工程初始目标是受控本地/LAN 下中位数不劣于参照的 10%，P95 不劣于 20%。远程网盘同时报告首字节时间，波动较大时按相邻样本配对重测。这些是项目目标值，参考端实测值待填。
- **播放与耐久。** 连播两小时，覆盖片头、片尾、下一集、字幕开关、十次随机拖动、睡眠唤醒和音频设备切换。记录每小时丢帧、音画偏移、重缓冲、峰值内存、缓存占用与能耗。合成拍板片用于测量声画偏移，字幕带已知起止帧；持续漂移、错字、错误声道、进度丢失逐例阻断对应阶段。
- **设备与系统。** 测试矩阵以官方最低系统和可用当前系统各取一组。基线标明 macOS 15、iOS/iPadOS 18、tvOS 18.5 和 visionOS 26 起。至少区分 Mac 内屏与 HDR 外屏、手机与平板、电视与接收器、Vision Pro 真机。模拟器可跑导航截图，HDR、功耗、投屏和空间声音保留真机结果。[官方技术规格](https://firecore.com/infuse)
- **回归与发行。** 每个提交运行本地协议夹具、状态迁移、索引和字幕快照；播放引擎或系统版本变更时加跑同素材的音画与性能对照。候选版本附覆盖清单、未验证项、可重现差异及脱敏证据。若仅 Mac 三个核心来源通过，对外标记为 Mac 首版；全平台覆盖以逐项验收记录为准。

### M5p 版本去重执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 版本合并 | MacBook Pro M2 Pro／macOS 27.2.1 | Jellyfin+Emby 同夹具 | Infuse 未安装 | 2 组；1080/720 各合并为双来源标签 | Evidence 81、`reports/m5p-dedupe.json` | 通过 |
| 单元测试 | 同上 | 两来源同 mediaSourceID | 待采样 | 1 版本，标签含 Jellyfin/Emby；29/29 | 终端 | 通过 |
| 真实服务器 | 同上 | 真实 ID | 待采样 | 未测 | — | 待验证 |

### M4q Trakt 执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 设备码/轮询 | MacBook Pro M2 Pro／macOS 27.2.1 | Trakt 夹具 | Infuse 未安装 | device_code + access_token | `reports/m4q-trakt.jsonl` | 通过（夹具） |
| 搜索/scrobble | 同上 | 本地样本 | 待采样 | search 1001；start 0；stop 99.9467 | Evidence 82 | 通过 |
| 真实 Trakt | 同上 | 真实账号 | 待采样 | 未测 | — | 待验证 |
| 音频回环 | 同上 | iFlyrec | 待采样 | ffmpeg 捕获被系统权限阻断 | — | 待验证 |

### M4r Trakt 剧集执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Show 搜索 | MacBook Pro M2 Pro／macOS 27.2.1 | Trakt 夹具 | Infuse 未安装 | `/search/show?query=示例剧` → 2001 | `reports/m4r-trakt.jsonl` | 通过 |
| Episode scrobble | 同上 | 本地示例剧 S01E01 | 待采样 | start/stop body episode{1,1}，stop 99.9467 | Evidence 83 | 通过 |
| 真实 Trakt/历史 | 同上 | 真实账号 | 待采样 | 未测 | — | 待验证 |

### M4s Trakt 历史执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| history 导入 | MacBook Pro M2 Pro／macOS 27.2.1 | Trakt 夹具 | Infuse 未安装 | movies/shows 请求；匹配 3 集 | `reports/m4s-trakt-history.jsonl` | 通过 |
| watched 筛选 | 同上 | 本地夹具 | 待采样 | visible 电影+剧集 | Evidence 84、`reports/m4s-trakt-watched.json` | 通过 |
| 真实 Trakt/远程来源 | 同上 | 真实账号/服务器 | 待采样 | 未测；仅本地 fileURL | — | 待验证 |

### M4t Trakt 远程历史执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Jellyfin history | MacBook Pro M2 Pro／macOS 27.2.1 | Trakt+Jellyfin 夹具 | Infuse 未安装 | 匹配 3 集；watched 电影+剧集 | Evidence 85、`reports/m4t-trakt-watched.json` | 通过 |
| 远程 fingerprint | 同上 | Jellyfin | 待采样 | 播放键 jellyfin://source/item/media 标记 | 同上 | 通过 |
| WebDAV/SMB/Plex | 同上 | 对应来源 | 待采样 | 代码已接，未逐一验收 | — | 待验证 |
| 真实 Trakt | 同上 | 真实账号 | 待采样 | 未测 | — | 待验证 |

### M5t Trakt OAuth UI 执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 设置页渲染 | MacBook Pro M2 Pro／macOS 27.2.1 | env 预填 | Infuse 未安装 | Client ID/Secret/API/状态/按钮 | Evidence 86 | 通过（UI） |
| 设备码/轮询 | 同上 | Trakt 夹具 | 待采样 | 协议已在 M4q probe 验证；UI 点击未自动化 | — | 部分通过 |
| 真实 Trakt/Keychain | 同上 | 真实账号/签名 | 待采样 | 未测 | — | 待验证 |

### M5u SMB 并发执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 并发 Range | MacBook Pro M2 Pro／macOS 27.2.1 | impacket SMB2 | Infuse 未安装 | 两并发 1MB Range，SHA-256 与 fixture 一致 | `reports/m5u-smb-concurrency.txt` | 通过 |
| SIGPIPE | 同上 | 客户端中断 | 待采样 | SO_NOSIGPIPE 已设；并发上限 4 | 同上 | 通过 |
| 真实 SMB3/大文件 | 同上 | 真实服务器 | 待采样 | 未测 | — | 待验证 |

### M5v Trakt 自动轮询执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 自动轮询 | MacBook Pro M2 Pro／macOS 27.2.1 | Trakt 夹具 | Infuse 未安装 | device code 后 1.07s token；App 授权成功 | `reports/m5v-trakt-auto.jsonl` | 通过 |
| 真实 Trakt/Keychain | 同上 | 真实账号/签名 | 待采样 | 未测；测试跳过 Keychain | — | 待验证 |

### M5w HDR10 元数据执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| HDR10 样片 | MacBook Pro M2 Pro／macOS 27.2.1 | bt2020/smpte2084 1080p10bit | Infuse 未安装 | ffprobe 识别；dynamicRange=HDR10 | Evidence 87、`reports/m5w-hdr-library.json` | 通过（元数据） |
| HDR 输出 | 同上 | 同上 | 待采样 | 未验证显示/tone mapping | — | 待验证 |
| 远程 HDR | 同上 | WebDAV/Jellyfin | 待采样 | 未解析 | — | 待验证 |

### M5x 远程 HDR 执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Jellyfin HDR | MacBook Pro M2 Pro／macOS 27.2.1 | 夹具 VideoRangeType=HDR10 | Infuse 未安装 | 版本 dynamicRange=HDR10/1080p | `reports/m5x-jellyfin-hdr.json` | 通过（元数据） |
| WebDAV HDR | 同上 | HDR MKV | 待采样 | ffprobe HDR10，`1080p · WebDAV` | Evidence 88、`reports/m5x-webdav-hdr.json` | 通过（元数据） |
| 实际 HDR 输出 | 同上 | 同上 | 待采样 | 未验证 | — | 待验证 |

### M5y HDR 播放执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| HDR10 解码 | MacBook Pro M2 Pro／macOS 27.2.1 | bt2020/smpte2084 | Infuse 未安装 | primaries bt.2020、gamma pq、sig-peak 4.926 | Evidence 89、`reports/m5y-hdr-playback.json` | 通过 |
| SDR tone map | 同上 | 同上 | 待采样 | spline/compute-peak，截图正常 | 同上 | 通过 |
| HDR 直通/显示器 | 同上 | 真实 HDR 屏 | 待采样 | 未验证 | — | 待验证 |

### M3n 损坏过滤执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 损坏过滤 | MacBook Pro M2 Pro／macOS 27.2.1 | 本地库 + 文本 .mkv | Infuse 未安装 | Broken 不入库；3 个正常作品 | `reports/m3n-corrupt-filter.json` | 通过 |
| 扫描中播放 | 同上 | 同上 | 待采样 | position 12s 继续；损坏扫描不崩 | 脚本 PASS | 通过 |
| 远程损坏 | 同上 | SMB/WebDAV | 待采样 | 未过滤 | — | 待验证 |

### M3o 多根本地库执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 两根共存 | MacBook Pro M2 Pro／macOS 27.2.1 | root-a/root-b | Infuse 未安装 | rawWorks=2，Alpha+Beta | `reports/m3o-local-roots.json` | 通过 |
| 移除根 | 同上 | 同上 | 待采样 | rawWorks=1，仅 Alpha；store 1 root | 同上 | 通过 |
| 跨根内容去重 | 同上 | 同文件 | 待采样 | 未按内容去重 | — | 待验证 |

### M3p 跨根去重执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 内容去重 | MacBook Pro M2 Pro／macOS 27.2.1 | 两根同文件 | Infuse 未安装 | rawWorks=2/groups=1/versions=1 | `reports/m3p-local-dedupe.json` | 通过 |
| 指纹 | 同上 | 1080p 样品 | 待采样 | contentKey size+首尾64KB SHA-256 | 同上 | 通过 |
| 全文件/远程指纹 | 同上 | 大文件/SMB/WebDAV | 待采样 | 未做 | — | 待验证 |

### M5z 5.1 解码执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| E-AC-3 5.1 | MacBook Pro M2 Pro／macOS 27.2.1 | 60s 测试 MKV | Infuse 未安装 | PCM 48k/6ch/5.1；六路非静音 | `reports/m5z-audio-pcm-probe.json` | 通过（解码） |
| 扬声器听测 | 同上 | 同上 | 待人工 | 未做 | — | 待验证 |
| Downmix/同步 | 同上 | 同上 | 待人工 | 未做 | — | 待验证 |

### M3q MKV 头部解析执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| 头部解析 | MacBook Pro M2 Pro／macOS 27.2.1 | 1080p/HDR10 MKV | Infuse 未安装 | 2MB Range → 1080p/HDR10 | `reports/m3q-mkv-header.json` | 通过 |
| 单测 | 同上 | 主/HDR 夹具 | 待采样 | 31/31，MatroskaProbe 2 项 | 终端 | 通过 |
| iOS 运行期扫描 | 同上 | iPhone/iPad | 待采样 | 仅构建，未跑扫描 | — | 待验证 |
| 大头部/畸形 EBML | 同上 | 大文件 | 待采样 | 未测 | — | 待验证 |
| Stereo downmix | 同上 | 5.1 样片 | 待人工 | 2ch 非静音 | `reports/m5z-stereo-probe.json` | 通过（解码） |

### M3r iOS 运行期 MKV 执行记录（2026-11-20）

| 测试 | 设备／系统／权益 | 素材／来源／初始状态 | 参照步骤与结果 | OpenFuse 构建与结果 | 截图或测量编号 | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| iOS 远程 MKV | iPhone 18 Pro 模拟器／iOS 27.2 | WebDAV HDR10 MKV | Infuse 未安装 | SQLite `1080p · WebDAV`/HDR10 | Evidence 90、`reports/m3r-ios-mkv.txt` | 通过 |
| 真实 OpenList/大头部 | 同上 | 真实服务 | 待采样 | 未测 | — | 待验证 |
| 扬声器听测 | 同上 | 5.1 样片 | 待人工 | 未做 | — | 待验证 |
