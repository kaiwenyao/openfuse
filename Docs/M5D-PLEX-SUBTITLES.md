# M5d 验收记录：Plex 外挂字幕

日期：2026-11-20。分支：`m5d-plex-subs`。基线：Infuse 8.5.10（参照客户端待装）。

Plex metadata 的 `Media[].Part[].Stream[]` 中字幕流（streamType=3）现在会带 `X-Plex-Token` 下载到缓存，转换成 `SubtitleTrack`，随 `MediaItem.plex` 交给 libmpv；播放语言选择复用 `--subtitle` 与播放器字幕菜单。

## 交付内容

- `PlexStream` / `PlexPart.Stream` 解码；`PlexClient.metadata(ratingKey)`、`subtitleData(streamKey)`。
- `PlexSubtitle.tracks`：codec/language 归一化（chi/zho→zh-Hans，cht→zh-Hant，jpn/ja 等），缓存文件，forced 标记。
- AppModel `openPlexItem` 异步拉 metadata/字幕；`MediaItem.plex` 接受 subtitles。
- 夹具 `/library/metadata/401` Stream + `/library/streams/401-srt` 服务；验收 `--subtitle zh-Hans`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Plex 字幕流下载 | GET `/library/streams/401-srt` 200 |
| 字幕轨道 | `Plex 外挂简体|zh-Hans` + 内嵌 `中文（简体） · 中日双语|zh` |
| 选择 | selectedSubtitle **mpv:1** |
| 画面 | 9.958s 显示「第二句：中文字体回退测试…」 |
| 扫描/播放 | 2 作品/3 集；sourceKind plex |
| `swift test` | **28/28 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 真实 Plex | 待验证 |

证据：`Evidence/61-plex-subtitle.jpg`、`reports/m5d-plex-*.json`、`reports/m5d-plex-subtitle.txt`。

## 可复现差异与未验证

1. **真实 Plex** 字幕流鉴权/格式/语言字段未验证。
2. **没有 Plex 直连浏览页**；仍是库扫描/海报/详情/播放。
3. **Plex 音轨选择/版本切换未接**；只做字幕。
4. **Emby/SMB、HDR/AirPlay、自包含打包**未做。
5. **CloudKit 真实账号/Trakt、自动同步/离线队列**未做。
6. **音频主观听测、M3 T07/WebDAV MKV 分辨率**未做。

## 下一项

macOS 自包含打包已在 [M5e 验收](Docs/M5E-PACKAGING.md) 完成。剩余 M5f：公证/Universal、Plex 直连/音轨/版本、Emby/SMB/HDR/AirPlay、CloudKit/Trakt、音频、M3 尾项。
