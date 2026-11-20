# M3f 验收记录：WebDAV NFO 与认证海报缓存

日期：2026-11-20。分支：`m3f-webdav`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮补齐 WebDAV 来源的本地元数据：下载并解析远程 `movie.nfo`/`tvshow.nfo`/单集 NFO，按 Basic Auth 拉取海报并缓存到本地，使 OpenList/WebDAV 海报库不再依赖 TMDB 或占位图。

## 交付内容

- **远程 NFO**：WebDAV 扫描时对目录中的 `.nfo` 发起带凭据 GET，解析 `title/year/plot/poster/thumb`；`movie.nfo` 作用于目录电影，`tvshow.nfo` 作用于剧集，`<video>.nfo` 作用于单集。
- **海报缓存**：优先 NFO 海报，其次同目录/剧集目录 `poster.jpg`/`folder.jpg`/`cover.jpg`；用 WebDAV Basic Auth 下载到 `Application Support/OpenFuse/PosterCache/`，库中记录 `file:<cache>`；失败才回退 `remote:<url>`。
- **NFO 优先**：NFO 提供标题/简介/海报后，TMDB 不再覆盖该作品（沿用 M3b 的完整 NFO 跳过规则）。
- **夹具**：WebDAV fixture 加入 `movie.nfo`、`tvshow.nfo`、单集 NFO 与海报；扫描时生成海报缓存。
- **验收脚本**：`Scripts/run-webdav-metadata.sh` 启动 WebDAV 夹具、扫描、检查标题/简介/单集标题/缓存文件/UI 截图。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **25/25 通过**（新增远程 NFO posterReference 解析） | 终端 |
| WebDAV 标题 | 《OpenFuse Fixture · WebDAV NFO》《示例剧 · WebDAV NFO》 | `reports/m3f-webdav-nfo.json`、Evidence 34 |
| 简介 | 电影/剧集简介来自 movie.nfo/tvshow.nfo | 同上 |
| 单集 | S01E01 标题「第 1 集 · WebDAV NFO」，简介来自单集 NFO | Evidence 35 |
| 海报 | 两作品均使用本地缓存 `file:.../PosterCache/...jpg`，文件存在 | 脚本断言、Evidence 34 |
| UI | 海报网格与详情正常 | Evidence 34–35 |

脚本输出：

```
PASS: WebDAV NFO titles/overview/episode title, authenticated posters cached
```

## 可复现差异与未验证

1. **真实 OpenList/百度网盘未验证。** 仅本地 WebDAV 夹具；真实服务的 NFO 编码、大小写、重定向、限流未测。
2. **NFO 只取常见字段。** 不解析演职员、剧集号、TMDB id、多语言标题；episode NFO 的 season/episode 仍以文件名为准。
3. **海报缓存无失效策略。** 以远程路径哈希命名，未按 ETag/mtime 更新；删除来源不清缓存。
4. **远程 NFO 下载是串行 GET**，大目录可能慢；受取消 token 控制。
5. **最近添加/继续观看排序、筛选、防剧透未做。**
6. **T07 深入未做**：扫描中播放、目录超时恢复、重启后只更新目标条目。
7. **真实 Jellyfin、TMDB 候选、Infuse 对照、人工听测、多端**仍未验证。

## 下一项

M3g：最近添加/继续观看排序、类型/分辨率/观看状态筛选、防剧透、T07 扫描中播放/超时恢复；完成后进入 M4 家庭设备与状态同步。
