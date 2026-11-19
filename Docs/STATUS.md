# 里程碑状态

更新：2026-11-19。基线 Infuse 8.5.10。

| 阶段 | 状态 | 说明 |
| --- | --- | --- |
| M0 参照与选型 | 完成（Infuse 实机采样除外） | AVPlayer 打不开 MKV；libmpv 胜出。夹具与声道校验完成。 |
| M1 Mac 本地播放 | 首个可用版本 | 打开/播放/切字幕/拖动/全屏/续播/关闭重开已实测；Infuse 对照、人耳听测、100 次循环未做。 |
| M2 远程播放 | 未开始 | 下一项：WebDAV/OpenList → Jellyfin。 |
| M3 Mac 媒体库 | 未开始 | |
| M4 家庭设备与同步 | 未开始 | |
| M5 其余来源与高级播放 | 未开始 | 含自包含打包、HDR、投屏、Plex/Emby/SMB。 |
| M6 Vision Pro | 未开始 | |

## 当前分支

`m1-local-playback`（从 `main` 拉出）。M2 应从该分支拉出 `m2-remote-sources`。

## 下一批可执行工作

1. 抽出 `MediaSource` 与 `RemoteFile`，让 `PlayerModel` 接受非本地 URL；保留 Range 读取与取消。
2. WebDAV：`PROPFIND` 列目录、`GET` Range、206/416/200 处理、Unicode 路径、远程 ASS 发现、拖动时取消旧请求。
3. Jellyfin Direct：登录、视图/条目、PlaybackInfo、`TranscodingUrl` 或直链、轨道保留、进度上报；Library 模式在 M3 接入。
4. 远程首帧与拖动分段计时；本地/LAN 10% 中位数目标。
5. 真机 5.1 接收器与 Infuse 对照：需要设备与安装包时逐项登记「待验证」，不阻塞其他工作。

## 已知风险

- libmpv/FFmpeg 的许可与打包；当前依赖 Homebrew。
- 窗口快照不包含 OpenGL 层，UI 自动比对需要另建渲染抓帧。
- 无 Infuse 安装与测试账号，参照矩阵无法闭环。
