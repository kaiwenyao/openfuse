# M5ar 验收记录：32 并发 Range / backlog 修复

日期：2026-11-20。分支 `m5ar-samba-concurrency-32`。基线 Infuse 8.5.10（参照客户端待装）。

M5aq 验证 16 并发。32 并发初测只成功 21/32，11 个连接被拒绝；原因是 listen backlog=16，而 accept 受 4 槽背压限制。

## 根因与修复

- `listen(fd, 16)`：16 backlog + 4 active 仅约20个可排队。
- 修复 `listen(fd, 128)`；accept 循环仍先取信号量，连接在内核 backlog 排队。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 32 并发 Range | **32/32 HTTP 206**，每个 1MiB |
| 播放 | 1200/1800 继续 |
| RSS | 211MB → 211MB |
| 脚本 | `Scripts/run-samba-concurrency-32.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| >32/长稳/DFS | 待验证 |

证据：`Evidence/114-samba-concurrency32.jpg`、`reports/m5ar-samba-*`、`reports/m5ar-samba-concurrency32.txt`。

## 可复现差异与未验证

1. **32 并发**；更高并发、长稳未测。
2. **DFS/域/真实 NAS**未测。
3. **物理5.1/人耳/HDMI、HDR测量、CloudKit、visionOS 真机**未完成。

## 下一项

M5as/M6f：>32/长稳/DFS；物理5.1/HDMI；HDR测量；CloudKit；visionOS。
