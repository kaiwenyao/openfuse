# M4r 验收记录：Trakt 剧集匹配

日期：2026-11-20。分支：`m4r-trakt-episodes`。基线：Infuse 8.5.10（参照客户端待装）。

M4q 只会 movie 搜索。现在 AppModel 在播放剧集前准备 `TraktQuery(show, season, episode)`，TraktService 搜索 `/search/show`，scrobble body 带 `episode{season,number}`；电影路径不变。

## 交付内容

- `TraktQuery`（movie/show + title/year/season/episode）。
- `TraktService.prepare`；有 prepared query 即使用，不再要求 Player 标题完全相等。
- `TraktClient.scrobble` 增加 season/episode，show body 写入 `episode`。
- 夹具 `/search/show`；验收脚本覆盖电影与剧集。
- 播放器加载/保存/结束触发 show scrobble。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Show 搜索 | `/search/show?query=示例剧` → trakt 2001 |
| start | body 含 `show.ids` + `episode{season:1,number:1}`，progress 0 |
| stop | progress **99.9467**，同一 episode |
| 电影路径回归 | `/search/movie` + movie scrobble 仍通过 |
| 脚本 | `Scripts/run-trakt-acceptance.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Trakt | 待验证 |

证据：`Evidence/83-trakt-show.jpg`、`reports/m4r-trakt.jsonl`、`reports/m4r-trakt-show.txt`。

## 可复现差异与未验证

1. **真实 Trakt** 未验证：client、账号、限流、refresh。
2. **无 OAuth UI/Keychain**；仍环境变量。
3. **剧集匹配依赖库 work/episode 标题/季集**；特殊命名/绝对集号未处理。
4. **pause/progress 10s 节流**未做长时间测试。
5. **历史导入/双向同步**未做。
6. **音频回环捕获被系统权限阻断**；仍待人工听测。
7. **SMB3/并发、HDR/AirPlay 实机、CloudKit 真实账号、M3 多根/损坏过滤**未做。

## 下一项

M5s：Trakt 真实账号/OAuth UI/历史；音频人工听测；SMB3/并发；HDR/AirPlay 实机；CloudKit；M3 多根/损坏过滤。
