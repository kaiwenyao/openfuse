# M5ah 验收记录：大 MP4 尾部 moov 扫描

日期：2026-11-20。分支：`m5ah-moov-scan`。基线：Infuse 8.5.10（参照客户端待装）。

M5ag 的尾部回退假设尾数据从 atom 边界开始；>8MB 文件的尾 8MB 往往从 mdat 中间开始。现在 MP4Probe 在头部解析失败后扫描 `moov` 签名，从 size 字段重新解析；12.6MB tail-moov HDR MP4 over SMB 验证通过。

## 交付内容

- MP4Probe `moov` 签名扫描（避免 mdat 中间开始）。
- 单元测试：1MB 任意前缀 + moov atom。
- 大 HDR MP4 fixture 生成/验收 `Scripts/run-smb-large-mp4.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 单元测试 | 前缀+moov → 1080p/HDR10 |
| SMB 12.6MB MP4 | 头4MB无 moov；尾8MB中段；扫描成功 |
| 版本 | `1080p · SMB` |
| dynamicRange | **HDR10** |
| contentKey | 存在 |
| 脚本 | `Scripts/run-smb-large-mp4.sh` PASS |
| `swift test` | **34/34 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 碎片 MP4/moov >8MB | 待验证 |

证据：`reports/m5ah-smb-large-mp4.json`、`reports/m5ah-smb-large-mp4.txt`。

## 可复现差异与未验证

1. **moov 大于 8MB 或完全在前 4MB 之外且不在尾 8MB** 仍可能失败。
2. **碎片化 MP4（moof）**未解析。
3. **真实 SMB3/大库性能**未测。
4. **音频听测/热插拔、HDR 测量、真实 Trakt/CloudKit/OpenList**未做。

## 下一项

visionOS 沉浸空间已在 [M6a 验收](Docs/M6A-VISION-IMMERSIVE.md) 完成模拟器验证。剩余 M6b：真机 VideoMaterial/手势/空间音频、音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList。
