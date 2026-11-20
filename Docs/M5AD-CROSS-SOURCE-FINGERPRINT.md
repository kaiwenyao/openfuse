# M5ad 验收记录：本地/WebDAV/SMB 内容指纹去重

日期：2026-11-20。分支：`m5ad-remote-fingerprint`。基线：Infuse 8.5.10（参照客户端待装）。

M3p 只对本地版本生成 contentKey。本轮抽出共享 `ContentFingerprint`，WebDAV/SMB 扫描用 Range 读首尾 64KB 计算同一个键；同一文件出现在本地、WebDAV、SMB 时只显示一个版本。

## 交付内容

- `ContentFingerprint`：size+first/last 64KiB SHA-256，32 hex 前缀；`localKey` 修复 seekToEnd 后未回文件头。
- WebDAV scanner：两次 Range 读取，候选/版本写 contentKey。
- SMB scanner：两次 pread 读取，候选/版本写 contentKey。
- `versionIdentity` 对 contentKey 不再混入版本名，允许跨来源合并。
- 验收脚本 `Scripts/run-cross-source-dedupe.sh`（local+WebDAV+SMB）。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 组 | groups=**1** |
| sources | local + webdav + smb |
| 合并版本 | **1**：`本地/WebDAV/SMB · 本地文件 · HDR10` |
| contentKey | `3b02310a2a04f4eb68fc527b4312f56d`（三源一致） |
| 脚本 | `Scripts/run-cross-source-dedupe.sh` PASS |
| 本地去重回归 | PASS |
| `swift test` | **31/31 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 全文件哈希 | 待验证 |

证据：`reports/m5ad-cross-source-dedupe.json`、`reports/m5ad-cross-source-dedupe.txt`。

## 可复现差异与未验证

1. **首尾抽样不是全文件哈希**；中段变化可能误合并。
2. **SMB 扫描仍不探测 HDR/分辨率**（contentKey 有，元数据空）。
3. **远程读取成本**：每个视频额外 128KB；大库/慢网未压测。
4. **音频听测/设备热插拔、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList**未做。

## 下一项

M5ae：全文件/可配置哈希；SMB HDR 探测；远程指纹性能；听测/热插拔；HDR 测量；真实 SMB3/Trakt；CloudKit；真实 OpenList。
