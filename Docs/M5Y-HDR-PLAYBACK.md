# M5y 验收记录：HDR10 播放与色调映射

日期：2026-11-20。分支：`m5y-hdr-playback`。基线：Infuse 8.5.10（参照客户端待装）。

M5x 只把 HDR 元数据入库。本轮配置 libmpv 对 HDR10 做 SDR 色调映射（spline + hdr-compute-peak），播放 1080p10bit bt2020/smpte2084 样片，确认 mpv 解码为 PQ/bt.2020 并正常出画。

## 交付内容

- MPVEngine：`tone-mapping=spline`（`OPENFUSE_TONE_MAPPING` 可覆盖）、`hdr-compute-peak=yes`、`target-peak=auto`。
- 播放报告新增 toneMapping/hdrComputePeak/videoPrimaries/videoGamma/videoSigPeak/targetColorspaceHint。
- 验收脚本 `Scripts/run-hdr-playback.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 解码 | HEVC Main 10 |
| primaries/gamma | **bt.2020 / pq** |
| sig-peak | **4.926108** |
| tone mapping | **spline**，compute-peak yes |
| 画面 | SDR 截图彩色条正常，非黑屏/过曝 |
| 位置 | 1.542s |
| 脚本 | `Scripts/run-hdr-playback.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 HDR 显示 | 待验证 |

证据：`Evidence/89-hdr-playback.jpg`、`reports/m5y-hdr-playback.json`、`reports/m5y-hdr-playback.txt`。

## 可复现差异与未验证

1. **只验证 SDR tone mapping**；未验证 HDR 直通/真实 HDR 显示器。
2. **target-colorspace-hint 未真正启用**（auto）；macOS/OpenGL 输出链路未确认。
3. **HDR10+/Dolby Vision 映射精度**未验证。
4. **音频回环仍被权限阻断**。
5. **真实 SMB3/Trakt、AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

M5z：HDR 直通/真实显示器；音频听测；真实 SMB3/Trakt；AirPlay 实机；CloudKit；M3 多根/损坏过滤。
