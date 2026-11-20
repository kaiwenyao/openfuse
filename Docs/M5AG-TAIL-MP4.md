# M5ag 验收记录：尾部 moov/HDR colr MP4 over SMB

日期：2026-11-20。分支：`m5af-smb-mp4` 后续（M5ag）。基线：Infuse 8.5.10（参照客户端待装）。

M5af 只测了 moov 在前的 SDR MP4，且 SMB `pread` 可能短读。本轮生成 20s HDR10 MP4（moov 在尾、colr/nclx），修复 MP4Probe 跳过 stsd/sample entry 头，SMB 读改为 1MB 分块循环；头 4MB 不足时尾回退成功解析 1080p/HDR10。

## 交付内容

- MP4Probe：`stsd` 跳 8B，视觉 sample entry 跳 78B 后递归，正确读取 colr/nclx。
- SMBClient.read：1MB 分块 pread 循环直到请求长度/EOF，处理短读。
- HDR MP4 fixture（tail moov, colr 9/16）。
- 单测 tail HDR；验收 `Scripts/run-smb-hdr-mp4.sh`；SMB Range 回归补测试 token。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 版本 | `1080p · SMB` |
| resolution | **1080p** |
| dynamicRange | **HDR10** |
| 单测 | MP4ProbeTests 2 项，总 **33/33** |
| 脚本 | `run-smb-hdr-mp4.sh` PASS；`run-smb-range-concurrency.sh` 回归 PASS |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| moov >8MB 尾部/碎片 MP4 | 待验证 |

证据：`reports/m5ag-smb-hdr-mp4.json`、`reports/m5ag-smb-hdr-mp4.txt`。

## 可复现差异与未验证

1. **moov 不在最后 8MB** 或尾数据从 mdat 中间开始时仍会失败；未做 moov 扫描定位。
2. **碎片化 MP4（moof）**未支持。
3. **真实 SMB3/大库性能**未测。
4. **音频听测/热插拔、HDR 测量、真实 Trakt/CloudKit/OpenList**未做。

## 下一项

大 MP4 尾部 moov 扫描已在 [M5ah 验收](Docs/M5AH-MOOV-SCAN.md) 完成。剩余 M5ai：碎片 MP4/大 moov、SMB 性能、听测/热插拔、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList。
