# M5i 验收记录：Plex 直连浏览

日期：2026-11-20。分支：`m5i-plex-browser`。基线：Infuse 8.5.10（参照客户端待装）。

Plex 不再只有扫描后的海报库：新增 Plex Direct 浏览，按 section → 电影/剧 → 季 → 集导航，条目可进入详情并播放；复用现有 token、海报、外挂字幕与 libmpv 播放链路。

## 交付内容

- `AppRoute.plexBrowser`、`browsePlex`、`plexClient`、`openPlexMetadata`。
- `PlexBrowserView`：NavigationStack；section 卡片；section 条目网格；metadata 详情；show/season children；movie/episode 播放按钮。
- token 动态海报；`OPENFUSE_PLEX_SECTION` 测试钩子自动进入 section。
- Home Plex 来源卡新增「浏览」；CLI `--plex-browse`。
- 验收 `Scripts/run-plex-browser.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Sections | `Plex Direct` 显示 Plex 电影 / Plex 电视剧 |
| Section 条目 | 自动进入电影 section，显示电影网格/海报/年份 |
| 数据请求 | `/library/sections`、`/library/sections/1/all` 带 token |
| 播放链路 | 详情播放按钮调用 `openPlexMetadata`（与库播放同一路径，库播放已验证 9.9s） |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Plex | 待验证 |

证据：`Evidence/67-plex-browser-sections.jpg`、`68-plex-browser-movies.jpg`、`reports/m5i-plex-browser.jsonl`、`reports/m5i-plex-browser.txt`。

## 可复现差异与未验证

1. **详情/播放点击未自动化**：只自动进入 section；播放按钮代码复用已验收的库播放路径。
2. **真实 Plex** section 类型/children 形态/分页未验证；夹具无分页。
3. **Plex 音轨选择/版本切换**在浏览详情未展示；版本播放已有 CLI 验收。
4. **版本级跨来源去重**未做。
5. **SMB/HDR/AirPlay、CloudKit/Trakt、音频、M3 尾项**未做。

## 下一项

T07 扫描中播放已在 [M3l 验收](Docs/M3L-T07.md) 完成。剩余 M5j/M3m：Plex 详情点击/音轨、版本级去重、真实服务器、SMB/HDR/AirPlay、CloudKit/Trakt、音频、多根本地库/损坏过滤/WebDAV MKV 分辨率。
