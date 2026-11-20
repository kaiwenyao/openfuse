# M5ae 验收记录：SMB MKV 分辨率/HDR

日期：2026-11-20。分支：`m5ae-smb-hdr`。基线：Infuse 8.5.10（参照客户端待装）。

M5ad 让 SMB 有 contentKey，但版本仍无分辨率/HDR。本轮 SMB 扫描读取前 2MB，用现有 `MatroskaProbe` 解析 PixelHeight/Colour，写入版本。

## 交付内容

- SMB scanner `matroskaInfo(entry)`：`client.read` 0..2MB（受文件大小限制）。
- FileCandidate 写 resolution/dynamicRange；版本名变为 `1080p · SMB`。
- 验收脚本 `Scripts/run-smb-hdr.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 版本 | `1080p · SMB` |
| resolution | **1080p** |
| dynamicRange | **HDR10** |
| contentKey | `3b02310a2a04f4eb68fc527b4312f56d` |
| 脚本 | `Scripts/run-smb-hdr.sh` PASS |
| `swift test` | **31/31 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |

证据：`reports/m5ae-smb-hdr.json`、`reports/m5ae-smb-hdr.txt`。

## 可复现差异与未验证

1. **只读前 2MB**；Tracks 更靠后的 MKV 无元数据。
2. **MP4/其他容器 SMB 未探测**。
3. **真实 SMB3/DFS/大库性能**未测；每个视频额外 2MB 读取。
4. **音频听测/热插拔、HDR 测量、真实 Trakt、CloudKit、真实 OpenList**未做。

## 下一项

M5af：SMB MP4/大头部/性能；全文件哈希；听测/热插拔；HDR 测量；真实 SMB3/Trakt；CloudKit；真实 OpenList。
