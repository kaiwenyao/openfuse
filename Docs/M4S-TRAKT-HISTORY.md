# M4s 验收记录：Trakt 历史导入

日期：2026-11-20。分支：`m4s-trakt-history`。基线：Infuse 8.5.10（参照客户端待装）。

M4r 只会向外 scrobble。现在拉取 Trakt `/sync/history/movies|shows`，按规范化标题匹配本地库，把对应本地集标记为已看；`--library-watch watched` 能看到电影和整部剧。

## 交付内容

- `TraktHistoryItem`；`TraktClient.history()` 拉取 movies/shows（limit 100）。
- `AppModel.syncTraktHistory`：
  - 标题规范化（去年份/标点/空格、小写）；
  - movie 匹配整部电影，show 按 season/number 匹配集；
  - 本地 `fileURL` 写入 PlaybackStore finished；
  - 刷新最近/状态。
- CLI `--sync-trakt`；扫描菜单「同步 Trakt 历史」。
- 夹具 history 端点；验收脚本 `Scripts/run-trakt-history.sh`。
- 修正 `traktConfigured` 供 UI 显示。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| history 请求 | `/sync/history/movies`、`/sync/history/shows` |
| 匹配 | **3 集**（电影 + 示例剧 S01E01/S01E02） |
| watched 筛选 | visible `["OpenFuse Fixture", "示例剧"]` |
| 自动化 | `Scripts/run-trakt-history.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Trakt | 待验证 |

证据：`Evidence/84-trakt-history.jpg`、`reports/m4s-trakt-watched.json`、`reports/m4s-trakt-history.jsonl`、`reports/m4s-trakt-history.txt`。

## 可复现差异与未验证

1. **真实 Trakt** 未验证：账号、限流、refresh、分页。
2. **仅本地 fileURL 条目写进度**；Jellyfin/Emby/WebDAV/SMB 历史标记未接。
3. **标题匹配可能冲突**（同名电影/剧），未用年份/ID 严格匹配。
4. **limit 100、无增量时间戳/分页**。
5. **无 OAuth UI/Keychain**。
6. **音频人工听测、SMB3/并发、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

M5t：Trakt 真实账号/OAuth UI/远程来源历史标记；音频听测；SMB3/并发；HDR/AirPlay 实机；CloudKit；M3 多根/损坏过滤。
