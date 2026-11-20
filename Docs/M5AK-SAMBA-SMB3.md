# M5ak 验收记录：真实 Samba SMB3

日期：2026-11-20。分支 `m5ak-samba-smb3`。基线 Infuse 8.5.10（参照客户端待装）。

此前 SMB 只用 impacket SMB2 夹具。本轮用 `dperson/samba` 4.13.7 Docker，OpenFuse 扫描/播放/seek/字幕真实 Samba 共享；同时修复 Samba 对根/子路径前导 `/` 的差异。

## 交付内容

- `Scripts/run-samba-smb3.sh`：起 Samba、共享 MKV/SRT、扫描/播放/seek/字幕断言。
- SMB 路径兼容：
  - list 根使用空路径（Samba 拒绝 `"/"` 的 CREATE）；
  - 子路径先试 `/Movie/file`，失败回退 `Movie/file`；
  - impacket 仍走绝对路径。
- 移除强制 `SMB2_VERSION_ANY3`/signing（会让 impacket 协商失败）；使用默认协商。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 服务 | Samba 4.13.7 Docker |
| 扫描 | 1 作品 `OpenFuse Samba`，1080p |
| 播放/seek | 11.0/60s |
| 字幕 | mpv:1 |
| 脚本 | `Scripts/run-samba-smb3.sh` PASS |
| impacket 回归 | `Scripts/run-smb-acceptance.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 签名/加密/DFS/大文件 | 待验证 |

证据：`Evidence/99-samba-smb3.jpg`、`reports/m5ak-samba-*.json`、`reports/m5ak-samba-smb3.txt`。

## 可复现差异与未验证

1. **Samba 默认配置**；强制签名/加密/DFS/域账号未测。
2. **大文件/并发/背压**未测。
3. **真实 NAS/Windows 共享**未测。
4. **音频听测、HDR 测量、Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

SMB3 签名/加密已在 [M5al 验收](Docs/M5AL-SAMBA-ENCRYPTED.md) 完成。剩余 M5am/M6d：DFS/域/大文件、音频听测、HDR 测量、真实 Trakt/CloudKit、visionOS 真机。
