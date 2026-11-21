# Jellyfin macOS 网格与详情页（0.6.1）

参考图：`Docs/References/Jellyfin-macOS/01-library-overlap.png`、`02-episode-overlap.png`、`03-series-information.png`、`04-media-specs.png`。修复后截图：`build/jellyfin-macos/`。

## 1. 网格

`JellyfinBrowserView.card` 的图片容器现在由网格单元决定宽度，并按条目类型固定比例：

| 条目 | 比例 |
| --- | --- |
| CollectionFolder / UserView / Folder | 16:9 |
| Episode | 16:9 |
| Movie / Series / Season | 2:3 |

- `AsyncImage` 成功时 `scaledToFill` + 固定比例容器 + `clipped()`，不再用自身 intrinsic size 撑开列；加载中、失败、无图、选中覆盖层共用同一容器。
- 标题/副标题 `frame(maxWidth:.infinity, alignment:.leading)`，长标题两行截断；卡片 Button 的可点区域与列内卡片一致。
- `UserView` 的副标题改为“文件夹”（按 collectionType 显示电影库/电视剧库），不再显示原始类型。
- 真实窗口：1180 宽（`grid/ui.png`）与 980 宽（`grid-narrow/ui.png`）均无跨列；AX hit test 显示卡片之间为 `AXOpaqueProviderGroup`，两侧才是 `AXButton`（`ax-grid/hit-test.txt`）。

## 2. 窗口内详情

- 可播放条目（Episode/Movie）不再弹 640 pt sheet，而是在 `JellyfinBrowserView` 主内容区显示 `JellyfinDetailPage`；Series/Season 仍保持下钻浏览。
- Hero：优先使用作品/父剧集 Backdrop；缺横幅时主题底色 + 海报。`ViewThatFits` 在宽度 ≥1000 时用横幅叠加文字，窄窗改为图在上、文字在下。
- 标题、年份/首播日期、时长、分级、类型、简介、播放/继续观看集中在 Hero；`播放`才调用 `openJellyfinItem`，选集只更新页面。
- 电视剧：季选择 + 横向分集列表（16:9 剧照、集号、标题、观看进度、当前选中边框）。从单集进入会定位到正确季集；切换季/集更新标题、剧情、评分、演职员、播放目标和参数。
- 选择状态存入 `AppModel.jellyfinDetailSelections`（按来源），退出播放器后 `JellyfinBrowserView` 重新读取，恢复到之前的季/集并滚动到分集区。
- 窄窗/全屏截图：`grid-narrow/ui.png`、`e2-fullscreen/ui.png`；E2 点击后 `e2-click/ui.png`。

## 3. 评分与演职员

- 社区评分：`社区评分 8.2/10`；影评人：`影评人 93%`；整剧回退时前缀 `整剧 ·`。
- 外部评分复用 OMDb：`本剧 · IMDb 9.0/10`、`本剧 · 烂番茄 95%`、`本剧 · Metacritic 85/100`（通过 ProviderIds.Imdb 关联，只发送公共 ID）。
- 演职员来自 Jellyfin People：头像、姓名、角色；Type Actor → “演员 · 角色”，Director → “导演”；单集无 People 时回退整剧并标“本剧演职员”。无数据整段省略。

## 4. 技术参数

`JellyfinMediaSummary`（Data）从当前所选 `JellyfinMediaSource` 读取：

- 摘要顺序：文件大小、视频编码、分辨率、音频编码+声道/布局、总码率、帧率。示例实测：`957.9 MB · HEVC · 1920×1080 · AAC 5.1 · 1.7 Mbps · 23.976 fps`。
- “媒体信息”展开：容器、视频 profile、位深、HDR/SDR、视频流码率、总码率、音轨语言、字幕格式。总码率与视频流码率分开；未知字段省略。
- 帧率保留 24000/1001 → `23.976`；大小/码率使用十进制单位；未知不显示 “—”。
- 版本 Picker 切换后 `selectedSourceID` 同时决定摘要与实际播放的 `MediaSourceId`；`openJellyfinItem` 使用该 ID。
- 快速切集/切版本用 `selectionToken` 校验迟到响应，旧 item/source 不会写回。

## 5. 验收

`Scripts/run-jellyfin-macos.sh` + `Scripts/jellyfin_fixture.py`：

- fixture 提供三个媒体库、Fargo S1E1–E5、Inception 1080p/2160p、无图样片、People、社区/影评人评分、OMDb 评分与完整 MediaStreams。
- 断言：E1→E2 选集、播放目标 E2、摘要 957.9 MB/23.976 fps、评分/演员/导演、2160p 4.5 GB/3840×2160/24 fps、缺图缺评分省略、窄窗 980、全屏 1512、AX 点击打开电影库、间距命中不是按钮。
- 真实点击通过 `Tools/ax_press.swift` 的 accessibility `AXPress` 完成；CGEvent 左键注入在该环境不会驱动 SwiftUI Button，因此没有把它当作通过依据。

## 6. 边界

- 没有真实 Jellyfin 服务器；验收使用本地 fixture（相同 API 字段）。
- 分段 Picker 的 AXPress 未改变版本选择，2160p 验收用 seed `--jellyfin-media`；人类点击 Picker 走 SwiftUI 绑定。
- 退出播放器恢复滚动位置为“分集区居中”的近似，不是像素级 offset。
- 缺单集剧照时详情页 Hero 回退整剧 Backdrop/主题底色；分集卡片仍显示占位图标（未回退剧照）。
