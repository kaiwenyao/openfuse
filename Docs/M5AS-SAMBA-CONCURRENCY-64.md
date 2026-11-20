# M5as 验收记录：64 并发 Range

日期：2026-11-20。分支 `m5as-samba-concurrency-64`。基线 Infuse 8.5.10（参照客户端待装）。

M5ar 把 backlog 提到 128 并验证 32 并发。本轮不改产品代码，验证 64 个同时 Range 客户端在 4 活跃槽+128 backlog 下全部完成。

## 交付内容

- `Scripts/run-samba-concurrency-64.sh`：2.4GB 播放期间 64 并发 512KiB Range，断言 64/64、播放位置、RSS、截图。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 并发 Range | **64/64 HTTP 206**，每个 512KiB |
| 播放 | 1202/1800 继续 |
| RSS | 167MB → 158MB |
| 脚本 | `Scripts/run-samba-concurrency-64.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| >64/长稳/DFS | 待验证 |

证据：`Evidence/115-samba-concurrency64.jpg`、`reports/m5as-samba-*`、`reports/m5as-samba-concurrency64.txt`。

## 可复现差异与未验证

1. **64 并发**；更高并发、长时间 soak 未测。
2. **DFS/域/真实 NAS**未测。
3. **物理5.1/人耳/HDMI、HDR测量、CloudKit、visionOS**未完成。

## 下一项

同步设置 UI 已在 [M6f 验收](Docs/M6F-SYNC-SETTINGS.md) 完成。剩余 M6g/M5at：物理5.1/HDMI、HDR测量、>64/长稳/DFS、CloudKit/visionOS。
