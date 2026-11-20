# M5 验收记录：Plex 来源（Mac 媒体库 + 直连播放）

日期：2026-11-20。分支：`m5-plex`。基线：Infuse 8.5.10（参照客户端待装）。

M5 首个新来源：Plex。数据层使用 Plex JSON API（sections/items/children），媒体库扫描电影/剧/季/集；海报以 `plex:<ratingKey>` 引用存储，UI 用 token 动态生成 URL；播放经 `/library/parts/{key}/file?X-Plex-Token=...` 交给 libmpv。

## 交付内容

- `PlexClient`：`/library/sections`、sections/all、metadata children、part stream、thumb；token query/header。
- `PlexSourceStore` + macOS Keychain；`PlexLibraryScanner` 生成 works/seasons/episodes/versions；分辨率/容器。
- `MediaItem.Origin.plex`；`plex://` 续播键；库详情播放走 mpv。
- Mac UI：工具栏「Plex」添加来源（地址/token）、Plex 来源卡扫描/删除；媒体库海报/详情/播放。
- 夹具 `Tools/plex_fixture.py`；验收 `Scripts/run-plex-acceptance.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 添加/扫描 | 2 作品 / 3 集：电影 + 1 剧（1 季 2 集） |
| 海报 | `plex:<ratingKey>` 引用；UI 带 token 解析，不把 token 写进库 |
| 播放 | sourceKind **plex**，冻结 **9.917s**，标题「Plex 第 1 集」 |
| 服务器 | sections/children/parts API + Range 流 |
| `swift test` | **28/28 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 真实 Plex | **待验证**：仅本地 JSON 夹具 |
| Emby/SMB/HDR/AirPlay | 未开始 |

证据：`Evidence/58-plex-library.jpg`、`59-plex-playback.jpg`、`reports/m5-plex-*`、`reports/m5-plex.txt`。

## 可复现差异与未验证

1. **真实 Plex 未验证**：token 生命周期、HTTPS、XML fallback、转码、远程访问未测。
2. **没有 Plex 直连浏览页**：只做库扫描/海报/详情/播放；未做 Plex 目录浏览、版本选择、服务器搜索。
3. **Plex 外挂字幕/音轨未接**：播放走 mpv 直连；Plex 字幕流未下载。
4. **Plex 进度未回写**：只写本地 PlaybackStore，未调用 Plex timeline/scrobble。
5. **Emby/SMB、HDR/AirPlay、自包含打包**未做。
6. **CloudKit 真实账号、Trakt、自动同步/离线队列**未做。
7. **音频主观听测、M3 T07/WebDAV MKV 分辨率**未做。

## 下一项

M5b：Plex 直连浏览/进度回写/字幕；Emby；SMB；HDR/AirPlay；自包含打包；CloudKit/Trakt；音频听测；M3 尾项。
