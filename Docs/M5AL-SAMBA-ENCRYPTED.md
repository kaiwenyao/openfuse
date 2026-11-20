# M5al 验收记录：Samba SMB3 签名与加密

日期：2026-11-20。分支 `m5al-samba-encrypted`。基线 Infuse 8.5.10（参照客户端待装）。

M5ak 验证了 Samba 默认配置。本轮强制 `server signing = mandatory`、`smb encrypt = required`、`server min protocol = SMB3`，OpenFuse 自动从普通协商回退到签名+加密连接，成功扫描/播放。

## 交付内容

- `SMBClient.connectedContext`：先普通连接；失败后新 context 设置
  `smb2_set_sign(1)` + `smb2_set_seal(1)` 重试，保留最后一次错误。
- `Scripts/run-samba-encrypted.sh`：启动强制签名/加密 Samba，扫描/播放，并在播放期间抓 `smbstatus` 断言 SMB3_11/AES-128-CCM/AES-128-CMAC。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 服务 | Samba 4.13.7，signing mandatory，encrypt required，min SMB3 |
| 协议 | **SMB3_11** |
| 加密 | **AES-128-CCM** |
| 签名 | **AES-128-CMAC** |
| 扫描 | 1 作品/1080p |
| 播放/seek | 11/60s |
| 脚本 | `Scripts/run-samba-encrypted.sh` PASS |
| impacket 回归 | PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| DFS/域账号/大文件 | 待验证 |

证据：`Evidence/100-samba-encrypted.jpg`、`reports/m5al-samba-encrypted-*`、`reports/m5al-samba-encrypted.txt`。

## 可复现差异与未验证

1. **DFS/域/Kerberos**未测。
2. **大文件/并发/背压**未测。
3. **真实 NAS/Windows 共享**未测。
4. **音频听测、HDR 测量、Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

M5am/M6d：DFS/域/大文件；音频听测；HDR 测量；真实 Trakt/CloudKit；visionOS 真机。
