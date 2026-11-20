# M5ac 验收记录：CoreAudio 输出设备选择

日期：2026-11-20。分支：`m5ac-audio-devices`。基线：Infuse 8.5.10（参照客户端待装）。

此前 mpv 只用默认 CoreAudio 设备。现在枚举输出设备，在播放器「音轨 → 音频输出」中可选自动/具体设备，测试可用 `OPENFUSE_AUDIO_DEVICE` 指定；报告记录选中与生效设备。

## 交付内容

- `AudioDeviceInfo` / `AudioDevices.outputDevices()`：CoreAudio 设备/UID/输出声道。
- PlayerModel `audioDevices`、`selectedAudioDeviceID`、`selectAudioDevice`。
- PlayerView 音频输出菜单增加设备列表与勾选。
- 播放报告 `audioDevice` / `audioDeviceActive`。
- probe `audio-devices`；验收脚本 `Scripts/run-audio-devices.sh`。
- 修复报告字典重复 `audioDevice` 键导致的 SIGTRAP。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设备枚举 | 包含 `coreaudio/BuiltInSpeakerDevice` |
| 选中设备 | `coreaudio/BuiltInSpeakerDevice` |
| 生效设备 | `coreaudio/BuiltInSpeakerDevice` |
| AO | `coreaudio` |
| 声道 | 6 |
| 脚本 | `Scripts/run-audio-devices.sh` PASS |
| `swift test` | **31/31 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 实际听测/热插拔 | 待验证 |

证据：`reports/m5ac-audio-devices.json`、`reports/m5ac-audio-device-play.json`、`reports/m5ac-audio-devices.txt`。

## 可复现差异与未验证

1. **未实际听声音**；只验证属性/设备选择。
2. **设备热插拔/失效回退**未处理。
3. **exclusive mode/AirPlay 路由**未做。
4. **HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList**未做。

## 下一项

跨来源内容指纹已在 [M5ad 验收](Docs/M5AD-CROSS-SOURCE-FINGERPRINT.md) 完成。剩余 M5ae：全文件/可配置哈希、SMB HDR 探测、远程指纹性能、听测/热插拔、HDR 测量、真实 SMB3/Trakt、CloudKit、真实 OpenList。
