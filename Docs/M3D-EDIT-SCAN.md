# M3d 验收记录：手动纠错、扫描取消与 10,000 条目压力

日期：2026-11-20。分支：`m3d-edit`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮补 M3 的两块基础能力：媒体信息手工覆盖（标题/年份/简介/海报，可持久化/清除），以及可取消、带进度的扫描；同时执行 T07 的 10,000 条目首轮压力测试。

## 交付内容

- **本地覆盖**：`LibraryOverrideStore` 写入 `library-overrides.json`，按工作 ID 保存 title/year/overview/poster；扫描替换来源后覆盖仍生效；`apply(to:)` 在读取库后合并覆盖，不改服务器/文件名。
- **详情编辑**：Library 详情右上「编辑信息」sheet，修改标题、年份、海报 URL/本地路径、简介；保存立即刷新详情与首页；「清除本地覆盖」恢复原始元数据。
- **海报输入归一化**：`https://…` → `remote:`，本地存在路径 → `file:`，已带 `jellyfin:/file:/remote:` 前缀则保留；无效输入保留原海报。
- **扫描取消**：`ScanCancellationToken` 注入本地/WebDAV/Jellyfin 扫描；取消只停止本次任务，不替换 SQLite，旧库保持原样。
- **进度**：本地按文件数、WebDAV 按条目数、Jellyfin 按条目数显示「N 项」；扫描 header 出现 ProgressView + 取消按钮。
- **10,000 条目压力**：`Scripts/run-scan-stress.sh` 生成 10,000 个嵌套目录/空 MKV，测完整扫描、取消、取消后保留旧库；报告摘要写入 `summary.json`。
- **CLI 测试入口**：`--library-edit-title/-year/-overview/-poster`、`--library-clear-override`、`--cancel-scan-after`，配合 `--library-report` 复现。

## 复现

```bash
Scripts/run-editing-acceptance.sh
Scripts/run-scan-stress.sh
```

手工：扫描文件夹 → 进入任意作品 →「编辑信息」→ 保存；扫描中在媒体库标题旁点「取消」。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **24/24 通过**（新增 override store/apply） | 终端 |
| 编辑验收 | **PASS**：应用标题/2024/简介/海报，重启后仍生效；清除后恢复原值 | `Scripts/run-editing-acceptance.sh`、Evidence 31 |
| 扫描进度 | 10,000 项时显示「10,000 项 + 取消」，旧库保留 | Evidence 32 |
| 完整扫描 | **10,000 作品 / 10,000 集**，含应用启动与退出共 **6.52 s** | `reports/m3d-scan-stress.json` |
| 取消（空库） | 0 作品，状态「扫描已取消，媒体库保持原样」 | 同上 |
| 取消（已有 10k） | 10,000 作品保持不变 | 同上 |
| 文件上限 | 提高到 20,000 个媒体文件；目录不计数 | 代码 |

脚本输出：

```
PASS: 10000 works/episodes scanned in 6.52s; cancel leaves 0; cancelled rescan preserves 10000
PASS: manual title/year/overview/poster override, persistence, clear
```

## 可复现差异与未验证

1. **没有合并/拆分。** 只能改标题/年份/简介/海报；不能把误合并的两个作品拆开，也不能把两个条目手动合并。
2. **没有 TMDB 候选/手动 id。** 覆盖只是手填字段；不能搜索候选并一键匹配。
3. **不是真正的增量扫描。** 仍完整枚举后整源替换；取消可以保留旧库，但没有目录增量、文件变化 diff、断点恢复。10k 完整扫描是本地 SSD、空文件的上限参考，不代表真实媒体/网络目录。
4. **T07 只完成部分。** 未测扫描一半时播放、扫描中新增外挂、另一目录超时、重启后新增字幕只更新相邻影片；也未测索引大小/内存峰值。
5. **取消延迟。** 网络扫描在当前请求返回后才检查取消；本地扫描约按文件枚举检查。
6. **WebDAV NFO/认证海报缓存仍未做。**
7. **最近添加/继续观看排序、类型/分辨率筛选、防剧透未做。**
8. **真实 Jellyfin/OpenList、Infuse 对照、人工听测、多端仍未验证。**

## 下一项

手动合并/拆分与 TMDB 候选已在 [M3e 手动整理验收](M3E-MANUAL.md) 完成。剩余 M3f：WebDAV NFO/认证海报、最近添加/继续观看排序、筛选/防剧透、T07 扫描中播放/超时；完成后再进入 M4。
