# M2b 验收记录：Jellyfin Direct Mode

日期：2026-11-19。分支：`m2-remote-sources`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮实现 Jellyfin Direct Mode 的最小可用链路：登录 → 媒体库 → 电影/剧/季/集 → 服务器封面与版本 → 直连播放 → 音轨/字幕 → 进度开始/进度/停止回写 → 用服务器位置续播。真实 Jellyfin 账号没有提供，全部验证使用仓库内的 Jellyfin 协议夹具；真实服务器标记为「待验证」。

## 交付内容

- **登录与来源管理**：`/Users/AuthenticateByName`，`X-Emby-Authorization` 带 Client/Device/DeviceId；令牌存 Keychain（`com.openfuse.jellyfin`），来源元数据存 `jellyfin-sources.json`。首页 Jellyfin 来源卡片、添加表单、移除。
- **Browse Direct**：`/Users/{userId}/Views`、`/Users/{userId}/Items?ParentId=...`；媒体库 → 剧 → 季 → 集按服务器层级展示；电影/剧集卡片使用服务器 `Primary` 封面，标题与年份来自服务器。
- **详情与版本**：电影/单集详情拉取 `/Users/{id}/Items/{itemId}` 与 `/Items/{id}/PlaybackInfo`；展示服务器标题、封面、年份、时长、简介；多版本用分段选择器；显示「直连/重封装/转码」。
- **播放**：优先 `SupportsDirectPlay` 的 MediaSource，使用 `DirectStreamUrl`（或 `/Videos/{id}/stream` 回退）；libmpv 以 `X-Emby-Token` 头访问；HEVC Main 10 仍走 VideoToolbox。
- **服务器轨道名**：把 MediaStreams 的音频/内嵌字幕 `DisplayTitle` 映射到 mpv 轨道菜单。夹具故意返回「服务器音轨 · E-AC-3 5.1」「服务器字幕 · 中日双语」，验收报告里能看到服务器命名，而不是本地文件里的标题。
- **进度回写**：播放开始 `POST /Sessions/Playing`，每 5 秒 `POST /Sessions/Playing/Progress`，退出/结束 `POST /Sessions/Playing/Stopped`；包含 ItemId、MediaSourceId、PlaySessionId、PositionTicks、IsPaused、PlayMethod=DirectPlay。停止事件只发一次。
- **服务器续播**：打开条目时读取 `UserData.PlaybackPositionTicks`，与本地记录取较大值；全新本地库也能从服务器位置继续。
- **夹具**：`Tools/jellyfin_fixture.py`，实现登录、Views、Items、PlaybackInfo、带 Range 的 `/Videos/{id}/stream`、Primary 图片、三个 Sessions 端点；内存中更新观看位置；生成合成封面。

## API 与数据流

```
JellyfinBrowserView
   ├─ GET Views / Items?ParentId  ──> JellyfinClient(actor)
   ├─ GET Items/{id} / PlaybackInfo ──> 详情 + 版本
   └─ openJellyfinItem ──> MediaItem.jellyfin ──> PlayerModel ──> libmpv
                                                    │  X-Emby-Token
                                                    └─ 进度上报：Playing/Progress/Stopped
```

- `JellyfinClient` 只处理协议；`MediaItem` 保存 `jellyfinContext`（item、media source、play session、token、runtime、服务器位置、MediaStreams）。
- `PlaybackRecord` 沿用 `sourceKind=source/jellyfin`、`remotePath="<itemID>|<mediaSourceID>"`，首页续播时可按来源与版本重开。
- 服务器位置只在打开时读取；播放中以内嵌的 `PlaySessionId` 回写，避免旧会话覆盖新位置。

## 复现

```bash
# 协议层
Scripts/test-jellyfin.sh

# 端到端：直连播放、服务器元数据、版本选择、进度、服务器续播
Scripts/run-jellyfin-acceptance.sh
```

手工夹具：

```bash
python3 Tools/jellyfin_fixture.py --setup --port 8096
# http://127.0.0.1:8096   test / test   token jf-test-token
```

真实服务器：添加来源填 `http://host:8096`，测试账号密码；Direct Mode 直接浏览，未做 Library 聚合。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **17/17 通过**（新增 Jellyfin 条目、PlaybackInfo、版本 URL、ticks、MediaItem 身份） | 终端 |
| 协议探针 | 登录、2 个媒体库、电影条目、2 个版本、绝对 stream URL、图片 URL、带 token 的 Range 206、MKV magic | `Scripts/test-jellyfin.sh` |
| 401 | 错误密码被拒绝 | 同上 |
| 单集直连 | `ep-1`，60.000 s，HEVC Main 10，`hwdec=videotoolbox`；标题「第 1 集」 | `reports/m2-jellyfin-episode.json`、Evidence 15 |
| 服务器轨道 | 音频菜单「服务器音轨 · E-AC-3 5.1」，字幕「服务器字幕 · 中日双语」 | 同上 |
| 版本选择 | 电影选择 `ms-movie-compact`，服务端流请求 MediaSourceId 为该版本 | `reports/m2-jellyfin-movie.json`、服务端日志 |
| 进度回写 | Playing → Progress(4.7 s, 9.7 s, 9.917 s) → Stopped(9.917 s) | `reports/m2-jellyfin-server-log.jsonl` |
| 服务器续播 | 全新本地库打开同一集，Playing PositionTicks=99,170,000；6 s 后报告 15.375 s | `reports/m2-jellyfin-resume.json`、日志 |
| 浏览 UI | 电影库/电视剧库、封面、来源名 | Evidence 13–14 |
| 播放器 | 来源显示「Jellyfin 测试」，音轨/字幕为服务器命名 | Evidence 18、15 |

端到端脚本最终输出：

```
PASS: Jellyfin direct play, server metadata, version switch, progress, server resume
```

## 可复现差异与未验证

1. **真实 Jellyfin 未验证。** 没有账号，夹具是协议级近似；真实服务器的 HTTPS、反向代理子路径、令牌过期、转码决策都未覆盖。
2. **只验证 Direct Play。** 代码在 `SupportsDirectPlay=false` 时选 `TranscodingUrl`，但没有真实转码器与带宽测试；没有码率/质量选择。
3. **外部字幕流未验证。** `MediaItem.serverSubtitles` 能构造 `DeliveryUrl`，夹具只有内嵌 ASS；真实服务器的外挂字幕路径待测。
4. **轨道映射按顺序。** 目前用服务器 MediaStreams 顺序覆盖 mpv 同类轨道标签；若 mpv 重排或服务器轨道缺失可能错位。应改为按 `Index`/语言/编码显式匹配。
5. **进度冲突规则简单。** 打开时取 `max(本地, 服务器)`；已看/未看、暂停即回写、跨设备覆盖、重复停止事件尚未按 T08 设计验证。
6. **封面加载把 token 放 query。** 真实服务可能记录 URL；生产应改为带 Authorization 头的图片加载器，避免令牌进日志。
7. **Library Mode 与海报库未实现。** 当前是 Direct 浏览（库→剧→季→集），没有聚合首页、TMDB、继续观看/最近添加排序；属于 M3。
8. **Keychain 首次授权、ad-hoc 签名。** 自动化用 `OPENFUSE_JELLYFIN_PASSWORD`/Token 环境变量并跳过写 Keychain；真实用户首次登录会看到系统授权。
9. **详情 sheet 未截图。** 应用内 `cacheDisplay` 不捕获独立 sheet 窗口；版本选择通过日志验证，UI 代码已存在但未做像素对照。
10. **无服务器发现、自签名证书、多用户切换、播放列表、下集、Played 标记。**
11. **性能未测。** 未做首帧/拖动 P95、20 次统计；进度回写频率固定 5 s。

## 下一项

1. 用真实 Jellyfin 10.10 测试账号验证登录、HTTPS、转码、外挂字幕与多用户；缺账号的组合标「待验证」。
2. 轨道映射改为显式 MediaStream Index；暂停/拖动立即回写进度。
3. M3：Library Mode 聚合、TMDB 识别、海报库、继续观看/最近添加、搜索与电影多版本。
4. 真实 OpenList/百度网盘验证与跨域凭据代理。
