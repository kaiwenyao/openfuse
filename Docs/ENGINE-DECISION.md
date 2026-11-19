# M0 引擎选型记录：AVFoundation 与 libmpv

记录日期：2026-11-19（Europe/Dublin）。对照基线为 Infuse 8.5.10；本机没有安装 Infuse，因此本文只记录 OpenFuse 侧的可复现测量，Infuse 同素材对照标记为「待采样」。

## 测试环境

| 项 | 值 |
| --- | --- |
| 机器 | MacBook Pro（Apple M2 Pro，arm64） |
| 系统 | macOS 27.2.1（26B131） |
| 工具链 | Xcode 27.2（27B52），Swift 6.4.2 |
| 视频引擎 A | AVFoundation / AVPlayer（系统框架） |
| 视频引擎 B | libmpv 0.42.0（Homebrew，FFmpeg 9.0.2，libass） |
| 显示 | 内置 Liquid Retina XDR，逻辑 1512×982，2× 缩放 |
| 音频 | 内置 MacBook Pro 扬声器（CoreAudio device 101） |
| 权益 | 不适用（OpenFuse 本地构建） |

## 样片

`Fixtures/generated/openfuse-fixture.mkv`：60.000 s，1920×1080，24.000 fps，HEVC Main 10（yuv420p10le，BT.709），E-AC-3 5.1 448 kb/s 单音轨，内嵌 ASS 一条，同目录三份外挂 ASS。素材由仓库脚本生成，详见 [TEST-MEDIA.md](TEST-MEDIA.md)。

## 测量结果

同一文件、同一台机器，`openfuse-probe` 分别走两条路径：

| 指标 | AVFoundation | libmpv |
| --- | --- | --- |
| `isPlayable` / 打开 | false | true |
| 时长 | 0 s | 60.000 s |
| 轨道枚举 | 0 条 | HEVC Main 10、E-AC-3 6ch、ASS |
| 首帧 | 无（容器不支持） | 无窗口路径 0.078 s（解码侧）；应用内由 VideoToolbox 硬解 |
| 定位到 30 s | 不可用 | 30.042 s |
| 外挂 ASS | 不支持 | 已渲染（简繁切换见 M1 记录） |
| 音轨 | 不可用 | 5.1(side) 解码，CoreAudio 下混 2ch |
| 硬解 | — | 应用内 `hwdec-current=videotoolbox` |

命令与原始输出：

```bash
.build/debug/openfuse-probe avplayer Fixtures/generated/openfuse-fixture.mkv
# {"duration":0,"engine":"AVFoundation","playable":false,"tracks":[]}

.build/debug/openfuse-probe mpv Fixtures/generated/openfuse-fixture.mkv 30
# playable=true, duration=60, position=30.042, audioChannels=6,
# tracks: video hevc / audio eac3 6ch / sub ass
```

AVPlayer 连 Matroska 容器都无法打开，轨道数为 0；这不是解码器问题，而是容器层缺失。要沿用 AVPlayer，需要先把 MKV 重封装成 MP4，再把 ASS 转成 WebVTT 或烧录，且会丢失多轨与样式，与「保留服务器/文件轨道、直接播放」的目标冲突。

## 结论

1. **主播放路径选 libmpv**（libmpv + libass + FFmpeg + VideoToolbox 硬解 + CoreAudio），覆盖 MKV、HEVC Main 10、E-AC-3 5.1、ASS 附件字体与精确拖动。M1 的应用即走此路径。
2. **AVFoundation 暂不作为主路径**，只保留为后续系统能力（画中画、AirPlay、锁屏控制）的候选；需要这些能力时在支持的容器上并行验证，不阻塞 MKV/ASS。
3. **渲染方式**：libmpv render API（OpenGL）绘制到 `NSOpenGLView`，应用层负责控制层、进度持久化和轨道菜单。首次尝试在文件加载后才创建 render context，mpv 报 `vo/libmpv: No render context set.`，画面为黑；已改为 render context 就绪后才 `loadfile`，并在 M1 记录中复测通过。
4. **风险**：libmpv/FFmpeg 的 GPL/LGPL 义务、发行打包、Homebrew 运行时依赖。M1 的构建脚本要求 `brew install mpv`，把 dylib 打进 .app 留到打包阶段（M5）处理。

## 尚未覆盖

- Infuse 8.5.10 同素材实测（本机无 Infuse，待采样）。
- HDR10 / Dolby Vision、画中画、AirPlay、Google Cast。
- 20 次冷/热缓存首帧与拖动统计（当前只有单次探针和应用内观察）。
- 外接 5.1 接收器上的真实声道输出；当前只验证到 CoreAudio 请求 5.1、系统输出 2ch，以及文件本身的离散声道测量。
- 其他平台（iOS/iPadOS/tvOS/visionOS）。
