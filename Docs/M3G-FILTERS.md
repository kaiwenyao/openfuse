# M3g 验收记录：媒体库排序与类型筛选

日期：2026-11-20。分支：`m3g-filters`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮补 Mac 媒体库的组织操作：标题/年份/最近添加/集数排序，电影/剧集筛选，搜索与排序组合；`addedAt` 分别来自本地文件 mtime、WebDAV mtime、Jellyfin DateCreated。防剧透和 T07 深入仍未做。

## 交付内容

- **排序**：标题、年份降序、最近添加降序、集数降序；`AppModel.visibleLibraryGroups` 统一计算，UI 与验收报告一致。
- **筛选**：全部 / 电影 / 剧集；与搜索、排序组合。
- **最近添加**：`ScannedWork.addedAt`：
  - 本地文件 `contentModificationDate`；
  - WebDAV `RemoteEntry.modifiedAt`；
  - Jellyfin `DateCreated`（ISO8601，缺失时回退扫描时间）。
- **搜索**：片名/简介，组内任一来源命中即保留。
- **报告**：`--library-report` 增加 `visible` 字段（按当前筛选/排序），供自动化断言。
- **CLI**：`--library-sort title|year|added|episodes`、`--library-filter movie|series`，与 `--library-search` 组合。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **25/25 通过** | 终端 |
| `Scripts/run-library-filters.sh` | **PASS**：电影筛选只剩《OpenFuse Fixture》；剧集按集数《示例剧》在前；搜索「示例」只剩《示例剧》 | 终端 |
| 类型筛选 | `visible = ["OpenFuse Fixture"]` | `reports/m3g-filter-movies.json`、Evidence 36 |
| 集数排序 | `visible = ["示例剧", "另一部剧 · 本地 NFO"]` | `reports/m3g-filter-series.json` |
| 搜索 + 标题排序 | `visible = ["示例剧"]` | `reports/m3g-filter-search.json` |
| 既有回归 | 三源扫描/合并、版本菜单、TMDB/NFO、Jellyfin 进度、WebDAV NFO/海报、本地播放/续播、10k 扫描保持 | 各脚本 |

脚本输出：

```
PASS: type filter, episode-count sort, title sort, search
```

## 可复现差异与未验证

1. **最近添加在本地夹具中时间相同。** 硬链接共享源片 mtime；Jellyfin 夹具已加 DateCreated。测试只验证了排序代码与报告，未在 UI 上逐项比对顺序。
2. **没有防剧透。** 未隐藏简介/缩略图，也未按已看状态模糊。
3. **筛选只到类型。** 分辨率、HDR、观看状态、来源、评分/类型未做。
4. **没有“继续观看”专门排序。** 首页“继续观看”仍独立于媒体库排序；未按最近播放/进度排序。
5. **T07 深入未做**：扫描中播放、目录超时恢复、重启后新增字幕只更新目标条目。
6. **真实 OpenList/Jellyfin、Infuse 对照、人工听测、多端**仍未验证。

## 下一项

M3h：防剧透、观看状态/分辨率筛选、继续观看排序；或按计划进入 M4 家庭设备与状态同步（M3 剩余项单列为待办）。
