# M5z 验收记录：E-AC-3 5.1 解码到 PCM

日期：2026-11-20。分支：`m5z-audio-pcm`。基线：Infuse 8.5.10（参照客户端待装）。

系统音频回环捕获被 macOS 权限阻断，无法直接录音。改用 libmpv 的 `ao=pcm` 测试模式把 E-AC-3 解码写成 WAV，验证 6 声道/5.1/48kHz/六路均有信号。**这不是扬声器听测**。

## 交付内容

- MPVEngine 测试模式：`OPENFUSE_AO_PCM=/path.wav` 时 `ao=pcm`、`ao-pcm-file`、waveheader、`audio-channels=5.1`；正常模式仍 CoreAudio。
- 验收脚本 `Scripts/run-audio-pcm.sh`：ffprobe + astats 六声道。
- 播放 16s 覆盖 FL/FR/FC/LFE/BL/BR 走查段。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 编码 | pcm_f32le |
| 采样率 | 48000 Hz |
| 声道 | **6 / 5.1** |
| 时长 | 16.096s |
| 六路电平 | FL/FR/FC/LFE/BL/BR 均非静音（RMS 约 -24..-29 dB） |
| Stereo downmix | 2ch/48k/16.1s，两路 RMS 约 -24 dB |
| 脚本 | `Scripts/run-audio-pcm.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 扬声器听测 | **待验证** |

证据：`reports/m5z-audio-pcm-probe.json`、`reports/m5z-audio-astats.txt`、`reports/m5z-stereo-probe.json`、`reports/m5z-stereo-astats.txt`、`reports/m5z-audio-pcm.txt`。

## 可复现差异与未验证

1. **只验证解码/PCM 布局**，未验证扬声器/耳机实际可听、CoreAudio 设备路由。
2. **立体声 downmix 已验证为 2ch 非静音**；对白可懂度未听测。
3. **未做人工 A/V 同步听测**。
4. **HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit、iOS 远程 MKV**未做。

## 下一项

M5aa：真实扬声器听测/设备路由；downmix；HDR 直通；真实 SMB3/Trakt；AirPlay；CloudKit；iOS 远程 MKV。
