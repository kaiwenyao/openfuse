# M5w 验收记录：HDR10 元数据

日期：2026-11-20。分支：`m5w-hdr-metadata`。基线：Infuse 8.5.10（参照客户端待装）。

生成 1080p10bit HDR10 样片（bt2020/smpte2084），ffprobe 识别 color transfer/primaries，写入版本 `dynamicRange` 与 SQLite，媒体库/详情显示 HDR10。实际 HDR 显示/色调映射仍未验证。

## 交付内容

- HDR10 生成脚本/验收 `Scripts/run-hdr-acceptance.sh`（缺失时 ffmpeg 生成）。
- `ScannedVersion.dynamicRange` / `LibraryVersion.dynamicRange`；SQLite `versions.dynamic_range` + ALTER 迁移。
- `MediaProbe.probeVideo`：ffprobe JSON 解析 height/color_transfer/color_primaries；`smpte2084+bt2020` → HDR10，`arib-std-b67` → HLG。
- 版本标签/库卡片显示 HDR；库报告序列化 dynamicRange。
- 修复 Trakt 初始化无条件读 Keychain 导致未配置用户弹授权：只有已保存 Client ID 或 env 时读。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 样片 | 1920×1080 Main10, bt2020nc/smpte2084/bt2020 |
| 扫描 | resolution=**1080p**，dynamicRange=**HDR10** |
| UI | 卡片显示「本地文件 · HDR10」 |
| 脚本 | `Scripts/run-hdr-acceptance.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 实际 HDR 输出 | 待验证 |

证据：`Evidence/87-hdr10.jpg`、`reports/m5w-hdr-library.json`、`reports/m5w-hdr.txt`。

## 可复现差异与未验证

1. **只验证元数据**，未验证 HDR 显示/色调映射/4K HDR 输出。
2. **WebDAV/Jellyfin HDR 元数据未解析**；仅本地 ffprobe。
3. **Dolby Vision/HDR10+** 未识别。
4. **音频回环仍被系统权限阻断**。
5. **真实 SMB3/大文件、Trakt 真实账号、AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

M5x：HDR 输出/tone mapping；WebDAV/Jellyfin HDR；音频听测；真实 SMB3/Trakt；AirPlay 实机；CloudKit；M3 多根/损坏过滤。
