# M1 证据

均由 2026-11-19 的 `m1-local-playback` 构建在 MacBook Pro（M2 Pro，macOS 27.2.1）上生成。

| 文件 | 内容 | 采集方式 |
| --- | --- | --- |
| `01-home-continue-watching.jpg` | 首页继续观看卡片，00:25 / 01:00 | 应用内 `cacheDisplay` 窗口快照 |
| `02-player-controls.jpg` | 播放器控制层、字幕/音轨菜单标签 | 同上；OpenGL 视频层不进窗口快照，视频区为黑色 |
| `03-hevc-main10-frame.jpg` | 13.458 s 的实际渲染帧，含时间码与 5.1 声道图 | 播放器 `glReadPixels` |
| `04-subtitle-zh-hans.jpg` | 9.917 s，外挂简体 + 日文双语 | 同上 |
| `05-subtitle-zh-hant.jpg` | 9.917 s，外挂繁体 + 日文双语 | 同上 |
| `06-subtitle-font-fallback.jpg` | 4.417 s，缺字体 NOTE 样式与双语字幕 | 同上 |
| `07-webdav-browser.jpg` | WebDAV 根目录浏览（Movies/Shows） | 应用内窗口快照 |
| `08-webdav-sources.jpg` | 首页网络来源卡片 | 应用内窗口快照 |
| `09-webdav-playback.jpg` | 远程播放 9.958 s，远程 `zh-Hans` 字幕 | 播放器 `glReadPixels` |
| `10-webdav-zh-hant.jpg` | 远程切到 `zh-Hant` 的同一帧 | 同上 |
| `11-webdav-seek.jpg` | 限速 WebDAV 拖动到 41 s | 同上 |
| `12-webdav-player-ui.jpg` | 远程播放器控制层，来源显示「本地 WebDAV」 | 应用内窗口快照 |
| `13-jellyfin-home.jpg` | 首页 Jellyfin 来源卡片 | 应用内窗口快照 |
| `14-jellyfin-browser.jpg` | Jellyfin 电影库/电视剧库与封面 | 应用内窗口快照 |
| `15-jellyfin-episode-frame.jpg` | Jellyfin 直连播放单集，服务器字幕 | 播放器 `glReadPixels` |
| `16-jellyfin-version-frame.jpg` | 电影选择压缩版后的播放帧 | 同上 |
| `17-jellyfin-resume.jpg` | 服务器位置 9.9 s 续播后的帧 | 同上 |
| `18-jellyfin-player-ui.jpg` | Jellyfin 来源的播放器控制层 | 应用内窗口快照 |
| `reports/m2-jellyfin-*.json` | 单集/电影/续播报告与服务端事件日志 | 应用 `--report`、夹具日志 |
| `19-library-local.jpg` | 本地扫描后的媒体库（3 作品/4 集） | 应用内窗口快照 |
| `20-library-aggregate.jpg` | 本地 + Jellyfin 合并后的媒体库（3 组） | 同上 |
| `21-library-series-detail.jpg` | 剧集详情、来源胶囊、季/集列表 | 同上 |
| `22-library-search.jpg` | 媒体库搜索「示例」 | 同上 |
| `23-library-movie-versions.jpg` | 电影详情的 1080p/720p 版本 Picker | 同上 |
| `24-library-play.jpg` | 从媒体库播放单集的渲染帧 | 播放器 `glReadPixels` |
| `reports/m3-library-*.json` | 本地/聚合/WebDAV 扫描、媒体库播放报告 | 应用 `--library-report` |
| `25-tmdb-local.jpg` | 本地扫描 + TMDB + NFO 的媒体库 | 应用内窗口快照 |
| `26-tmdb-webdav.jpg` | WebDAV 扫描 + TMDB 海报库 | 同上 |
| `27-tmdb-detail.jpg` | TMDB 电影详情（标题/简介/海报） | 同上 |
| `28-nfo-detail.jpg` | tvshow.nfo 优先级（标题/年份/简介/本地海报） | 同上 |
| `reports/m3b-tmdb-*.json` | TMDB/NFO 本地与 WebDAV 报告、TMDB 请求日志 | 应用 `--library-report`、夹具日志 |
| `29-merged-movie-versions.jpg` | 电影详情合并 Jellyfin/本地/WebDAV 共 4 个版本 | 应用内窗口快照 |
| `30-merged-series-versions.jpg` | 剧集每集多来源版本菜单 | 同上 |
| `31-edited-detail.jpg` | 手动修改标题/年份/简介/海报后的详情 | 应用内窗口快照 |
| `32-scan-progress.jpg` | 10,000 项扫描进度与取消按钮 | 同上 |
| `reports/m3d-edit-*.json` | 纠错前/应用/持久化/清除报告 | 应用 `--library-report` |
| `reports/m3d-scan-stress.json` | 10k 完整扫描、取消、旧库保留摘要 | `run-scan-stress.sh` |
| `33-manual-merged.jpg` | 手动把两部剧合并后的详情（S01E01 2 个版本） | 应用内窗口快照 |
| `reports/m3e-merge-*.json` | 合并前/合并后/拆分后的分组报告 | 应用 `--library-report` |
| `34-webdav-nfo-library.jpg` | WebDAV NFO 标题与缓存海报的媒体库 | 应用内窗口快照 |
| `35-webdav-nfo-detail.jpg` | WebDAV NFO 剧集详情与单集标题/简介 | 同上 |
| `reports/m3f-webdav-nfo.json` | WebDAV NFO/海报扫描报告 | 应用 `--library-report` |
| `36-library-filters.jpg` | 电影筛选 + 年份排序后的媒体库 | 应用内窗口快照 |
| `reports/m3g-filter-*.json` | 类型筛选/集数排序/搜索报告 | 应用 `--library-report` |
| `reports/m4-ios-build.txt` | iOS/ tvOS/visionOS 构建、来源管理、未验证项 | `xcodebuild` 日志摘要 |
| `reports/m4d-auth-asset.txt` | WebDAV Basic Auth AVAsset/AVPlayer 实测摘要 | `test-auth-asset.sh` |
| `reports/m4d-auth-asset.json` | 认证加载时长/轨道/尺寸 | probe 输出 |
| `reports/m4d-auth-play.json` | AVPlayer 实际播放进度 | probe 输出 |
| `reports/m4e-jellyfin-remote.txt` | Jellyfin PlaybackInfo/token/AVPlayer 摘要 | `test-jellyfin-mobile.sh` |
| `reports/m4e-jellyfin-remote.json` | Jellyfin 远程 20s/5.866s 结果 | probe 输出 |
| `reports/m4f-hls.txt` | Jellyfin HLS/MKV 转码摘要 | `test-jellyfin-hls.sh` |
| `reports/m4f-hls.json` | HLS 60s/5.954s 结果 | probe 输出 |
| `reports/m3i-webdav-recovery.txt` | WebDAV 504 目录恢复摘要 | `test-webdav-recovery.sh` |
| `reports/m3i-recovery-*.json` | 失败前后库报告 | 应用 `--library-report` |
| `38-ios-home.jpg` | iPhone 首屏（真实模拟器） | `simctl io screenshot` |
| `39-ios-playback.jpg` | iOS 样本播放 HUD 3.0/20.0s | 同上 |
| `40-ios-resume.jpg` | 重启续播 HUD 12.0/20.0s | 同上 |
| `41-ipad-split.jpg` | iPad NavigationSplitView 分栏 | 同上 |
| `reports/m4g-ios-run.txt` | iOS 启动/播放/续播记录 | 测试脚本摘要 |
| `42-ios-webdav-remote.jpg` | iPhone WebDAV 远程播放 7.0/20s | `simctl io screenshot` |
| `43-ios-jellyfin-remote.jpg` | iPhone Jellyfin 远程播放 8.0/20s | 同上 |
| `reports/m4h-mobile-remote.txt` | 移动远程测试/构建摘要 | 运行记录 |
| `44-resolution-filter.jpg` | 本地 1080p 筛选显示 3 作品 | 应用内窗口快照 |
| `reports/m3j-resolution.txt` | 本地分辨率探测摘要 | 扫描/ffprobe |
| `45-stream-resolution-filter.jpg` | Jellyfin 1080p 筛选含电影+剧集 | 应用内窗口快照 |
| `reports/m3k-stream-resolution.txt` | WebDAV/Jellyfin 流分辨率摘要 | 扫描/PlaybackInfo |
| `46-ios-tracks.jpg` | iOS HEVC/EAC3 样本 + 音轨/字幕选择 | `simctl io screenshot` |
| `47-tvos-home.jpg` | Apple TV 焦点网格实际运行 | 同上 |
| `48-tvos-playback.jpg` | Apple TV 全屏 HEVC/EAC3 播放 | 同上 |
| `reports/m4i-tracks-tvos.txt` | 移动轨道/tvOS 运行摘要 | 运行记录 |
| `49-ios-subtitle-hans.jpg` | iOS 简体字幕 seek 4.5s | `simctl io screenshot` |
| `50-ios-subtitle-hant.jpg` | iOS 繁体字幕 seek 10s | 同上 |
| `reports/m4j-subtitles.txt` | 移动字幕解析/构建摘要 | 运行记录 |
| `51-ios-webdav-remote-subtitle.jpg` | WebDAV 远程字幕选中（画面未到 cue） | `simctl io screenshot` |
| `reports/m4k-remote-subs.txt` | WebDAV 字幕下载/构建摘要 | 运行记录 |
| `52-ios-webdav-subtitle.jpg` | WebDAV 远程字幕 4.6/20.0s 实际显示 | `simctl io screenshot` |
| `reports/m4l-remote-subtitle.txt` | 远程时长/字幕修复摘要 | 运行记录 |
| `53-ios-webdav-seek-subtitle.jpg` | WebDAV 远程 seek 10s + 第二句字幕 | `simctl io screenshot` |
| `reports/m4m-seek-jfsubs.txt` | 远程 seek/Jellyfin 字幕管线摘要 | 运行记录 |
| `54-ios-jellyfin-external-subtitle.jpg` | Jellyfin 外挂字幕 4.7/60s 显示 | `simctl io screenshot` |
| `reports/m4n-jellyfin-external-subtitle.txt` | 外挂字幕下载/播放摘要 | 运行记录 |
| `55-visionos-home.jpg` | Vision Pro 空间窗口实际启动 | `simctl io screenshot` |
| `56-visionos-playback.jpg` | Vision Pro HEVC/EAC3 播放 | 同上 |
| `reports/m4o-visionos.txt` | visionOS 运行/构建摘要 | 运行记录 |
| `57-progress-sync-b.jpg` | B 设备续播到 21.9s | 应用内渲染抓帧 |
| `reports/m4p-*.json` | 两设备播放/同步记录 | 应用报告 |
| `reports/m4p-progress-sync.txt` | 跨设备续播摘要 | 运行记录 |
| `58-plex-library.jpg` | Plex 扫描后的媒体库 | 应用内窗口快照 |
| `59-plex-playback.jpg` | Plex 条目播放 9.9s | 播放器抓帧 |
| `reports/m5-plex-*.json` | Plex 库/播放报告 | 应用报告 |
| `reports/m5-plex.txt` | Plex 验收/构建摘要 | 运行记录 |
| `60-plex-progress.jpg` | Plex 播放到 59.967s | 播放器抓帧 |
| `reports/m5b-plex-timeline.jsonl` | Plex timeline 事件（脱敏） | 夹具日志 |
| `reports/m5b-plex-progress.txt` | Plex 进度回写摘要 | 运行记录 |
| `reports/m5c-plex-timeline.jsonl` | Plex playing/paused/stopped/scrobble 事件 | 夹具日志 |
| `reports/m5c-plex-scrobble.txt` | Plex scrobble 摘要 | 运行记录 |
| `61-plex-subtitle.jpg` | Plex 外挂中文字幕 9.958s | 播放器抓帧 |
| `reports/m5d-plex-*.json` | Plex 字幕库/播放报告 | 应用报告 |
| `reports/m5d-plex-subtitle.txt` | Plex 字幕下载/选择摘要 | 运行记录 |
| `62-self-contained-playback.jpg` | 自包含 app 播放 MKV | 播放器抓帧 |
| `reports/m5e-packaging.txt` | 依赖/体积/播放摘要 | 运行记录 |
| `63-emby-library.jpg` | Emby 扫描后的媒体库 | 应用内窗口快照 |
| `64-emby-playback.jpg` | Emby 第 1 集播放 9.9s | 播放器抓帧 |
| `reports/m5f-emby-*.json` | Emby 库/播放报告 | 应用报告 |
| `reports/m5f-emby.txt` | Emby 验收/构建摘要 | 运行记录 |
| `65-jellyfin-emby-dedupe.jpg` | 两来源聚合后的媒体库 | 应用内窗口快照 |
| `reports/m5g-dedupe.json` | 去重后的 2 组/sources | 应用报告 |
| `reports/m5g-emby-progress.jsonl` | Emby Playing/Progress 事件 | 夹具日志 |
| `reports/m5g-dedupe-progress.txt` | 聚合/进度摘要 | 运行记录 |
| `66-plex-alternate-version.jpg` | Plex 720p 备版播放 | 播放器抓帧 |
| `reports/m5h-plex-*.json` | Plex 多版本库/播放报告 | 应用报告 |
| `reports/m5h-plex-versions.txt` | Plex 多版本摘要 | 运行记录 |
| `67-plex-browser-sections.jpg` | Plex Direct sections | 应用内窗口快照 |
| `68-plex-browser-movies.jpg` | Plex 电影 section 网格 | 同上 |
| `reports/m5i-plex-browser.jsonl` | Plex 浏览请求（脱敏） | 夹具日志 |
| `reports/m5i-plex-browser.txt` | Plex 浏览摘要 | 运行记录 |
| `69-scan-while-playing.jpg` | 扫描中播放到 12s | 播放器抓帧 |
| `reports/m3l-corrupt-scan.json` | 损坏文件扫描报告 | 应用报告 |
| `reports/m3l-scan-while-playing.json` | 扫描中播放报告 | 应用报告 |
| `reports/m3l-t07.txt` | T07 摘要 | 运行记录 |
| `70-webdav-mkv-resolution.jpg` | WebDAV MKV 1080p 媒体库 | 应用内窗口快照 |
| `reports/m3m-webdav-mkv-library.json` | MKV 版本/分辨率 | 应用报告 |
| `reports/m3m-webdav-mkv-filter.json` | 1080p 筛选结果 | 应用报告 |
| `reports/m3m-webdav-mkv.txt` | MKV 分辨率摘要 | 运行记录 |
| `71-airplay-player.jpg` | Mac 播放器 AirPlay 入口 | 应用内窗口快照 |
| `reports/m5j-airplay.txt` | AirPlay 构建/UI 摘要 | 运行记录 |
| `72-plex-detail-versions.jpg` | Plex 详情版本/音轨 | 应用内窗口快照 |
| `73-plex-detail-play.jpg` | Plex 详情播放 9.9s | 播放器抓帧 |
| `reports/m5k-plex-detail-play.json` | Plex 详情播放报告 | 应用报告 |
| `reports/m5k-plex-detail.txt` | 详情/播放摘要 | 运行记录 |
| `74-smb-library.jpg` | SMB 媒体库/来源卡 | 应用内窗口快照 |
| `75-smb-playback.jpg` | SMB 缓存播放 9.9s | 播放器抓帧 |
| `reports/m5l-smb-*.json` | SMB 库/播放报告 | 应用报告 |
| `reports/m5l-smb.txt` | SMB 验收/打包摘要 | 运行记录 |
| `76-smb-stream-seek.jpg` | SMB Range 流 seek 到 31s | 播放器抓帧 |
| `reports/m5m-smb-stream.json` | SMB 流播放报告 | 应用报告 |
| `reports/m5m-smb-stream.txt` | SMB 流摘要 | 运行记录 |
| `77-smb-nfo-poster.jpg` | SMB NFO 标题与海报 | 应用内窗口快照 |
| `78-smb-subtitle.jpg` | SMB 外挂字幕 + seek 31s | 播放器抓帧 |
| `reports/m5n-smb-*.json` | SMB 元数据/播放报告 | 应用报告 |
| `reports/m5n-smb.txt` | SMB NFO/字幕摘要 | 运行记录 |
| `79-smb-show-seasons.jpg` | SMB 两季剧集/NFO 海报 | 应用内窗口快照 |
| `80-smb-show-play.jpg` | SMB 跨季剧集播放 31s | 播放器抓帧 |
| `reports/m5o-smb-*.json` | SMB 跨季库/播放报告 | 应用报告 |
| `reports/m5o-smb-show.txt` | 跨季 NFO/重连摘要 | 运行记录 |
| `81-version-dedupe.jpg` | Jellyfin/Emby 版本合并库 | 应用内窗口快照 |
| `reports/m5p-dedupe.json` | 版本级去重报告 | 应用报告 |
| `reports/m5p-version-dedupe.txt` | 版本去重摘要 | 运行记录 |
| `82-trakt-scrobble.jpg` | Trakt scrobble 播放到 59.9s | 播放器抓帧 |
| `reports/m4q-trakt.jsonl` | Trakt 设备码/搜索/scrobble 事件 | 夹具日志 |
| `reports/m4q-trakt-play.json` | Trakt 播放报告 | 应用报告 |
| `reports/m4q-trakt.txt` | Trakt 验收摘要 | 运行记录 |
| `37-spoiler-protection.jpg` | 防剧透开启的详情/单集简介 | 应用内窗口快照 |
| `reports/m3h-watch-*.json` | 观看中/最近播放/1080p 筛选报告 | 应用 `--library-report` |
| `reports/m2-*.json` | WebDAV 播放/拖动/续播/简繁报告 | 应用 `--report` |
| `reports/m2-webdav-range-log.jsonl` | 服务端 GET/Range 记录，证明初始请求取消与中段读取 | `Tools/webdav_fixture.py` |
| `reports/*.json` | M1 运行报告、续播存储、24 项声道检测 | 应用 `--report` 与 `analyze_audio.py` |

报告中的绝对路径已替换为仓库相对路径，日志保留最后 20 行。原始 PNG 与测试片不入库，可用 `Scripts/make_fixtures.sh` 重新生成。

窗口快照不能捕获 `NSOpenGLView` 是 macOS 的既有行为；因此不能用窗口图判断“是否出画”，必须看 `03`–`06` 这类渲染帧。
