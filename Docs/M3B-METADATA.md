# M3b 验收记录：TMDB、NFO 与远程海报

日期：2026-11-19。分支：`m3b-metadata`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮给 M3a 的媒体库补上元数据来源：TMDB 搜索、本地 NFO 优先级、TMDB 海报渲染，以及 WebDAV 扫描后的海报库。真实 TMDB key 没有提供，使用仓库内的 TMDB 协议夹具验证；真实 API 标为「待验证」。

## 交付内容

- **TMDB 客户端**：`/3/search/movie`、`/3/search/tv`，按标题与年份查询；读取 `title/name`、`overview`、`poster_path`、`release_date/first_air_date`；进程内缓存相同查询。
- **配置**：
  - `OPENFUSE_TMDB_API_KEY`：启用 TMDB；没有 key 时完全离线，保留文件名/Jellyfin 元数据。
  - `OPENFUSE_TMDB_BASE_URL`：默认 `https://api.themoviedb.org/3`，测试指向夹具。
  - `OPENFUSE_TMDB_IMAGE_BASE`：默认 `https://image.tmdb.org/t/p/w500`，测试指向夹具。
- **应用范围**：本地扫描与 WebDAV 扫描完成后，对非 Jellyfin 作品逐项查询；用 TMDB 标题、年份、简介、海报覆盖。Jellyfin 保留服务器元数据，不覆盖。
- **NFO**：本地读取 `movie.nfo`、`<video>.nfo`、`tvshow.nfo`、单集 NFO；解析 `title/year/plot/poster/thumb`，相对海报路径解析为本地文件；有完整 NFO 的作品跳过 TMDB（本地覆盖优先）。
- **海报引用**：`jellyfin:<itemID>|<tag>`、`file:<path>`、`remote:<https URL>`；UI 对文件用 `NSImage`，对远程 URL 用 AsyncImage。TMDB 海报因此可在本地/WebDAV 作品中显示。
- **夹具**：`Tools/tmdb_fixture.py` 模拟 TMDB movie/tv 搜索与海报；`Tools/make_library_fixture.py` 为「另一部剧」写入 `tvshow.nfo`，用于验证 NFO 优先级。
- **脚本**：`Scripts/test-tmdb.sh` 协议检查；`Scripts/run-tmdb-acceptance.sh` 本地 + WebDAV 扫描与截图。

## 数据流

```
LibraryScanner.scanLocal / scanWebDAV
    ├─ 本地：NFOReader (tvshow.nfo / movie.nfo / episode.nfo)
    ├─ 标题/年份/简介/海报
    └─ LibraryMetadata.enrich(TMDBClient)
          ├─ search movie/tv (title + year)
          ├─ 跳过 NFO 完整条目与 Jellyfin
          └─ poster → remote:<image URL>
LibraryStore.replace(source:)
LibraryView → LibraryPoster(file / remote / jellyfin)
```

## 复现

```bash
Scripts/test-tmdb.sh
Scripts/run-tmdb-acceptance.sh
```

手工：

```bash
python3 Tools/tmdb_fixture.py --port 8110
OPENFUSE_TMDB_API_KEY="$OPENFUSE_TMDB_API_KEY" \
OPENFUSE_TMDB_BASE_URL=http://127.0.0.1:8110/3 \
OPENFUSE_TMDB_IMAGE_BASE=http://127.0.0.1:8110 \
OPENFUSE_SUPPORT_DIR=/tmp/openfuse-tmdb \
build/OpenFuse.app/Contents/MacOS/OpenFuse --scan-local "$PWD/build/library-fixture"
```

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **22/22 通过**（新增 NFO 解析、PosterRef/mergeKey） | 终端 |
| `Scripts/test-tmdb.sh` | PASS：movie/tv 搜索、海报 URL、错误 key 无匹配 | 终端 |
| `Scripts/run-tmdb-acceptance.sh` | PASS：本地 3 作品，TMDB 2 匹配，NFO 1 覆盖；WebDAV 2 作品全部 TMDB 海报 | 终端 |
| 本地标题 | 《OpenFuse Fixture: TMDB Cut》《另一部剧 · 本地 NFO》《示例剧：TMDB 版》 | `reports/m3b-tmdb-local.json`、Evidence 25 |
| 海报 | TMDB 远程海报显示在本地作品；NFO 本地海报显示 | Evidence 25、28 |
| NFO 优先级 | 「另一部剧」标题/2025/本地简介/`poster.jpg` 来自 tvshow.nfo，未被 TMDB 覆盖 | Evidence 28 |
| WebDAV 海报库 | 扫描 WebDAV 后 2 个作品均使用 TMDB 海报 | Evidence 26、`reports/m3b-tmdb-webdav.json` |
| 详情 | TMDB 标题、简介、海报与播放按钮 | Evidence 27 |

端到端输出：

```
PASS: TMDB movie/TV enrichment, NFO precedence, WebDAV posters, local/remote UI
```

## 可复现差异与未验证

1. **真实 TMDB 未验证。** 没有 API key；夹具只覆盖搜索与海报，未覆盖限流、语言、成人内容过滤、网络错误与缓存失效。TMDB 要求署名，见 THIRD-PARTY。
2. **匹配规则简单。** 只按标题+年份取第一条结果；同名/重制/多语言标题可能误配；没有人工确认、候选列表或手动改 TMDB id。TMDB 改名会影响跨源合并键，当前用「去年份 + 去冒号副标题」的启发式避免本地/服务器重复卡片（实测本地 TMDB + Jellyfin 5 原始行合并为 3 组），仍可能误合并。
3. **NFO 只覆盖本地。** WebDAV 上的 NFO 未下载解析；Jellyfin 不读取本地 NFO；episode NFO 只读取同目录。
4. **没有增量与手工纠错。** 每次整源替换；扫描取消、断点恢复、改标题/海报/合并/拆分仍缺。
5. **跨源集级版本仍未合并。** 作品层合并 + 来源胶囊；同一集的多来源版本没有在同一集下列出。
6. **海报缓存/离线。** TMDB 海报依赖网络，未落盘缓存；WebDAV 自带海报仍需 Basic Auth，当前用 TMDB 覆盖或占位。
7. **没有 backdrop、演职员、预告片、评分源、语言/分级设置。**
8. **性能/限额。** 扫描时逐作品串行查询 TMDB，没有并发/取消/预算；大库会慢并可能触发限流。
9. **真实 OpenList/Jellyfin、Infuse 对照、人工听测与多端仍未验证。**

## 下一项

集级跨源版本合并已在 [M3c 版本合并验收](M3C-VERSIONS.md) 完成（电影 4 版本、剧集每集 2–3 版本）。剩余 M3d：TMDB 候选/手动匹配、WebDAV NFO/认证海报、增量扫描/取消、手工纠错、最近添加/继续观看排序、T07 压力；完成后再进入 M4。
