# M5j 验收记录：AirPlay 投屏入口

日期：2026-11-20。分支：`m5j-airplay`。基线：Infuse 8.5.10（参照客户端待装）。

在 Mac 播放器控制栏加入系统 AirPlay 路由选择器；无 AirPlay 接收设备，实际投屏未验证。

## 交付内容

- `AirPlayRoutePicker`：`AVRoutePickerView` 的 NSViewRepresentable，macOS 无 tint API，去掉自定义颜色，保留系统按钮。
- `PlayerView` 控制栏在字幕/音轨/倍速/全屏之间加入 AirPlay 图标，help「AirPlay 投屏」。
- 构建与 UI 截图验证按钮存在；没有伪造投屏成功。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Mac 构建 | 成功 |
| 控制栏 | AirPlay 图标位于全屏按钮左侧 |
| 本地播放 | MKV 打开/冻结 3s，控制栏字幕/音轨/倍速/全屏均正常 |
| `swift test` | **28/28 通过** |
| 五端/device | 全部 **BUILD SUCCEEDED** |
| 实际投屏 | **待验证**：无 AirPlay 接收设备 |
| HDR/空间音频路由 | 未做 |

证据：`Evidence/71-airplay-player.jpg`、`reports/m5j-airplay.txt`。

## 可复现差异与未验证

1. **未连接 Apple TV/AirPlay 接收器**：路由菜单、握手、音视频同步、HDR 均未测。
2. **iOS/tvOS 未加自定义 AirPlay 按钮**；AVKit 自带。
3. **音频未听测**。
4. **Plex 详情点击/音轨、版本级去重、SMB、CloudKit/Trakt、M3 多根/损坏过滤**未做。

## 下一项

Plex 详情/版本/音轨已在 [M5k 验收](Docs/M5K-PLEX-DETAIL.md) 完成。剩余 M5l：AirPlay/HDR 实机、真实 Plex/版本级去重、SMB、CloudKit/Trakt、音频、M3 多根/损坏过滤。
