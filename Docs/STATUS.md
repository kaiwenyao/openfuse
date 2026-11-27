# 里程碑状态

当前只排期 [Mac 的 WebDAV 和 Jellyfin](MAC-FIRST.md)。下表是既有实现的历史记录。

更新：2026-11-27。基线 Infuse 8.5.10。

0.9.7 为 macOS、iPhone 和 iPad 提供新的 OpenFuse 应用图标，GitHub Release 提供 macOS 安装包。

0.9.6 修复 2026-11-27 功能问题清单中的 7 条：续播后关闭卡在加载页、失败无提示、「仅本次会话」来源误报密码错误、来源移除后的历史条目、Keychain 写入警告不可见，以及两条 iOS 问题。[问题清单](BUG-REVIEW-2026-11-27.md) · [PR #3](https://github.com/kaiwenyao/openfuse/pull/3)

0.9.5 改善 macOS 持续播放视频时的 `Cmd+Tab` 卡顿。渲染路径减少主线程对目标帧时刻的等待，验收脚本记录切换前后的进度、音画同步和掉帧。[修复与验证记录](MACOS-CMD-TAB-FIX.md) · [PR #2](https://github.com/kaiwenyao/openfuse/pull/2)

0.9.4 修复 macOS 字幕偏移显示精度与负号解析。菜单、编辑框、保存和播放统一到毫秒精度。旧记录按影片和字幕轨恢复。[PR #1](https://github.com/kaiwenyao/openfuse/pull/1)

0.9.3：修复换集后右键/空格无法暂停视频——播放器的 AppKit 本地事件监视器改为在事件到达时解析当前 `PlayerModel`，不再捕获换集前的旧引擎；新增 `Scripts/run-episode-switch-pause.sh` 六用例回归。记录：[0.9.3 换集修复](0.9.3-EPISODE-SWITCH.md)。

0.9.2：WebDAV 文件夹卡片只显示本名；播放器改为顶部居中、两行、可拖动的紧凑悬浮面板（macOS 26+ glassEffect，14/15 NSVisualEffectView），标题收敛为作品名 + 季集号。记录：[0.9.2 UI](0.9.2-UI.md)。

0.4.0：默认明亮主题并可在设置中切换；Trakt 同步已完全移除（含历史/授权/CLI/脚本与旧凭据清理）。
M7（2026-11-20）：播放器控制栏在明亮主题下可见、WebDAV 路径不再重复、播放管线按 IINA 重写（CAOpenGLLayer + CVDisplayLink + display-resample）。记录：[M7 播放器管线](M7-PLAYER-PIPELINE.md)。
0.5.1：播放器标题栏与窗口外观跟随深色，退出后恢复用户主题。
0.5.2：回退 0.5.x 的 Core Animation 播放核心，修复色彩失衡与 SRT/ASS 字幕残缺、乱码；纯文本字幕固定上移避免被控制栏遮挡。
0.7.0：底栏字幕偏移、零配置 WebDAV/Jellyfin 资料、首页 4 项继续观看、点击即加载页、移除独立进度同步。
0.6.1：Jellyfin 媒体库网格修复、窗口内作品详情/选集、评分与演职员、所选 MediaSource 技术参数。
0.6.0：字幕时间偏移（按视频+字幕轨持久化）、播放器同文件夹选集（排序/多版本/全屏切换）、WebDAV 目录影视资料（TMDB/OMDb、NFO/修正、缓存、断网回退）。
0.5.6：IINA 风格窗口管理（⌘3 全屏、⌃⌘F、⌃⌘T 总在最前、⌘0/1/2 尺寸、⌘4 适合屏幕、⌘-/⌘= 缩放、Esc 退出全屏）。
0.5.5：进度条 hover 缩略图（独立无声 mpv 引擎、2 秒缓存桶、请求取消，不打扰播放）。
0.5.4：打开/切换/退出播放器不再阻塞主线程；缓冲测速三态与断流重连；App 内音量（键盘/滑块/HUD/持久化）；播放器任意位置右键暂停。
0.5.3：缓存功能——缓冲/加载 HUD 显示百分比、已缓存大小与下载速度（对标 IINA）；进度条高亮已缓存区间（支持多段 seekable-ranges）。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| M0 参照与选型 | 完成（Infuse 实机采样除外） | AVPlayer 打不开 MKV；libmpv 胜出。夹具与声道校验完成。 |
| M1 Mac 本地播放 | 首个可用版本 | 打开/播放/切字幕/拖动/全屏/续播/关闭重开已实测；Infuse 对照、人耳听测、100 次循环未做。 |
| M2 远程播放 | 部分完成：WebDAV(OpenList) + Jellyfin | Mac+iPhone 真实 OpenList；Mac Jellyfin 多用户进度/权限隔离；iPhone HLS 1080p。百度网盘、HTTPS/4K/UI 用户切换/并发未完成。 |
| M3 Mac 媒体库 | 基本完成：M3a–M3s | 三源扫描/合并/版本/海报/筛选/防剧透/TMDB/NFO/恢复；T07；本地/WebDAV/SMB 损坏签名过滤；多根；跨来源指纹去重；MKV/MP4 分辨率/HDR（尾部 moov）；iOS 运行期验证。碎片 MP4/性能、真实 OpenList、全文件哈希仍待。 |
| M4 家庭设备与同步 | 部分完成：M4a–M5ac | 五端启动；移动远程来源/字幕；进度同步本地两设备实测；CloudKit 代码；E-AC-3 5.1 PCM+stereo 验证；CoreAudio 设备选择。真实账号/自动同步、扬声器听测/热插拔未做。 |
| M5 其余来源与高级播放 | 部分完成：M5a–M5ao | Plex 全链路；Emby；Jellyfin+Emby 去重；SMB SMB3/2.4GB seek；HDR10/EDR 直通。未公证/仅 arm64；SMB >4GB/DFS/域、HDR 测量、AirPlay 实机、CloudKit 未做。 |
| M6 Vision Pro | 部分完成：M6a–M6c | `.full` 沉浸实际出画；星点环境、3D 播放/关闭球、进度条；窗口切换；自动关闭写回进度；空间音频 intended experience。真机手势/空间音频/HDR 待验证。 |
| M7 播放器修复与管线重写 | 完成（Mac 本机） | 控制栏在明亮/深色均可见；WebDAV 连点不再重复路径；`MPVController`/`MPVVideoLayer`/`MPVVideoView` 按 IINA 重写，60 s 连播 p99 12.2 ms、淡出停帧 12.3 ms（旧 ~100 ms）。Infuse 同机对照、HDR 实测仍待。 |

## 阶段快照分支（历史）

`m6i-tvos`（基于 M6h 提交）。M6j/M5au 从该分支继续。

## 上一轮的候选工作（历史）

1. M6j/M5au：tvOS遥控/远程来源；物理5.1/HDMI；HDR测量；小时级/DFS；CloudKit/visionOS。
2. M3 尾项：T07 其他场景（扫描中播放/单文件失败）、画质元数据补全。
3. 真实 Jellyfin：独立测试账号验证 HTTPS/反向代理、转码、外挂字幕、多用户；缺账号的组合标「待验证」。
4. 真实 OpenList：独立测试账号验证登录、限流、签名跳转与目录规模；重定向凭据改为本机代理。
5. 轨道映射改为显式 MediaStream Index；暂停/拖动立即回写进度。
6. 远程首帧与拖动分段计时；本地/LAN 10% 中位数目标。
7. 真机 5.1 接收器与 Infuse 对照：需要设备与安装包时逐项登记「待验证」，不阻塞其他工作。

## 已知风险

- libmpv/FFmpeg 的许可与打包；当前依赖 Homebrew。
- 窗口快照不包含 OpenGL 层，UI 自动比对需要另建渲染抓帧。
- 无 Infuse 安装与测试账号，参照矩阵无法闭环。
