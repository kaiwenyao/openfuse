# M5an 验收记录：>1GB SMB 流式与远距离 seek

日期：2026-11-20。分支 `m5an-samba-multigb`。基线 Infuse 8.5.10（参照客户端待装）。

M5am 验证了 90MB。本轮生成 1200s、720p HEVC/E-AC-3、**1.4GB** 样片，Samba 共享，OpenFuse 扫描、seek 900s，采样内存确认无整文件缓存。

## 交付内容

- `Scripts/run-samba-multigb.sh`：生成/复用 1.4GB 样片、Samba、扫描、seek900、RSS/截图断言。
- 覆盖 Int64 偏移、SMB pread 循环、回环 HTTP Range 长距离 seek。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 样片 | 1200s，1280×720，HEVC/E-AC-3，**1.4GB** |
| 扫描 | 720p 版本 |
| 播放/seek | **902.04 / 1200s** |
| URL | SMB 回环 |
| RSS | **≈154MB**（阈值600MB） |
| 缓存 | 无整文件缓存 |
| 脚本 | `Scripts/run-samba-multigb.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| >2GB/并发/DFS/域 | 待验证 |

证据：`Evidence/108-samba-multigb.jpg`、`reports/m5an-samba-multigb-*`、`reports/m5an-samba-multigb.txt`。

## 可复现差异与未验证

1. **1.4GB/20min**；>2GB/4GB 边界未测。
2. **并发 Range/背压**未压测。
3. **DFS/域/Kerberos/真实 NAS**未测。
4. **音频听测、HDR 测量、Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

M5ao/M6d：>2GB/并发/DFS；音频/HDR/visionOS；同步 HTTPS/CloudKit 真机。
