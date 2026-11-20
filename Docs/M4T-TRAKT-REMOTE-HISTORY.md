# M4t 验收记录：Trakt 历史回填远程来源

日期：2026-11-20。分支：`m4t-trakt-remote-history`。基线：Infuse 8.5.10（参照客户端待装）。

M4s 只给本地 fileURL 写已看。本轮生成播放器一致的 fingerprint key：Jellyfin/Emby、WebDAV、SMB、Plex、本地，Trakt history 匹配后把每个版本键标 finished；远程 Jellyfin 的 watched 筛选已验收。

## 交付内容

- `AppModel.playbackKeys(work:episode:)`：
  - Jellyfin/Emby：`kind://sourceID/itemID/mediaSourceID`；
  - WebDAV：`webdav://sourceID/path`；
  - SMB：`smb://sourceID/path`；
  - Plex：`plex://sourceID/partKey`；
  - 本地：fileURL path。
- `syncTraktHistory` 对每个版本 key 写 finished；按集计数。
- 验收脚本 `Scripts/run-trakt-remote-history.sh`：Jellyfin 扫描 + Trakt history + watched 筛选。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Jellyfin 扫描 | 2 作品/3 集 |
| History 匹配 | **3 集** |
| watched 筛选 | `["OpenFuse Fixture (2026)", "示例剧"]`，sourceKind jellyfin |
| 自动化 | `Scripts/run-trakt-remote-history.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| WebDAV/SMB/Plex key 路径 | 代码已接，未逐一验收 |
| 真实 Trakt | 待验证 |

证据：`Evidence/85-trakt-remote-history.jpg`、`reports/m4t-trakt-watched.json`、`reports/m4t-trakt-remote-history.txt`。

## 可复现差异与未验证

1. **真实 Trakt** 未验证：账号/限流/refresh/分页。
2. **WebDAV/SMB/Plex history 回填未实测**；只有 Jellyfin。
3. **标题匹配可能冲突**；未用年份/Trakt ID 严格匹配。
4. **无 OAuth UI/Keychain**。
5. **音频人工听测、SMB3/并发、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

Trakt OAuth 设置页已在 [M5t 验收](Docs/M5T-TRAKT-OAUTH-UI.md) 完成 UI/协议验证。剩余 M5u：真实账号/自动轮询、音频听测、SMB3/并发、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤。
