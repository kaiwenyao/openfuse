# 里程碑状态

更新：2026-11-19。基线 Infuse 8.5.10。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| M0 参照与选型 | 完成（Infuse 实机采样除外） | AVPlayer 打不开 MKV；libmpv 胜出。夹具与声道校验完成。 |
| M1 Mac 本地播放 | 首个可用版本 | 打开/播放/切字幕/拖动/全屏/续播/关闭重开已实测；Infuse 对照、人耳听测、100 次循环未做。 |
| M2 远程播放 | 部分完成：WebDAV + Jellyfin Direct | WebDAV：列目录、直放、远程 ASS、Range 拖动、续播。Jellyfin Direct：登录、媒体库/剧/季/集、服务器封面与版本、服务器轨道命名、直连、进度回写、服务器续播。真实服务与 Library Mode 未完成。 |
| M3 Mac 媒体库 | 基本完成：M3a–M3m | 三源扫描/合并/版本/海报/筛选/防剧透/TMDB/NFO/恢复；T07 扫描中播放/损坏单文件；WebDAV MKV 分辨率（macOS ffprobe）与 1080p 筛选通过。多根本地库策略、损坏过滤、iOS 远程 MKV 探测仍待。 |
| M4 家庭设备与同步 | 部分完成：M4a–M4p | 五端实际启动；iPhone/iPad 远程 WebDAV+Jellyfin；移动音轨/字幕；tvOS/visionOS 播放；进度同步协议 + 本地共享文件两设备续播实测（A 9.917s → B 14.417s）；CloudKit transport 代码、真实 iCloud 未验证。音频听测、ASS 样式、沉浸式交互、Trakt/自动同步未做。 |
| M5 其余来源与高级播放 | 部分完成：M5a–M5j | Plex 扫描/播放/进度/字幕/多版本/Direct 浏览；macOS 自包含 app；Emby；Jellyfin+Emby 去重/progress；Mac AirPlay 入口。未公证/仅 arm64；真实服务器、版本级去重、Plex 详情点击/音轨、SMB/HDR/AirPlay 实机、CloudKit/Trakt、音频未做。 |
| M6 Vision Pro | 未开始 | |

## 当前分支

`m5j-airplay`（基于 M3m 提交）。M5k 从该分支继续。

## 下一批可执行工作

1. M5k：AirPlay/HDR 实机；Plex 详情/点击/音轨；版本级去重；SMB；CloudKit/Trakt；音频；M3 多根/损坏过滤。
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
