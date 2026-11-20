# M3h 验收记录：观看状态、继续观看排序、防剧透与画质筛选

日期：2026-11-20。分支：`m3h-watch`（基于 M4a 提交）。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮补 Mac 媒体库最后一批组织操作：用 `PlaybackStore` 计算观看状态，按最近播放排序，按未看/观看中/已看与 4K/1080p/720p 筛选；防剧透开启时隐藏简介与单集简介。

## 交付内容

- **观看状态**：`AppModel.watchState(for:)` 按季/集合并组内来源，匹配本地路径、`webdav://source/path`、`jellyfin://source/item/mediaSource` 的播放记录；全部看完 → 已看，任一条目有进度 → 观看中，否则未看。
- **最近播放排序**：`LibrarySort.recentlyPlayed`，按组内最大 `lastPlayedAt` 降序；未播放排后。
- **观看状态筛选**：全部/未看/观看中/已看。
- **画质筛选**：全部/4K/1080p/720p；从版本 `resolution` 或名称（1080p/720p/4K/2160）解析。Jellyfin 电影 MediaSource 现在写入高度；单集/本地/WebDAV 没有可靠分辨率时不计入具体画质筛选（会出现在「全部」）。
- **防剧透**：`@AppStorage("openfuse.spoilerProtection")`；开启且未看完时，详情简介显示「简介已隐藏（防剧透）＋显示」，单集简介显示「防剧透已开启」；点「显示」临时展开本页。
- **合并键**：规范化标题增加 `·` 分隔符，使 WebDAV NFO 标题《示例剧 · WebDAV NFO》与 Jellyfin/本地《示例剧》正确合并（避免 5 组重复）。
- **验收**：`Scripts/run-library-acceptance.sh` 扩展观看状态/最近播放/画质/防剧透断言与截图。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | **25/25 通过**（新增中点标题合并键） | 终端 |
| 完整库验收 | **PASS**：7 作品/9 集、3 组合并、搜索、播放、观看状态/最近播放/画质/防剧透 | 终端 |
| 观看中筛选 | `visible = ["示例剧"]`（本地 S01E01 记录 9.917s） | `reports/m3h-watch-in-progress.json` |
| 最近播放排序 | `visible = ["示例剧", "OpenFuse Fixture (2026)", "另一部剧 · 本地 NFO"]` | `reports/m3h-watch-recent.json` |
| 1080p 筛选 | `visible = ["OpenFuse Fixture (2026)"]`（Jellyfin 电影版本有分辨率；剧集/本地无） | `reports/m3h-watch-resolution.json` |
| 防剧透 | 详情/单集简介隐藏，点「显示」展开；截图见 Evidence 37 | Evidence 37 |

脚本输出：

```
PASS: local/Jellyfin/WebDAV scan, 7 works/9 episodes, search, details, library playback, watch/recent/resolution filters, spoiler UI
```

## 可复现差异与未验证

1. **画质元数据不完整。** 只有 Jellyfin 电影 MediaSource 有高度；Jellyfin 单集、本地、WebDAV 版本无分辨率，选中 4K/1080p/720p 时会被排除。需要探测媒体或读取 NFO/MediaInfo。
2. **观看状态依赖播放记录键。** 本地路径、WebDAV/Jellyfin 伪键匹配已验证；手动改标题/合并后仍按文件/集匹配，不按展示标题。
3. **「最近播放」不是独立首页栏。** 只作为媒体库排序；首页「继续观看」仍用 `PlaybackStore.recentlyPlayed`，未按组聚合。
4. **防剧透是整页开关。** 不按单集已看状态逐条隐藏，也没有缩略图模糊；本页「显示」一次展开所有。
5. **T07 深入未做**：扫描中播放、目录超时恢复、重启后新增字幕只更新目标条目。
6. **真实 OpenList/Jellyfin、Infuse 对照、人工听测、移动端运行**仍未验证。

## 下一项

M4b：完成 iOS 模拟器 runtime 启动/截图；移动端 Jellyfin/WebDAV、MKV/libmpv、iPad 分栏、tvOS/visionOS、CloudKit/Trakt。M3 仅剩 T07 深入与画质元数据补全。
