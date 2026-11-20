# M5am 验收记录：SMB 大文件流式与 seek

日期：2026-11-20。分支 `m5am-samba-large`。基线 Infuse 8.5.10（参照客户端待装）。

本轮用 120s、约90MB 的 HEVC/E-AC-3 样片在真实 Samba 共享上验证大文件流式/seek，并采样进程内存确认没有整文件缓存。

## 交付内容

- `Scripts/run-samba-large.sh`：生成/复用 120s 90MB 样片、Samba 共享、扫描、seek60、RSS 断言、截图。
- 使用已有回环 Range/SMB pread 流式路径，无整文件缓存。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 样片 | 120s，1920×1080，HEVC/E-AC-3，~90MB |
| 扫描 | 1080p 版本 |
| 播放/seek | **62.04 / 120s** |
| URL | SMB 回环 `http://127.0.0.1:<port>/stream` |
| RSS | **≈100MB**（阈值 500MB） |
| 缓存 | 仅 SMBPosterCache/SMBSubtitleCache，无整文件 |
| 脚本 | `Scripts/run-samba-large.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 多 GB/并发/真实 NAS | 待验证 |

证据：`Evidence/102-samba-large.jpg`、`reports/m5am-samba-large-*`、`reports/m5am-samba-large.txt`。

## 可复现差异与未验证

1. **仅 90MB/120s**；多 GB 文件未测。
2. **并发 Range/背压**未压测。
3. **真实 NAS/Windows/SMB 多通道**未测。
4. **音频听测、HDR 测量、Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

M5an/M6d：SMB 多 GB/并发/DFS/域；音频听测；HDR 测量；真实 Trakt/CloudKit；visionOS 真机。
