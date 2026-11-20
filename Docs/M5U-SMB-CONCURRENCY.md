# M5u 验收记录：SMB 流并发与 SIGPIPE 健壮性

日期：2026-11-20。分支：`m5u-smb-concurrency`。基线：Infuse 8.5.10（参照客户端待装）。

SMB 回环 HTTP 服务器此前串行处理连接；拖动/多请求会被旧响应阻塞，且客户端中断可能触发 SIGPIPE。现在连接并发（上限 4）、socket 设 `SO_NOSIGPIPE`、accept 处理 EINTR/退避；两个并发 Range 请求均返回正确字节。

## 交付内容

- `connectionQueue` 改为 concurrent；`DispatchSemaphore(value: 4)` 限制并发。
- listener 与 accepted fd 设置 `SO_NOSIGPIPE`。
- accept 遇 EINTR 继续、其他错误退避 20ms。
- 验收脚本 `Scripts/run-smb-range-concurrency.sh`：两个 curl Range 与 fixture SHA-256 对比。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 并发 Range | 0..1MB 与 10MB..+1MB 同时请求 |
| 字节校验 | 两个 SHA-256 均与 fixture 对应片段一致 |
| SIGPIPE | socket 设置 SO_NOSIGPIPE；客户端中断不再可能杀进程 |
| 自动化 | `Scripts/run-smb-range-concurrency.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 SMB3/DFS/大文件 | 待验证 |

证据：`reports/m5u-smb-concurrency.txt`。

## 可复现差异与未验证

1. **真实 SMB3/DFS/签名/加密**未测；仅 impacket SMB2。
2. **并发上限 4**；更多连接直接关闭，无排队/背压/限速。
3. **SMBClient 读仍串行**；并发连接只是避免旧响应阻塞 accept/send。
4. **大文件/长时 seek**未压力测试。
5. **音频人工听测、HDR/AirPlay 实机、CloudKit 真实账号、M3 多根/损坏过滤**未做。

## 下一项

Trakt 自动轮询已在 [M5v 验收](Docs/M5V-TRAKT-AUTO-POLL.md) 完成。剩余 M5w：真实 Trakt/Keychain、音频听测、SMB3/大文件压力、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤。
