# M5at 验收记录：SMB 播放 + 周期并发长稳

日期：2026-11-20。分支 `m5at-samba-soak`。基线 Infuse 8.5.10（参照客户端待装）。

M5ar/M5as 验证瞬时并发。本轮在 2.4GB 文件播放期间每 10 秒发 8 个 Range，持续 12 轮（约 2 分钟），观察播放、请求成功与 RSS。

## 交付内容

- `Scripts/run-samba-soak.sh`：播放从 600s 起，12×8 Range，断言全部 206、播放位置、RSS、截图。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Range | **96/96 HTTP 206**，每个 512KiB |
| 持续时间 | 12 轮 × 10s |
| 播放 | 继续（report ≥600s） |
| RSS | 188MB → 83MB |
| 脚本 | `Scripts/run-samba-soak.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 小时级/DFS | 待验证 |

证据：`Evidence/117-samba-soak.jpg`、`reports/m5at-samba-soak-*`、`reports/m5at-samba-ranges96.txt`、`reports/m5at-samba-soak.txt`。

## 可复现差异与未验证

1. **约2分钟**；小时级 soak 未测。
2. **DFS/域/真实 NAS**未测。
3. **物理5.1/人耳/HDMI、HDR测量、CloudKit、visionOS**未完成。

## 下一项

M5au/M6g：小时级/DFS；物理5.1/HDMI；HDR测量；CloudKit/visionOS。
