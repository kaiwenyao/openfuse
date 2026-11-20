# M5p 验收记录：Jellyfin/Emby 版本级去重

日期：2026-11-20。分支：`m5p-version-dedupe`。基线：Infuse 8.5.10（参照客户端待装）。

M5g 只做到作品组去重，组内同分辨率版本仍会重复出现 Jellyfin/Emby 两条。本轮按 `mediaSourceID + 版本名 + 分辨率`（回退 remotePath/fileURL/id）合并版本，标签写成 `Jellyfin/Emby · ...`；真实不同分辨率版本仍保留。

## 交付内容

- `LibraryAggregation.versionIdentity`；合并时把新来源追加到标签（如 `Jellyfin/Emby`）。
- 版本标签不再重复；媒体库报告 `merged` 暴露合并后版本，验收脚本断言。
- 单元测试 `testVersionDedupeMergesJellyfinAndEmby`。
- 顺带修复 Emby 测试环境变量判断：`OPENFUSE_EMBY_*` 不再触发 Keychain 写/读提示。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 双来源组 | raw 4 作品/6 集 → **2 组**，sources 两者 |
| 合并版本 | `Emby/Jellyfin · 1080p HEVC 5.1` + `Emby/Jellyfin · 720p 压缩版` |
| 重复标签 | 无 |
| 脚本 | `Scripts/run-jellyfin-emby-dedupe.sh` PASS |
| 单测 | `testVersionDedupeMergesJellyfinAndEmby` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实服务器 | 待验证 |

证据：`Evidence/81-version-dedupe.jpg`、`reports/m5p-dedupe.json`、`reports/m5p-version-dedupe.txt`。

## 可复现差异与未验证

1. **真实 Emby/Jellyfin** 的 mediaSourceID 形态未验证；不同服务器若撞同一 mediaSourceID/名称可能误合并。
2. **版本顺序/首选版本**未按码率/大小排序。
3. **音频轨去重**未做；只合并播放版本。
4. **SMB 真实 SMB3/并发大文件、HDR/AirPlay 实机、CloudKit/Trakt、音频、M3 多根/损坏过滤**未做。

## 下一项

Trakt 已在 [M4q 验收](Docs/M4Q-TRAKT.md) 完成夹具验证。剩余 M5r：Trakt 真实账号/剧集/历史、音频听测、SMB3/并发、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤。
