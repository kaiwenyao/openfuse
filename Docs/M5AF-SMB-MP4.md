# M5af 验收记录：SMB MP4 元数据

日期：2026-11-20。分支：`m5af-smb-mp4`。基线：Infuse 8.5.10（参照客户端待装）。

M5ae 只解析 SMB MKV。本轮加纯 Swift `MP4Probe`（moov/tkhd/colr），SMB 扫描 MP4/MOV/M4V 时读头 4MB，必要时读尾 8MB，得到分辨率与 HDR 标签。

## 交付内容

- `MP4Probe`：ISO-BMFF atom 遍历；tkhd 16.16 宽高；colr/nclx transfer/primaries。
- SMB scanner `videoInfo` 同时处理 MKV（2MB）与 MP4（4MB head + 8MB tail）。
- 单元测试 `MP4ProbeTests`；验收脚本 `Scripts/run-smb-mp4.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 版本 | `1080p · SMB` |
| resolution | **1080p** |
| contentKey | `9f999c7471948cc928d58046c3e688d0` |
| 单测 | MP4ProbeTests 通过，总 **32/32** |
| 脚本 | `Scripts/run-smb-mp4.sh` PASS |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |

证据：`reports/m5af-smb-mp4.json`、`reports/m5af-smb-mp4.txt`。

## 可复现差异与未验证

1. **MP4 moov 完全在尾部/碎片化 MP4** 未真实采样；仅做了头尾回退。
2. **HDR colr 样本**未验证；mobile MP4 为 SDR。
3. **真实 SMB3/大库性能**未测。
4. **音频听测/热插拔、HDR 测量、真实 Trakt、CloudKit、真实 OpenList**未做。

## 下一项

M5ag：尾部/碎片 MP4、HDR colr、SMB 性能；听测/热插拔；HDR 测量；真实 SMB3/Trakt；CloudKit；真实 OpenList。
