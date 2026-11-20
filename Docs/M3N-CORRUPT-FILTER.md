# M3n 验收记录：本地损坏文件过滤

日期：2026-11-20。分支：`m3-corrupt-filter`。基线：Infuse 8.5.10（参照客户端待装）。

M3 只做到“损坏单个文件不中断扫描”，坏文件仍以占位作品入库。本轮 ffprobe 判定本地版本可播放性，移除损坏版本及空作品，扫描中播放用例仍通过。

## 交付内容

- `MediaProbe.probeVideo` 返回 height/dynamicRange/playable；ffprobe 失败或无视频流 → 不可播放。
- `enrichLocalResolutions` 过滤版本；空 movie/episode/season/work 逐级移除。
- 大小 ≤1KB 直接判损坏；**ffprobe 不存在时保留**（未知不等于损坏）。
- T07 脚本增加 Broken 标题断言，并加测试 token 避免 Trakt Keychain 阻塞。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 损坏文件 | `Broken.Movie.2026.mkv` 不在库 |
| 正常作品 | 3 个：OpenFuse Fixture、另一部剧、示例剧 |
| 扫描中播放 | 通过（position 12s 继续） |
| 自动化 | `Scripts/run-scan-while-playing.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |

证据：`reports/m3n-corrupt-filter.json`、`reports/m3n-corrupt-filter.txt`。

## 可复现差异与未验证

1. **ffprobe 瞬时失败可能误删**；无重试/缓存。
2. **仅本地 fileURL**；SMB/WebDAV 损坏文件仍可能入库。
3. **≤1KB 一律判损坏**；极短合法片段会被过滤。
4. **音频回环、HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit、M3 多根**未做。

## 下一项

多根本地库已在 [M3o 验收](Docs/M3O-LOCAL-ROOTS.md) 完成。剩余 M3p/M5z：跨根文件级去重、SMB/WebDAV 损坏过滤、音频听测、HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit。
