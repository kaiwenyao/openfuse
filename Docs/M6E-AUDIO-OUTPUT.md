# M6e 验收记录：实际音频输出与设备路由

日期：2026-11-20。分支 `m6e-audio-output`。基线 Infuse 8.5.10（参照客户端待装）。

此前只验证 mpv PCM 回调（6ch/2ch），未证明声音真正到达输出设备。本机存在 iFlyrecAudioDevice（BlackHole 2ch 虚拟设备），可同时作为输出与录音源。本轮用它录回放输出，并用内置扬声器做静音对照。

## 交付内容

- `Scripts/run-audio-output.sh`：
  - 自动发现 `coreaudio/...IFLYREC` 虚拟设备；
  - ffmpeg 录虚拟设备，同时 OpenFuse 输出到虚拟设备；
  - 再输出到内置扬声器、仍录虚拟设备作对照；
  - 断言源 E-AC-3 6ch、虚拟有信号、对照静音；
  - 生成波形图。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 源音轨 | E-AC-3 **6ch** |
| 虚拟输出录音 | mean **-24.5dB** / max -5.6dB |
| 扬声器对照 | mean **-91.0dB**（静音） |
| 脚本 | `Scripts/run-audio-output.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 物理5.1/人耳 | 待验证 |

证据：`Evidence/113-audio-output-wave.jpg`、`reports/m6e-audio-*`。

## 可复现差异与未验证

1. **录到的是2ch downmix**；虚拟设备只有2ch，物理5.1声道分离未测。
2. **无人耳听测**；仅有电平/波形与路由对照。
3. **蓝牙/AirPlay/HDMI 实机路由**未测。
4. **HDR测量、CloudKit、visionOS 真机**未完成。

## 下一项

M6f/M5ar：物理5.1/人耳/HDMI；HDR测量；>16并发/长稳/DFS；CloudKit真机。
