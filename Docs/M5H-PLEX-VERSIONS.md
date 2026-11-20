# M5h 验收记录：Plex 多版本保留与选择

日期：2026-11-20。分支：`m5h-plex-versions`。基线：Infuse 8.5.10（参照客户端待装）。

此前 Plex 扫描只取 `Media[0]`，会丢服务器版本。现在遍历全部 Media，每部电影/每集保留多个 ScannedVersion（分辨率/容器/part key）；媒体库详情版本菜单沿用；新增 CLI `--library-version N` 做版本选择验收。

## 交付内容

- `PlexLibraryScanner.makeVersions`：遍历 `Media[]`，生成 `v0...vN`，名称由分辨率/容器组成。
- 电影与剧集均使用全部版本；`episode.remotePath` 取首版。
- `playLibraryEpisode(id:versionIndex:)` + CLI `--library-version`；UI 版本菜单不变。
- 夹具每个条目增加 720p 备版（part `4012`），验收实际播放备版。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 版本扫描 | 电影 2 版；每集 2 版（1080p MKV / 720p MKV） |
| 版本选择 | `--library-version 1` 实际播放 remotePath `/library/parts/4012/file.mkv` |
| 画面 | 备版播放 9.9s 截图（Evidence 66） |
| 字幕/进度回归 | 仍选中 Plex 外挂简体；timeline/scrobble 断言通过 |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Plex | 待验证 |

证据：`Evidence/66-plex-alternate-version.jpg`、`reports/m5h-plex-library.json`、`reports/m5h-plex-version.json`、`reports/m5h-plex-versions.txt`。

## 可复现差异与未验证

1. **真实 Plex 版本顺序/标签**未验证；夹具名称人为统一。
2. **版本级跨来源去重未做**：Jellyfin/Emby 同分辨率版本仍可能重复。
3. **Plex 直连浏览/音轨选择**未做。
4. **Emby/SMB、HDR/AirPlay、CloudKit/Trakt、音频、M3 尾项**未做。

## 下一项

M5i：Plex 直连浏览/音轨；版本级去重；Emby/Jellyfin 真机；SMB/HDR/AirPlay；CloudKit/Trakt；音频；M3 尾项。
