# M5n 验收记录：SMB 句柄复用、NFO/海报与外挂字幕

日期：2026-11-20。分支：`m5n-smb-metadata`。基线：Infuse 8.5.10（参照客户端待装）。

SMB 此前只有裸文件名/占位海报。本轮让 SMB 扫描读取 NFO 与 poster/folder/cover 图片，缓存海报到 `SMBPosterCache`；播放前发现同目录外挂字幕并下载到 `SMBSubtitleCache`；同时复用 smb2fh，避免每 64KiB 重新 open/close。

## 交付内容

- `SMBClient` 句柄缓存（按路径），`closeHandles`/deinit 清理。
- `SMBLibraryScanner`：目录内 NFO（movie/tvshow/base）、poster 图片缓存、NFO posterReference 解析；`FileCandidate` 携带 NFO/poster。
- `openSMBItem`：列出同目录字幕，按 base 名称匹配，下载 SRT/ASS/VTT，生成 `SubtitleTrack`，随 `MediaItem.smb` 交给 mpv。
- `SubtitleCatalog.matchSubtitleName` 公开，供 SMB/远程复用。
- 验收夹具增加 NFO、poster、zh-Hans SRT；脚本断言标题/海报/字幕/seek/无整文件缓存。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| NFO 标题 | 「SMB NFO 电影」入库 |
| 海报 | `SMBPosterCache/<hash>.jpg`，库中 `file:` 引用 |
| 外挂字幕 | 中文（简体）(SRT)，selectedSubtitle **mpv:1** |
| Range/seek | 回环 HTTP，30s→**31.0s** |
| 整文件缓存 | SMBCache **不存在** |
| 句柄复用 | 单连接多 Range 读使用缓存句柄 |
| 脚本 | `Scripts/run-smb-acceptance.sh` PASS |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 SMB3/DFS/大文件 | 待验证 |

证据：`Evidence/77-smb-nfo-poster.jpg`、`78-smb-subtitle.jpg`、`reports/m5n-smb-*.json`、`reports/m5n-smb.txt`。

## 可复现差异与未验证

1. **真实 SMB3/DFS/签名/大文件**未测；只有 impacket SMB2。
2. **剧集 tvshow.nfo 跨季继承**未实现：只读当前目录 NFO；多季剧的海报/简介可能缺失。
3. **SMB 字幕仅同目录/base 匹配**；远程字幕编码/字体/ASS 样式仍由 libmpv。
4. **并发 Range/背压/句柄失效重开**未测。
5. **仅 macOS**；iOS/tvOS/visionOS 无 SMB。
6. **音频未听测、HDR/AirPlay 实机、CloudKit/Trakt、版本级去重、M3 多根/损坏过滤**未做。

## 下一项

SMB 跨季 tvshow NFO/重连已在 [M5o 验收](Docs/M5O-SMB-SHOW-NFO.md) 完成。剩余 M5p：真实 SMB3/并发/大文件、HDR/AirPlay 实机、CloudKit/Trakt、音频、版本级去重、M3 多根/损坏过滤。
