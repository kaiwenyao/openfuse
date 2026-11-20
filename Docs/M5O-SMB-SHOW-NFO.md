# M5o 验收记录：SMB 跨季 tvshow NFO、海报与重连

日期：2026-11-20。分支：`m5o-smb-show-nfo`。基线：Infuse 8.5.10（参照客户端待装）。

SMB 剧集此前只读当前目录 NFO，季目录里的集无法继承 show 标题/海报。现在维护 show 目录元数据并向祖先查找；单集/电影 NFO 优先。另修复扫描过程中 impacket 返回 `STATUS_SHUTDOWN` 导致第二季漏扫：失败时重连并重试一次。

## 交付内容

- `showNFOByDirectory` / `showPosterByDirectory`；`showContext(for:)` 向上查找最近 show NFO。
- 单集 NFO 优先于 show NFO；show poster 作为季/集回退海报。
- `SMBClient.reconnect()`；扫描 list/fetch 与流读取失败后重连重试一次。
- 验收夹具：电影 NFO/海报/字幕 + 两季剧集 + tvshow.nfo/poster + S01E01 NFO。
- 验收脚本更新为 2 作品/3 集、跨季、字幕、seek31、无整文件缓存。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 作品/集 | **2 作品/3 集** |
| 剧集 | SMB 示例剧 2 季；S01E01「NFO 第一集」、S02E01「第 1 集」 |
| 海报 | show poster 缓存到 `SMBPosterCache`，库中 file: |
| 重连 | Season 02 在 STATUS_SHUTDOWN 后重连成功入库 |
| 播放 | S01E01 sourceKind smb，seek 31.0s，SRT mpv:1 |
| 缓存 | 无 SMBCache；有 SMBSubtitleCache |
| 脚本 | `Scripts/run-smb-acceptance.sh` PASS |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 SMB3/DFS | 待验证 |

证据：`Evidence/79-smb-show-seasons.jpg`、`80-smb-show-play.jpg`、`reports/m5o-smb-*.json`、`reports/m5o-smb-show.txt`。

## 可复现差异与未验证

1. **真实 SMB3/DFS/签名/大文件**未测；只测 impacket SMB2。
2. **深层 show 根目录/多级目录**继承只按最近祖先，未处理复杂库结构。
3. **并发 Range/背压/句柄失效重开**未测；重连会打断正在进行的流。
4. **SMB 字幕仅同目录/base 匹配**；跨目录字幕未做。
5. **仅 macOS**；iOS/tvOS/visionOS 无 SMB。
6. **音频未听测、HDR/AirPlay 实机、CloudKit/Trakt、版本级去重、M3 多根/损坏过滤**未做。

## 下一项

Jellyfin/Emby 版本级去重已在 [M5p 验收](Docs/M5P-VERSION-DEDUPE.md) 完成。剩余 M5q：真实服务器版本 ID/顺序、音频轨去重、SMB3/并发、HDR/AirPlay 实机、CloudKit/Trakt、音频、M3 多根/损坏过滤。
