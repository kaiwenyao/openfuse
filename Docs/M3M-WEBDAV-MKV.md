# M3m 验收记录：WebDAV MKV 分辨率

日期：2026-11-20。分支：`m3m-webdav-mkv-resolution`。基线：Infuse 8.5.10（参照客户端待装）。

此前 WebDAV 只有 MP4/MOV 通过 AVAsset 读分辨率，远程 MKV 没有画质元数据。现在对 MKV/TS/WebM/AVI 调用带 Basic Auth 的 ffprobe，用 HTTP Range 读取头部并解析高度；结果写入版本 resolution 和名称，1080p 过滤器覆盖远程 MKV。

## 交付内容

- `LibraryScanner.probeRemoteVideoHeight`：ffprobe `Authorization` 头、`-rw_timeout 8000000`、`-analyzeduration/-probesize` 限制。
- 使用 `terminationHandler` + 临时输出文件，避免 App 内 `waitUntilExit` 卡住。
- `ScannedVersion.name` 带分辨率（如 `1080p · WebDAV`）；库报告序列化 `resolution`。
- 验收脚本 `Scripts/run-webdav-mkv-resolution.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 远程 MKV 探测 | ffprobe 带 Basic Auth/Range，输出 1080 |
| 版本 | `resolution=1080p`，`name=1080p · WebDAV` |
| 画质筛选 | `--library-resolution hd1080` 可见 `OpenFuse Remote` |
| 服务器 | Lavf GET Range 206，探测后中止 |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 OpenList/百度网盘 | 待验证 |
| iOS 设备远程 MKV 探测 | 未实现（ffprobe 路径 macOS-only） |

证据：`Evidence/70-webdav-mkv-resolution.jpg`、`reports/m3m-webdav-mkv-library.json`、`reports/m3m-webdav-mkv-filter.json`、`reports/m3m-webdav-mkv.txt`。

## 可复现差异与未验证

1. **仅 macOS 扫描端**：iOS/tvOS/visionOS 没有 ffprobe，远程 MKV 分辨率仍为空。
2. **真实 OpenList/百度网盘** 的重定向、鉴权、Range/限速未验证；大文件探测超时策略只设 8s。
3. **HDR/4K 元数据**未解析，仅高度。
4. **多根本地库策略/损坏过滤、重启字幕更新**未做。
5. **Plex 详情点击/音轨、版本级去重、SMB/HDR/AirPlay、CloudKit/Trakt、音频**未做。

## 下一项

Mac AirPlay 入口已在 [M5j 验收](Docs/M5J-AIRPLAY.md) 完成（UI）。剩余 M5k：AirPlay/HDR 实机、Plex 详情点击/音轨、版本级去重、SMB、CloudKit/Trakt、音频、M3 多根/损坏过滤。
