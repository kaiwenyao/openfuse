# 里程碑状态

更新：2026-11-19。基线 Infuse 8.5.10。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| M0 参照与选型 | 完成（Infuse 实机采样除外） | AVPlayer 打不开 MKV；libmpv 胜出。夹具与声道校验完成。 |
| M1 Mac 本地播放 | 首个可用版本 | 打开/播放/切字幕/拖动/全屏/续播/关闭重开已实测；Infuse 对照、人耳听测、100 次循环未做。 |
| M2 远程播放 | 部分完成：WebDAV(OpenList) + Jellyfin | Mac+iPhone 真实 OpenList；Mac Jellyfin 12 直连/进度；iPhone Jellyfin MKV HLS 8Mbps/1080p 实际转码，HUD 服务器轨道标签。百度网盘、HTTPS/4K/多用户未完成。 |
| M3 Mac 媒体库 | 基本完成：M3a–M3s | 三源扫描/合并/版本/海报/筛选/防剧透/TMDB/NFO/恢复；T07；本地/WebDAV/SMB 损坏签名过滤；多根；跨来源指纹去重；MKV/MP4 分辨率/HDR（尾部 moov）；iOS 运行期验证。碎片 MP4/性能、真实 OpenList、全文件哈希仍待。 |
| M4 家庭设备与同步 | 部分完成：M4a–M5ac | 五端启动；移动远程来源/字幕；进度同步本地两设备实测；CloudKit 代码；Trakt 自动轮询/历史；E-AC-3 5.1 PCM+stereo 验证；CoreAudio 设备选择。真实账号/自动同步、扬声器听测/热插拔未做。 |
| M5 其余来源与高级播放 | 部分完成：M5a–M5al | Plex 全链路；自包含 app；Emby；Jellyfin+Emby 去重/progress；AirPlay 入口；SMB 边下边播/元数据/并发/真实 Samba SMB3/签名加密；HDR10/EDR 直通。未公证/仅 arm64；SMB DFS/域/大文件、HDR 测量、AirPlay 实机、CloudKit 未做。 |
| M6 Vision Pro | 部分完成：M6a–M6c | `.full` 沉浸实际出画；星点环境、3D 播放/关闭球、进度条；窗口切换；自动关闭写回进度；空间音频 intended experience。真机手势/空间音频/HDR 待验证。 |

## 当前分支

`m2g-jellyfin-hls-quality`（基于 M5al 提交）。M2h/M6d 从该分支继续。

## 下一批可执行工作

1. M2h/M6d：Jellyfin 4K/HTTPS/多用户；SMB DFS/域/大文件；音频听测；HDR 测量；真实 Trakt/CloudKit；visionOS 真机。
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
