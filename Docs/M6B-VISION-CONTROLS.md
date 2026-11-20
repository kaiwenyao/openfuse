# M6b 验收记录：visionOS 沉浸手势与进度回写

日期：2026-11-20。分支：`m6b-immersive-controls`。基线：Infuse 8.5.10（参照客户端待装）。

M6a 只证明沉浸空间能打开。本轮加拖动/缩放空间屏幕手势，并让自动关闭走同一条 finish 路径；模拟器实测退出后 PlaybackStore 写入 7.5s，窗口显示「从 7 秒继续」。

## 交付内容

- `VisionImmersiveView`：DragGesture 平移平面（0.004m/px）、MagnificationGesture 0.6–2.0 缩放。
- `OPENFUSE_IMMERSIVE_AUTOCLOSE=s` 自动 finish + dismiss；退出记录进度。
- `finish` 幂等，避免 onDisappear 双写。
- 验收脚本增加：沉浸截图 + autoclose=6 + 读取 app 容器 playback.json。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 自动关闭 | 6s 后退出沉浸空间 |
| PlaybackStore | position **7.517s** / duration 20.105s |
| 窗口续播 | 「从 7 秒继续」 |
| 手势 | 代码编译，模拟器未做手势自动化 |
| 脚本 | `Scripts/run-vision-immersive.sh` PASS |
| `swift test` | **34/34 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真机 VideoMaterial/空间音频 | 待验证 |

证据：`Evidence/93-vision-autoclose.jpg`、`reports/m6b-vision-playback.json`、`reports/m6b-vision-controls.txt`。

## 可复现差异与未验证

1. **模拟器 Metal 不可用**，VideoMaterial 仍黑屏。
2. **手势/眼动交互未自动化**；真机手感未验证。
3. **空间音频/环境**未做。
4. **音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList**未做。

## 下一项

M6c：真机 VideoMaterial/手势/空间音频；音频听测；HDR 测量；真实 SMB3/Trakt；CloudKit；真实 OpenList。
