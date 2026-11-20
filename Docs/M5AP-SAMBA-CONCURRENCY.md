# M5ap 验收记录：SMB 回环 Range 并发/背压

日期：2026-11-20。分支 `m5ap-samba-concurrency`。基线 Infuse 8.5.10（参照客户端待装）。

本轮在 2.4GB Samba 文件播放期间发起 8 个并发 Range 请求。初测仅 3/8 成功，5 个连接被服务器直接重置。

## 根因与修复

- `SMBStreamServer.acceptLoop` 在 4 个连接槽满时 **accept 后立即 close**，没有 HTTP 响应。
- 修复：先 `connectionLimit.wait()` 再 `accept`，超出并发的客户端在内核 backlog 排队；连接处理结束再 signal。
- 形成背压而不是 reset，播放与并发 Range 可共存。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 并发 Range | **8/8 HTTP 206**，每个 1MiB |
| 播放 | 1202/1800 继续 |
| 脚本 | `Scripts/run-samba-concurrency.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| >8 客户端/长稳/DFS | 待验证 |

证据：`Evidence/111-samba-concurrency.jpg`、`reports/m5ap-samba-concurrency-*`、`reports/m5ap-samba-ranges.txt`、`reports/m5ap-samba-concurrency.txt`。

## 可复现差异与未验证

1. **8 客户端**；更高并发/长稳未压测。
2. **背压期间客户端等待时间**未测。
3. **DFS/域/真实 NAS**未测。
4. **音频/HDR/CloudKit/visionOS 真机**未完成。

## 下一项

M5aq/M6d：>8 并发/长稳/DFS；音频/HDR/visionOS；CloudKit 真机。
