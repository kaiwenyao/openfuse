# M6c 验收记录：full immersion 与 3D 控件

日期：2026-11-20。分支：`m6b-immersive-controls` 后续（M6c）。基线：Infuse 8.5.10（参照客户端待装）。

M6b 用 `.mixed` 时窗口挡住画面、VideoMaterial 黑屏。切换 `.full` 后视频实际渲染；补虚拟影院环境、3D 播放/关闭球与进度条；打开沉浸时关闭主窗口，退出再打开。

## 交付内容

- `.full` immersion；黑色地板、屏幕边框、48 个星点。
- 3D 控件：
  - 左上蓝色播放/暂停球，右上红色关闭球；
  - InputTarget/Collision + `TapGesture().targetedToAnyEntity()`；
  - 底部黄色进度条按 position/duration 缩放。
- 窗口管理：`WindowGroup(id:"main")`，打开沉浸后 dismiss；关闭/自动关闭后 openWindow。
- `AVAudioSession.setIntendedSpatialExperience(.headTracked(soundStageSize:.medium, anchoringStrategy:.front))`，状态写入控件文字。
- 自动关闭仍写回进度（验收脚本）。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Full immersion | 实际渲染测试图 00:00:11:22 |
| 视频标识 | HEVC Main 10 / E-AC-3 5.1 可见 |
| 环境 | 星点、暗色地面/边框可见 |
| 3D 控件 | 播放/关闭球 + 进度条可见 |
| 主窗口 | 沉浸时关闭，截图无窗口 |
| 自动关闭 | playback.json 进度保留 |
| 脚本 | `Scripts/run-vision-immersive.sh` PASS |
| `swift test` | **34/34 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真机手势/空间音频 | 待验证 |

证据：`Evidence/94-vision-full-immersion.jpg`、`reports/m6c-vision-playback.json`、`reports/m6c-vision-environment.txt`。

## 可复现差异与未验证

1. **3D 控件点击未自动化**；真机手/眼命中精度未验证。
2. **空间音频只设置 intended experience**，未用真机听测。
3. **模拟器 VideoMaterial 在 full immersion 可出画**，但不代表真机 HDR/性能。
4. **音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList**仍未完成。

## 下一项

WebDAV/SMB 损坏签名过滤已在 [M3s 验收](Docs/M3S-REMOTE-CORRUPT.md) 完成。剩余 M6d/M5ai：真机 3D 控件/空间音频/HDR、碎片 MP4/SMB 性能、音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList。
