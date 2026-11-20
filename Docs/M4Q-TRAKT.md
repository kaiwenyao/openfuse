# M4q 验收记录：Trakt 设备码与 scrobble

日期：2026-11-20。分支：`m4q-trakt`。基线：Infuse 8.5.10（参照客户端待装）。

补上 M4 仍缺的外部观看同步：Trakt OAuth 设备码、标题搜索、scrobble start/pause/stop。真实账号未提供，使用本地 Trakt 夹具验证 HTTP 契约与播放器触发。

## 交付内容

- `TraktClient`：`oauth/device/code`、`oauth/device/token`、`search/movie`、`scrobble/start|pause|stop`；Bearer + trakt-api-key + version 2。
- `TraktService`：环境配置（BASE_URL/CLIENT_ID/TOKEN），播放器加载时搜索并 start，保存时按 10s 节流 update，结束/看完 stop。
- probe：`trakt-device` / `trakt-poll`。
- 夹具 `Tools/trakt_fixture.py`；验收 `Scripts/run-trakt-acceptance.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设备码 | `/oauth/device/code` 返回 device_code/user_code |
| 轮询 | `/oauth/device/token` 返回 access_token |
| 搜索 | `/search/movie?query=openfuse-fixture` → trakt 1001 |
| start | POST `/scrobble/start` progress 0 |
| stop | POST `/scrobble/stop` progress **99.9467** |
| 播放 | 位置 59.968s |
| 脚本 | `Scripts/run-trakt-acceptance.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Trakt | 待验证 |

证据：`Evidence/82-trakt-scrobble.jpg`、`reports/m4q-trakt.jsonl`、`reports/m4q-trakt-play.json`、`reports/m4q-trakt.txt`。

## 可复现差异与未验证

1. **真实 Trakt 未验证**：client ID/secret、账号授权、限流、token 刷新。
2. **无 OAuth UI/Keychain 持久化**：仅环境变量配置。
3. **仅 movie 搜索**；剧集/集数匹配未实现。
4. **pause/progress 10s 节流**未做长时间测试；本轮只观察到 start/stop。
5. **Trakt 历史导入/双向同步**未做。
6. **音频**：尝试用 iFlyrec 回环 + ffmpeg 捕获被系统音频权限阻断；仍待人工听测。
7. **SMB3/并发、HDR/AirPlay 实机、CloudKit 真实账号、M3 多根/损坏过滤**未做。

## 下一项

Trakt 剧集匹配已在 [M4r 验收](Docs/M4R-TRAKT-EPISODES.md) 完成。剩余 M5s：真实账号/OAuth UI/历史、音频听测、SMB3/并发、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤。
