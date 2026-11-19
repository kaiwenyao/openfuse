# M1 证据

均由 2026-11-19 的 `m1-local-playback` 构建在 MacBook Pro（M2 Pro，macOS 27.2.1）上生成。

| 文件 | 内容 | 采集方式 |
| --- | --- | --- |
| `01-home-continue-watching.jpg` | 首页继续观看卡片，00:25 / 01:00 | 应用内 `cacheDisplay` 窗口快照 |
| `02-player-controls.jpg` | 播放器控制层、字幕/音轨菜单标签 | 同上；OpenGL 视频层不进窗口快照，视频区为黑色 |
| `03-hevc-main10-frame.jpg` | 13.458 s 的实际渲染帧，含时间码与 5.1 声道图 | 播放器 `glReadPixels` |
| `04-subtitle-zh-hans.jpg` | 9.917 s，外挂简体 + 日文双语 | 同上 |
| `05-subtitle-zh-hant.jpg` | 9.917 s，外挂繁体 + 日文双语 | 同上 |
| `06-subtitle-font-fallback.jpg` | 4.417 s，缺字体 NOTE 样式与双语字幕 | 同上 |
| `reports/*.json` | 对应运行报告、续播存储、24 项声道检测 | 应用 `--report` 与 `analyze_audio.py` |

报告中的绝对路径已替换为仓库相对路径，日志保留最后 20 行。原始 PNG 与测试片不入库，可用 `Scripts/make_fixtures.sh` 重新生成。

窗口快照不能捕获 `NSOpenGLView` 是 macOS 的既有行为；因此不能用窗口图判断“是否出画”，必须看 `03`–`06` 这类渲染帧。
