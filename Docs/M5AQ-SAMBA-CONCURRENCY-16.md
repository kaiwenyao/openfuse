# M5aq 验收记录：16 并发 / 48 Range 压测

日期：2026-11-20。分支 `m5aq-samba-concurrency-16`。基线 Infuse 8.5.10（参照客户端待装）。

M5ap 修复背压后 8 并发通过。本轮把并发提高到 16，连续 3 批共 48 个 1MiB Range，同时在 2.4GB 文件上播放。

## 交付内容

- `Scripts/run-samba-concurrency-16.sh`：3×16 Range、播放、RSS/截图断言。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Range 请求 | **48/48 HTTP 206**，每个 1MiB |
| 并发 | 16/批，3 批 |
| 播放 | 1202/1800 继续 |
| RSS | 128MB → 112MB |
| 脚本 | `Scripts/run-samba-concurrency-16.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| >16/长稳/DFS | 待验证 |

证据：`Evidence/112-samba-concurrency16.jpg`、`reports/m5aq-samba-concurrency16-*`、`reports/m5aq-samba-ranges48.txt`、`reports/m5aq-samba-concurrency16.txt`。

## 可复现差异与未验证

1. **16 并发/48 请求**；更高并发、长时间 soak 未测。
2. **DFS/域/真实 NAS**未测。
3. **音频/HDR/CloudKit/visionOS 真机**未完成。

## 下一项

M5ar/M6d：>16/长稳/DFS；CA 导入 UI/同步并发/CloudKit；音频/HDR/visionOS。
