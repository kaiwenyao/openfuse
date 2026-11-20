# M6h 验收记录：iPad 常规宽度布局

日期：2026-11-20。分支 `m6h-ipad-layout`。基线 Infuse 8.5.10（参照客户端待装）。

iPhone 使用 compact 布局。本轮在 iPad Pro 模拟器验证 regular width 的 `NavigationSplitView`：侧栏媒体库 + 详情空态，不再放大 iPhone 单列。

## 交付内容

- `Scripts/run-ipad-layout.sh`：iPad 模拟器构建/安装/启动，等待冷启动，截图并校验非白屏（YAVG/大小）。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 布局 | 侧栏 + 详情“选择一部作品” |
| 截图 | YAVG **24.6**，177KB |
| 脚本 | `Scripts/run-ipad-layout.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 点击播放/横屏/多任务 | 待验证 |

证据：`Evidence/119-ipad-layout.png/.jpg`、`reports/m6h-ipad-launch.log`、`reports/m6h-ipad-layout.txt`。

## 可复现差异与未验证

1. **iPad 冷启动约15s** 才出现内容；期间系统 spinner/白屏。
2. **autoplay 测试钩子在 iPad 未触发全屏播放**；用户点击路径未自动化。
3. **横屏/Split View/Stage Manager/真实 iPad**未测。
4. **物理5.1/HDMI、HDR测量、CloudKit、visionOS**未完成。

## 下一项

M6i/M5au：iPad 点击播放/横屏/多任务；物理5.1/HDMI；HDR测量；小时级/DFS；CloudKit/visionOS。
