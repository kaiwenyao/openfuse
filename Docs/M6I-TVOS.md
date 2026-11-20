# M6i 验收记录：tvOS 实际播放

日期：2026-11-20。分支 `m6i-tvos`。基线 Infuse 8.5.10（参照客户端待装）。

tvOS 已有海报网格与 TVPlayerView，但 autoplay 测试钩子在 groups 未加载时直接返回。本轮修复等待/重试，并在 Apple TV 模拟器实际出画。

## 交付内容

- `TVRootView` autoplay：轮询最多 5s 等 groups/playbackItem 就绪。
- `Scripts/run-tvos-playback.sh`：构建/安装/启动 tvOS app，autoplay 样片，截图并校验非白屏。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 库页面 | 单张样片海报网格 |
| 播放 | 1.79s/19s，HEVC Main10/E-AC-3 |
| 控制栏 | 字幕/音轨按钮可见 |
| 截图 | YAVG 47.8，1.03MB |
| 脚本 | `Scripts/run-tvos-playback.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 遥控导航/真实 Apple TV | 待验证 |

证据：`Evidence/120-tvos-library.png/.jpg`、`121-tvos-playback.png/.jpg`、`reports/m6i-tvos-*`。

## 可复现差异与未验证

1. **遥控器导航/点击播放**未自动化。
2. **tvOS 远程来源/同步/字幕设置**未做；仅 bundled sample。
3. **单海报布局大片留白**，未与 Infuse 对照。
4. **真实 Apple TV/音频听测**未完成。
5. **物理5.1/HDMI、HDR、CloudKit、visionOS**未完成。

## 下一项

M6j/M5au：tvOS 遥控导航/远程来源；物理5.1/HDMI；HDR测量；小时级/DFS；CloudKit/visionOS。
