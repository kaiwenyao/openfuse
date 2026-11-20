# M3e 验收记录：手动合并/拆分与 TMDB 候选

日期：2026-11-20。分支：`m3e-manual`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮补 M3 的手工整理能力：同类型作品手动合并、从误合并中拆分、恢复自动分组；编辑信息时可搜索 TMDB 候选并一键填入标题/年份/简介/海报。仍缺 WebDAV NFO/认证海报、最近添加排序和 T07 深入。

## 交付内容

- **手动合并**：详情右上「合并到…」列出同类型作品（电影对电影、剧集对剧集），选择后把当前作品的所有来源/版本并入目标分组。
- **拆分/恢复**：合并或误合并后点「拆分」，当前作品获得独立分组键，其他来源保持原组；「恢复自动」清除手动分组键，回到标题启发式。
- **持久化**：`LibraryOverride.mergeGroupID` 存入 `library-overrides.json`；与标题/年份/简介/海报覆盖共存；扫描替换来源后仍生效（work id 稳定）。
- **同类型限制**：合并只允许电影↔电影、剧集↔剧集，避免把电影并进剧集；跨类型在 UI 中不出现，模型层也会拒绝。
- **TMDB 候选**：编辑信息 sheet 增加「搜索 TMDB 候选」，显示多条结果（标题/年份/简介/id），点击填入表单；无 key 时提示配置 `OPENFUSE_TMDB_API_KEY`。
- **CLI 测试入口**：`--library-merge <目标>`、`--library-split`、`--library-edit-*`、`--library-clear-override`，配合 `--library-report` 与 `--capture-ui`。

## 复现

```bash
Scripts/run-manual-merge.sh
Scripts/test-tmdb.sh
```

手工：媒体库 → 作品详情 →「合并到…」选同类型目标；「拆分」；“编辑信息” →「搜索 TMDB 候选」。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **24/24 通过** | 终端 |
| 手动合并 | 本地 3 组中把《示例剧》并入《另一部剧》所在组，3→2 组 | `reports/m3e-merge-applied.json`、Evidence 33 |
| 合并后详情 | 分组显示两个来源/版本；S01E01「2 个版本」 | Evidence 33 |
| 拆分 | 2→3 组，当前作品独立分组 | `reports/m3e-merge-split.json` |
| 同类型限制 | 电影↔剧集合并被拒绝（模型层 guard） | 代码/单元逻辑 |
| TMDB 候选 | `Scripts/test-tmdb.sh` PASS，movie/tv 各返回 1 条候选 | 终端 |
| 编辑 sheet | 候选点击填入标题/年份/简介/海报；无 key 提示 | 代码（sheet 未截图） |

脚本输出：

```
PASS: manual merge (3→2 groups) and split (2→3 groups)
PASS: TMDB movie/TV search, poster URLs
PASS: invalid API key returns no match
```

## 可复现差异与未验证

1. **合并只作用于本地库。** 不修改服务器、文件名或 NFO；Jellyfin 服务器端的合并/识别不参与。
2. **TMDB 候选未做图像列表/多语言切换。** 只显示文本候选，选中后填 URL；真实 TMDB key/限流未验证。
3. **合并冲突规则简单。** 同集按 season/episode 合并版本；两套不同剧集合合并时只按集号对齐，可能产生无意义版本列表。
4. **无合并历史/审计。** 覆盖与分组键只存最新状态；没有撤销栈。
5. **WebDAV NFO/认证海报缓存未做。**
6. **最近添加/继续观看排序、筛选、防剧透未做。**
7. **T07 深入未做。** 扫描中播放、目录超时恢复、重启后新增字幕只更新目标条目。
8. **真实服务、Infuse 同机对照、人工听测、多端**仍未验证。

## 下一项

WebDAV NFO/认证海报已在 [M3f WebDAV NFO 验收](M3F-WEBDAV-NFO.md) 完成。剩余 M3g：最近添加/继续观看排序、筛选/防剧透、T07 扫描中播放/超时；完成后再进入 M4。
