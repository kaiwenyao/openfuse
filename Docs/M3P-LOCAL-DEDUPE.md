# M3p 验收记录：跨根本地文件级去重

日期：2026-11-20。分支：`m3p-local-dedupe`。基线：Infuse 8.5.10（参照客户端待装）。

M3o 后同一文件拷到两个根会出现两个版本。本轮为本地版本计算内容指纹（大小+首尾 64KB SHA-256），版本合并优先按 contentKey，跨根同内容只显示一个版本。

## 交付内容

- `ScannedVersion/LibraryVersion.contentKey`。
- SQLite `versions.content_key` + ALTER 迁移。
- `MediaProbe` 计算指纹（SHA-256，前缀 32 hex）；写入版本。
- `LibraryAggregation.versionIdentity` 优先 contentKey，其次 mediaSourceID/remotePath/fileURL/id。
- 验收脚本 `Scripts/run-local-dedupe.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 两个根 | rawWorks=2 |
| 合并组 | groups=1 |
| 合并版本 | **1**（`本地 · 本地文件`） |
| contentKey | `7289df19a59322bfc219bf09ec855bdc` |
| 脚本 | `Scripts/run-local-dedupe.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |

证据：`reports/m3p-local-dedupe.json`、`reports/m3p-local-dedupe.txt`。

## 可复现差异与未验证

1. **不是全文件哈希**；首尾相同但中段不同的文件可能误合并（概率低）。
2. **同内容不同标题仍分开**；只做版本级去重，不做作品级内容合并。
3. **SMB/WebDAV/Plex 未计算 contentKey**。
4. **音频听测、HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit**未做。

## 下一项

E-AC-3 5.1 PCM 解码已在 [M5z 验收](Docs/M5Z-AUDIO-PCM.md) 完成（未扬声器听测）。剩余 M5aa：真实听测/设备路由/downmix、SMB/WebDAV 指纹、HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit。
