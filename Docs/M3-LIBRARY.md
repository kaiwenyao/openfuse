# M3a 验收记录：Mac 聚合媒体库与海报库

日期：2026-11-19。分支：`m3-library`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮建立 SQLite 媒体库、三个来源的扫描器、电影/剧/季/集层级、跨来源合并展示、海报网格、详情、搜索、电影版本与从媒体库播放。TMDB/NFO 识别、增量刷新和手工纠错留到 M3b。

## 交付内容

- **SQLite 媒体库**：`library.sqlite`，表 `works / seasons / episodes / versions`；按来源替换（`source_kind + source_id`）保证重复扫描幂等，不影响其他来源；WAL、事务、索引。
- **本地扫描**：递归枚举文件夹，解析 `Movie (2026)`、`S01E02`、`1x03`、`第N季第M集`；按剧名分组季/集；发现同目录 `poster.jpg`/`folder.jpg`/`cover.jpg` 与同名图片。
- **WebDAV 扫描**：递归 PROPFIND（默认 6 层、3000 文件上限），保留远程路径、外挂字幕与同名海报 URL；按同样规则分组。
- **Jellyfin 扫描**：`Recursive=true` 拉取 Movie/Series/Season/Episode；保留服务器 Id、名称、简介、年份、封面 tag、季集号；对电影调用 PlaybackInfo 保存多个服务器版本（名称、MediaSourceId、容器）。
- **跨来源合并展示**：按「类型 + 去括号年份的标题」分组，来源优先级 Jellyfin > 本地 > WebDAV；同一作品显示 3 个来源时只出现一张卡，详情页用来源胶囊切换（Jellyfin / 本地 / WebDAV），各自保留季集与版本。未接 TMDB，按标题合并只是临时规则。
- **海报**：Jellyfin 使用服务器 Primary（带 token 的 AsyncImage）；本地读取文件；WebDAV 远程海报因需要 Basic Auth，暂显示占位图。
- **首页**：媒体库网格、作品/集计数、搜索框、扫描菜单（文件夹 / Jellyfin / WebDAV）；继续观看仍来自播放记录。
- **详情**：电影显示版本 Picker 与播放；剧集显示季选择、S 剧集列表、每集播放；来源胶囊切换时重新加载对应来源数据。
- **从媒体库播放**：本地走文件 URL，WebDAV 走远程路径，Jellyfin 走 `openJellyfinItem`（保留 MediaSource）；字幕/音轨/续播沿用 M1–M2 会话逻辑。
- **夹具**：`Tools/make_library_fixture.py` 生成 1 部电影 + 2 部剧 + 4 集；Jellyfin/WebDAV 夹具复用同一测试片。

## 数据模型

```
works(id, kind movie|series, title, sort_title, year, overview, poster,
      source_kind, source_id, server_id, added_at, updated_at)
seasons(id, work_id, number, title, poster, source_kind, source_id)
episodes(id, work_id, season_id, season_number, episode_number, title, overview,
         runtime, poster, source_kind, source_id, server_id, remote_path,
         remote_variant, file_url)
versions(id, item_id, work_id, name, source_kind, source_id, remote_path,
         media_source_id, container, resolution, file_url)
```

- 电影也有一条 episode 记录（season_number=0），使版本/播放逻辑统一。
- 续播键仍由 M1/M2 的 `PlaybackRecord` 管理；媒体库不重复存观看位置。
- 分组只发生在 UI/AppModel，原始行仍按来源保留，便于 M3b 做 TMDB 合并与手工纠错。

## 复现

```bash
Scripts/run-library-acceptance.sh
```

脚本会生成测试片（若缺失）、本地媒体目录、启动 Jellyfin/WebDAV 夹具，依次扫描三类来源、截图首页/详情/搜索，并从媒体库播放一集；产物在 `build/library-acceptance/`。

手工：

```bash
python3 Tools/make_library_fixture.py
open build/OpenFuse.app
# 首页「扫描」→ 扫描文件夹… 选择 build/library-fixture
```

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **20/20 通过**（新增文件名解析、SQLite 增删查/搜索/替换、本地分组扫描） | 终端 |
| 本地扫描 | 3 个作品 / 4 集；电影 2026、剧集两季结构正确 | `reports/m3-library-local.json`、Evidence 19 |
| +Jellyfin | 原始行 5 / 7；合并为 3 个作品；Jellyfin 电影保留 2 个版本 | `reports/m3-library-aggregate.json` |
| +WebDAV | 原始行 7 / 9；合并为 3 个作品；来源集合 local/jellyfin/webdav | `reports/m3-library-aggregate-webdav.json`（Evidence 20 展示本地+Jellyfin 合并态） |
| 搜索 | 输入「示例」只剩示例剧；组内任一来源标题命中即保留 | Evidence 22 |
| 剧集详情 | 来源胶囊「Jellyfin 2 / 本地 2」，季选择、S01E01/S01E02、简介 | Evidence 21 |
| 电影详情 | 版本「1080p HEVC 5.1 / 720p 压缩版」，播放按钮 | Evidence 23 |
| 媒体库播放 | 从详情播放本地单集，9.958 s 冻结帧，外挂简体字幕选中 | `reports/m3-library-play.json`、Evidence 24 |
| 跨来源播放 | 另测 WebDAV 单集与 Jellyfin 单集从媒体库播放，sourceKind/字幕正确 | 运行记录 |

端到端脚本输出：

```
PASS: local/Jellyfin/WebDAV scan, 7 works/9 episodes, search, details, library playback
```

## 可复现差异与未验证

1. **没有 TMDB/NFO 识别。** 当前标题来自文件名/服务器，跨来源合并按规范化标题，可能误合并同名不同年作品；缺海报时用占位图。TMDB API key 未提供，相关组合标「待验证」。
2. **WebDAV 海报未加载。** 远程 poster 需要 Basic Auth，AsyncImage 无法带头；当前占位。M3b 可加带凭据的图片缓存。
3. **合并是展示层。** 原始行仍按来源保留；详情用来源胶囊切换，未把同一集的多个来源版本列在同一集下。跨源「多版本」只做到来源级，未做集级合并。
4. **电影多版本只对 Jellyfin 扫描时拉取 PlaybackInfo。** 本地/WebDAV 同片多文件未识别为多版本（README 的「同片多版本」待 M3b）。
5. **无增量刷新。** 每次扫描替换整来源；无目录分页、取消、扫描进度、增量 diff、扫描中断恢复；T07 的 10,000 条目压力未测。
6. **无手工纠错。** 改标题/海报/合并/拆分、NFO/XML、家庭视频、同名不同年、合集、播放列表均未实现。
7. **首页排序/继续观看**：媒体库按标题排序，未实现最近添加/继续观看排序、防剧透、类型/分辨率筛选；继续观看来自播放记录而非库状态。
8. **本地扫描**会把同名剧在不同目录合并为一个作品；季/集冲突未处理。
9. **Poster 尺寸**：合成海报是 16:9 帧裁切，卡片比例与 Infuse 海报不一致；没有参照截图。
10. **性能与文件系统**：未测大目录、网络文件、符号链接、权限错误；SQLite 未做迁移版本管理。
11. **真实服务/多端**：真实 Jellyfin/OpenList、跨设备续播、iPhone/iPad/tvOS/visionOS 未验证。

## 下一项

M3b 的 TMDB + NFO + 远程海报已记录于 [M3b 元数据验收](M3B-METADATA.md)。剩余 M3c：手动匹配、集级跨源版本合并、增量扫描/取消、手工纠错、最近添加/继续观看排序、WebDAV NFO/认证海报、T06/T07 压测；随后进入 M4。
