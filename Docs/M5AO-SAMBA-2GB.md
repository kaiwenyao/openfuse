# M5ao 验收记录：>2GB SMB 流式与 seek

日期：2026-11-20。分支 `m5ao-samba-2gb`。基线 Infuse 8.5.10（参照客户端待装）。

M5an 验证 1.4GB。本轮生成 1800s、720p、**2.4GB** HEVC/E-AC-3 样片，Samba 共享，OpenFuse seek 1200s，RSS 采样确认无整文件缓存。

## 交付内容

- `Scripts/run-samba-2gb.sh`：生成/复用 2.4GB 样片、Samba、扫描、seek1200、RSS/截图断言。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 样片 | 1800s，1280×720，**2.4GB** |
| 扫描 | 720p |
| 播放/seek | **1202.13 / 1800s** |
| RSS | **≈113MB**（阈值700MB） |
| 缓存 | 无整文件缓存 |
| 脚本 | `Scripts/run-samba-2gb.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| >4GB/并发/DFS/域 | 待验证 |

证据：`Evidence/110-samba-2gb.jpg`、`reports/m5ao-samba-2gb-*`、`reports/m5ao-samba-2gb.txt`。

## 可复现差异与未验证

1. **2.4GB/30min**；>4GB 边界未测。
2. **并发 Range/背压**未压测。
3. **DFS/域/Kerberos/真实 NAS**未测。
4. **音频听测、HDR 测量、Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

M5ap/M6d：>4GB/并发/DFS；音频/HDR/visionOS；CloudKit 真机。
