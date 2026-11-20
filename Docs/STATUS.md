# 里程碑状态

更新：2026-11-19。基线 Infuse 8.5.10。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| M0 参照与选型 | 完成（Infuse 实机采样除外） | AVPlayer 打不开 MKV；libmpv 胜出。夹具与声道校验完成。 |
| M1 Mac 本地播放 | 首个可用版本 | 打开/播放/切字幕/拖动/全屏/续播/关闭重开已实测；Infuse 对照、人耳听测、100 次循环未做。 |
| M2 远程播放 | 部分完成：WebDAV + Jellyfin Direct | WebDAV：列目录、直放、远程 ASS、Range 拖动、续播。Jellyfin Direct：登录、媒体库/剧/季/集、服务器封面与版本、服务器轨道命名、直连、进度回写、服务器续播。真实服务与 Library Mode 未完成。 |
| M3 Mac 媒体库 | 基本完成：M3a–M3h | SQLite、三源扫描、跨来源合并、海报、搜索、排序/类型/观看状态/画质筛选、防剧透、详情、版本菜单、TMDB/NFO、手动改/合并/拆分、TMDB 候选、可取消扫描、10k 压力、WebDAV NFO/认证海报。剩余 T07 深入与画质元数据补全。 |
| M4 家庭设备与同步 | 部分完成：M4a–M4c | 跨平台数据层；iPhone/iPad/tvOS/visionOS 目标均构建成功；iPad 分栏、tvOS 焦点网格、visionOS 分栏/详情/播放；移动端 WebDAV/Jellyfin 来源扫描。无 runtime，启动/触控/遥控/空间布局/远程播放待验证；MKV/字幕/音轨、CloudKit/Trakt 未做。 |
| M5 其余来源与高级播放 | 未开始 | 含自包含打包、HDR、投屏、Plex/Emby/SMB。 |
| M6 Vision Pro | 未开始 | |

## 当前分支

`m4c-ipad`（基于 M4b 提交）。M4d 从该分支继续。

## 下一批可执行工作

1. M4d：runtime 启动/截图、远程播放代理/转码、MKV/字幕/音轨、tvOS/visionOS 来源/焦点、CloudKit/Trakt。
2. M3 尾项：T07 深入、画质元数据补全（Jellyfin 单集/本地/WebDAV）。
3. 真实 Jellyfin：独立测试账号验证 HTTPS/反向代理、转码、外挂字幕、多用户；缺账号的组合标「待验证」。
4. 真实 OpenList：独立测试账号验证登录、限流、签名跳转与目录规模；重定向凭据改为本机代理。
5. 轨道映射改为显式 MediaStream Index；暂停/拖动立即回写进度。
6. 远程首帧与拖动分段计时；本地/LAN 10% 中位数目标。
7. 真机 5.1 接收器与 Infuse 对照：需要设备与安装包时逐项登记「待验证」，不阻塞其他工作。

## 已知风险

- libmpv/FFmpeg 的许可与打包；当前依赖 Homebrew。
- 窗口快照不包含 OpenGL 层，UI 自动比对需要另建渲染抓帧。
- 无 Infuse 安装与测试账号，参照矩阵无法闭环。
