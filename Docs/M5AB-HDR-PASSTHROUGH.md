# M5ab 验收记录：EDR 屏幕 HDR 直通

日期：2026-11-20。分支：`m5ab-hdr-passthrough`。基线：Infuse 8.5.10（参照客户端待装）。

M5y 只做 SDR 色调映射。本机 Built-in Retina Display 的 EDR 潜力为 16，支持 HDR。现在按屏幕 EDR 自动设置 `target-colorspace-hint=yes`，报告屏幕能力与 mpv 输出参数；实测输出为 bt.2020/pq、light=display、max-luma=1000。

## 交付内容

- MPVEngine：`NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1` 且未禁用时 `target-colorspace-hint=yes`；`OPENFUSE_HDR_PASSTHROUGH=0` 可关闭。
- 播放报告新增 `screenEDR`；沿用 `targetColorspaceHint` / `videoOutParams`。
- 验收脚本 `Scripts/run-hdr-passthrough.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 屏幕 EDR | **16.0**（Built-in Retina Display） |
| target-colorspace-hint | **yes** |
| 源 | bt.2020/pq |
| 输出参数 | light=display、bt.2020/pq、max-luma=1000、p010 |
| mpv 警告 | OpenGL 渲染器无 compute shader/SSBO，HDR peak computation 被禁用 |
| 脚本 | `Scripts/run-hdr-passthrough.sh` PASS |
| `swift test` | **31/31 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 实测 HDR 亮度/观感 | 待验证 |

证据：`Evidence/91-hdr-passthrough.jpg`、`reports/m5ab-hdr-passthrough.json`、`reports/m5ab-hdr-passthrough.txt`。

## 可复现差异与未验证

1. **未用色度计/EDR 捕获测量亮度**；只验证输出参数与屏幕能力。
2. **OpenGL 渲染器不支持 HDR peak computation**；原生 Metal/VideoToolbox 直通未实现。
3. **截图是 SDR 合成**，不能证明肉眼 HDR 效果。
4. **音频仍只验证 PCM/downmix，未扬声器听测**。
5. **真实 SMB3/Trakt、AirPlay、CloudKit、真实 OpenList 大头部**未做。

## 下一项

M5ac：Metal/EDR 渲染与 HDR 测量；音频听测/设备路由；SMB/WebDAV 指纹；真实 SMB3/Trakt；AirPlay；CloudKit；真实 OpenList。
