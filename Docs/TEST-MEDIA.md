# 测试素材：OpenFuse Playback Fixture

所有播放验收都使用仓库脚本生成的自有素材，不含商业影片、不依赖第三方字体授权（测试字体为 SIL Open Font License 的 Noto Sans SC）。

## 生成

```bash
brew install ffmpeg mpv          # ffmpeg 只用于编码与校验；播放用 libmpv
Scripts/make_fixtures.sh         # 60 s 完整样片，约 2–3 分钟
```

产物在 `Fixtures/generated/`（已被 `.gitignore` 排除，不入库）：

| 文件 | 说明 |
| --- | --- |
| `openfuse-fixture.mkv` | 视频 + E-AC-3 5.1 + 内嵌 ASS + 字体附件 |
| `openfuse-fixture.zh-Hans.ass` | 外挂简体中文 + 日文双语 |
| `openfuse-fixture.zh-Hant.ass` | 外挂繁体中文 + 日文双语 |
| `openfuse-fixture.ass` | 无语言标签的同结构外挂 |
| `audio.wav` / `audio.eac3` | 中间产物，6 声道 |
| `probe.json` / `audio-channel-map.json` | 自动校验结果 |
| `SHA256SUMS.txt` | 哈希 |

生成脚本最后会做三重校验：ffprobe 流参数、E-AC-3 解码后的逐声道音调检测、时长检查。任何一项失败都会以非零状态退出。

## 容器与流

| 项 | 值 |
| --- | --- |
| 容器 | Matroska |
| 时长 | 60.000 s |
| 视频 | HEVC Main 10，1920×1080，24.000 fps，yuv420p10le，BT.709 SDR |
| 音频 | E-AC-3，5.1(side)，48 kHz，448 kb/s，单音轨 |
| 字幕 | 内嵌 ASS（language=chi）；外挂 3 份 |
| 附件 | NotoSansSC-Regular.otf，标记 `font/otf` |

2026-11-19 生成结果（SHA-256）：

```
37875d6824c50391eda313b9c1fcdcba858e2525f4d8914cdf6ca4983e3cddd4  openfuse-fixture.mkv
192ecf4e325cccc78f03d1fc7751d0a14ea0c7142ac782975e1e8ac32627361d  video.mkv
7d81a5c83ebfdf24eabf00243e6aa1dfd9fbcfcd149cb0b33546c2c14aa2948e  audio.wav
0e6895a25752b327a45702b31fc62f69806cf4bb16e7be8fedbd1741535e5f89  openfuse-fixture.zh-Hans.ass
6b279ab01259bc11b9f1d4ed69864dceb7c30ab227d70a24dcae111b3087bd73  openfuse-fixture.zh-Hant.ass
faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9  NotoSansSC-Regular.otf
```

## 画面

每一帧包含：

- 精确到帧的时间码 `HH:MM:SS:FF` 与 `t = 秒.毫秒`；
- 帧号 / 总帧数；
- 10 秒一换的场景色与场景编号；
- 右侧 5.1 声道图和当前秒高亮的扬声器；
- 每秒整点的一帧全白闪，用于音画同步；
- 底部「字幕安全区」标记，便于比对字幕基线。

整秒白闪与整秒 1 kHz 短音对齐；把任一帧的时间码与报告里的 `position` 比较即可测同步偏差。M1 实测：抓帧 00:00:13:11（13.458 s），同次报告 `position=13.458`。

## 声音

音频按 11.4 s 一个循环，每 1.9 s 一个声道：

| 顺序 | 声道 | 频率 |
| --- | --- | --- |
| 1 | FL 左前 | 440 Hz |
| 2 | FR 右前 | 554 Hz |
| 3 | FC 中置 | 659 Hz |
| 4 | LFE 低频 | 41 Hz |
| 5 | BL 左环绕 | 740 Hz |
| 6 | BR 右环绕 | 880 Hz |

每个声道先响 0.55 s 音调，再在该声道播报「左前声道 / 左前チャンネル」等。中置另有开场白和整秒 1 kHz 同步音。

自动校验 `Tools/analyze_audio.py` 用 Goertzel 在音调频率上测每个声道的能量，要求目标声道最强、其余声道泄漏低于 −30 dB。2026-11-19 的结果：**24 个音调测试全部通过，0 失败**，明细见 `Docs/Evidence/reports/audio-channel-map.json`。

注意：这只证明文件里是离散 5.1。播放端是否真的把 5.1 送到接收器，要看 `audio-out-params` 和实际设备；M1 在 MacBook 扬声器上得到 6ch → 2ch 的下混，外接 5.1 设备待验证。

## 字幕

三份外挂共用同一时间轴，简体/繁体只改字形；每一行自带时间码文字，便于拖动后核对。

| 入点 | 出点 | 内容（简体版） |
| --- | --- | --- |
| 00:02.50 | 00:06.20 | 第一句：画面 2.5 秒，字幕准时出现。 |
| 00:08.00 | 00:11.50 | 第二句：中文字体回退测试，缺字体也要显示。 |
| 00:16.00 | 00:19.50 | 数字对齐 0123456789，标点：，。！？ |
| 00:26.00 | 00:29.50 | 第三句：简体中文字幕轨道，拖动后应重新同步。 |
| 00:34.00 | 00:40.00 | 长句测试……（单行、居中、描边与双语位置） |
| 00:44.00 | 00:47.50 | 第四句：接近片尾，用于验证末尾拖动。 |
| 00:52.00 | 00:58.00 | 最后一句：字幕结束于 58.0 秒，之后不应残留。 |

样式：

- `ZH`：PingFang SC，底部居中，Alignment 2，MarginV 70；
- `JA`：Hiragino Sans，顶部居中，Alignment 8，MarginV 132；
- `NOTE`：字体名 `OpenFuse Missing Font`（系统未安装），内容为中文 + 英文，用来验证缺字体回退；
- `KARA`：`\k` 卡拉 OK 标签，00:35–00:38 逐字变色。

## 复现命令

```bash
# 只做文件级校验，不启动播放器
ffprobe -v error -show_streams -show_format Fixtures/generated/openfuse-fixture.mkv
python3 Tools/analyze_audio.py Fixtures/generated/openfuse-fixture.mkv \
  --out Fixtures/generated/audio-channel-map.json

# 应用内抓取真实渲染帧
.build/debug/openfuse-probe avplayer Fixtures/generated/openfuse-fixture.mkv   # 预期不可播放
.build/debug/openfuse-probe mpv Fixtures/generated/openfuse-fixture.mkv 30      # 预期可播放、可定位
```

## 局限

- 合成样片只覆盖 HEVC Main 10 + E-AC-3 5.1 + ASS；其他编码、HDR、PGS/VobSub、音轨切换仍待 M5 的格式矩阵。
- 日语字体在本机来自系统 Hiragino；如果目标机器没有日文字体，回退结果会不同，需要按平台登记。
- 字体已下载到生成目录，构建需要网络；URL 与 OFL 许可证在 `Scripts/make_fixtures.sh` 中固定。
- 素材不入库，只有脚本、哈希和脱敏报告入库。
