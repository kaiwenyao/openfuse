# M5k 验收记录：Plex 详情、版本/音轨与播放

日期：2026-11-20。分支：`m5k-plex-detail`。基线：Infuse 8.5.10（参照客户端待装）。

Plex Direct 详情页现在展示每个 Media 版本（1080p/720p）和每个版本的音频流（E-AC-3 5.1 / AAC 2ch），可按版本播放；新增 `--plex-play` 与自动进入 section/item 的测试钩子，实际播放第 1 集并选中 Plex 外挂字幕。

## 交付内容

- `openPlexMedia(metadata:source:mediaIndex:)`：按版本 part key 播放。
- `playPlexMetadata(source:ratingKey:)`：拉 metadata 后播放；CLI `--plex-play <ratingKey>`。
- `PlexMetadataView`：
  - 「版本与音轨」列表，显示分辨率/容器/音频流/声道；
  - 每个版本「播放此版本」；
  - 修复电影误请求 children 的 404（仅 show/season 拉 children）；
  - `OPENFUSE_PLEX_ITEM` 自动进入条目；`OPENFUSE_PLEX_AUTOPLAY` 自动播放。
- 夹具音频流：1080p E-AC-3 5.1 6ch + AAC 2ch；720p AAC 2ch。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 详情 | 1080p/720p 两版本；E-AC-3 5.1 6ch / AAC 2ch 显示 |
| 电影 children | 不再请求，404 消失 |
| 播放 | `--plex-play 401`，sourceKind plex，9.917s |
| 字幕 | selectedSubtitle **mpv:1**，Plex 外挂简体在内 |
| 脚本 | `Scripts/run-plex-browser.sh` PASS（sections/grid/detail/play） |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Plex | 待验证 |

证据：`Evidence/72-plex-detail-versions.jpg`、`73-plex-detail-play.jpg`、`reports/m5k-plex-detail-play.json`、`reports/m5k-plex-detail.txt`。

## 可复现差异与未验证

1. **真实 Plex** metadata/stream 形态、分页、版本顺序未验证。
2. **音频听测未做**：只展示/选择，未确认 E-AC-3 实际输出。
3. **版本级跨来源去重**未做。
4. **SMB/HDR/AirPlay 实机、CloudKit/Trakt、M3 多根/损坏过滤**未做。
5. **Infuse 同机对照、人工听测**仍缺。

## 下一项

M5l：真实 Plex 验证、版本级去重；SMB；HDR/AirPlay 实机；CloudKit/Trakt；音频；M3 多根/损坏过滤。
