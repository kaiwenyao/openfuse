# M6a 验收记录：visionOS 沉浸式播放

日期：2026-11-20。分支：`m6-immersive`。基线：Infuse 8.5.10（参照客户端待装）。

M6 此前只有 window/sheet。本轮新增 ImmersiveSpace：RealityKit VideoMaterial 空间屏幕、播放/暂停/拖动/关闭控件，详情页「沉浸式播放」；自动验收用 `OPENFUSE_IMMERSIVE=1`。

## 交付内容

- `VisionImmersiveModel`：准备 AVPlayer、时长/进度、seek、finish 记录进度。
- `VisionImmersiveView`：4×2.25m plane，VideoMaterial，底部控件。
- App 增加 `ImmersiveSpace(id:)` 与 `.mixed` 风格；根/详情注入 playback。
- 显式 `Platforms/Vision/Info.plist`：`UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes=true`（原先系统拒绝沉浸空间）。
- 验收脚本 `Scripts/run-vision-immersive.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 多场景 plist | true |
| ImmersiveSpace | 启动无 "Unable to open" 拒绝 |
| 截图 | 大空间 plane + 应用窗口 |
| Simulator VideoMaterial | Metal device 不可用，plane 黑屏 |
| 自动化 | `Scripts/run-vision-immersive.sh` PASS |
| `swift test` | **34/34 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真机观感/手势/进度 | 待验证 |

证据：`Evidence/92-vision-immersive.jpg`、`reports/m6a-vision-immersive.txt`。

## 可复现差异与未验证

1. **Vision Pro 模拟器 Metal 不可用**，VideoMaterial 黑屏；真机渲染未验证。
2. **手势/眼动控件**未做自定义，仅系统指针/按钮。
3. **沉浸退出写进度**代码已接，未在真机验证。
4. **空间音频/环境**未做。
5. **音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList**仍未完成。

## 下一项

visionOS 手势与退出进度回写已在 [M6b 验收](Docs/M6B-VISION-CONTROLS.md) 完成。剩余 M6c：真机 VideoMaterial/手势/空间音频、音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList。
