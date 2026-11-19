# M3c 验收记录：集级跨来源版本合并

日期：2026-11-19。分支：`m3c-aggregation`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮把 M3a/M3b 的「作品层合并 + 来源胶囊」推进到「同一集聚合多来源版本」：电影详情列出所有来源/清晰度版本；剧集按季/集合并，每一集显示来源与版本数量，并通过菜单选择具体来源播放。

## 交付内容

- **`LibraryAggregation`（Core）**：给定 `LibraryGroup` 与 `LibraryStore`，按 `(season, episode)` 合并各来源剧集；同一集收集每个来源的 `versions`，生成 `MergedLibraryEpisode` / `MergedLibraryVersion`。
- **电影**：同一作品的不同来源（Jellyfin 多 MediaSource、本地文件、WebDAV 文件）合并为版本 Picker，标签形如「Jellyfin · 1080p HEVC 5.1」「Jellyfin · 720p 压缩版」「本地 · 本地文件」「WebDAV · WebDAV」。
- **剧集**：统一集列表；每集带「N 个版本」徽标；播放按钮改为菜单，逐项列出「来源 · 版本名」，选择后调用原播放链路（Jellyfin/本地/WebDAV）。
- **播放**：`playMergedVersion` 携带源作品、源剧集、版本，复用 M1–M2 的 MediaItem/播放会话；续播键仍按来源/条目/版本独立保存，切版本不会串进度。
- **标题/简介**：以 Jellyfin 为主来源的标题、季集号、简介；本地/NFO 与 WebDAV 仅补版本与缺失集。
- **兼容**：没有合并组的单来源作品仍显示一条版本；M3a 的来源胶囊移除，改为版本菜单，减少一次跳转。

## 合并规则

```
LibraryGroup.works（Jellyfin > 本地 > WebDAV）
  ├─ work A episodes ─┐
  ├─ work B episodes ─┼─ key = S{season}E{episode}
  └─ work C episodes ─┘
        └─ versions = [source · version name] 去重后按来源顺序
```

- 电影用 `season=0, episode=1` 的统一记录，因此与剧集共用合并逻辑。
- 集标题优先取来源顺序中的第一个非空；运行时/简介补空。
- 没有版本行的条目生成「来源 · 播放」占位，避免无按钮。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **23/23 通过**（新增跨来源电影合并：1 集 2 版本） | 终端 |
| `Scripts/run-library-acceptance.sh` | **PASS**：本地+Jellyfin+WebDAV 原始 7 作品/9 集、合并 3 组 | 终端 |
| 电影合并 | 1 集，**4 个版本**：Jellyfin 1080p、Jellyfin 720p、本地、WebDAV | `reports/m3-library-aggregate-webdav.json` 的 `merged`、Evidence 29 |
| 剧集合并 | 《示例剧》2 集：S01E01 **3 个版本**、S01E02 2 个版本 | 同上、Evidence 30 |
| 详情 UI | 电影版本 Picker；剧集每集「N 个版本」菜单 | Evidence 29–30 |
| 原有播放 | 本地/WebDAV/Jellyfin 从库播放与字幕/进度回归通过 | `reports/m3-library-play.json` |

端到端输出：

```
PASS: local/Jellyfin/WebDAV scan, 7 works/9 episodes, search, details, library playback
```

## 可复现差异与未验证

1. **合并键仍是启发式。** 类型 + 规范化标题（去年份、去冒号副标题）；同名/重制可能误合并。没有 TMDB id 作为权威键。
2. **手动匹配/拆分/合并未实现。** 不能指定「这两个文件是同一部」或把误合并拆开。
3. **增量扫描/取消未实现。** 仍整源替换；大库扫描、断点恢复、扫描中播放优先未测。
4. **T07 10,000 条目压力未执行。**
5. **WebDAV NFO 与认证海报缓存未做。** WebDAV 版本可用，但本地 NFO 只覆盖本地；远程海报依赖 TMDB 或占位。
6. **集标题/简介来源顺序固定为 Jellyfin > 本地 > WebDAV**，没有逐字段选择；NFO 与 TMDB 的优先级只在扫描阶段。
7. **版本级续播独立**，但 UI 未显示每个版本各自的进度；切版本后从头/各自位置。
8. **真实服务、Infuse 对照、人工听测、多端**仍未验证。

## 下一项

M3d：手动匹配/拆分合并、增量扫描与取消、WebDAV NFO/海报缓存、最近添加/继续观看排序、T06/T07 压力与中断恢复；完成 M3 后再进入 M4 家庭设备与状态同步。
