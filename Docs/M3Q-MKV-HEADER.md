# M3q 验收记录：纯 Swift MKV 头部解析

日期：2026-11-20。分支：`m3q-mkv-header`。基线：Infuse 8.5.10（参照客户端待装）。

iOS/tvOS/visionOS 没有 ffprobe，WebDAV 远程 MKV 分辨率/HDR 为空。本轮实现 EBML/Matroska 头部解析：Range 读取前 2MB，解析 PixelWidth/Height 与 Colour Transfer/Primaries；iOS 默认使用，macOS 可用 env 强制。

## 交付内容

- `MatroskaProbe`：EBML vint、Segment/Info/Tracks/TrackEntry/Video/Colour 递归；截断主元素按可用数据解析。
- WebDAV `probeRemoteHeight` 对 MKV 优先/回退头部解析；Range 0..2MB。
- 单元测试 2 个；验收脚本 `Scripts/run-mkv-header.sh`。
- 音频脚本补充 5.1→stereo downmix 验证。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 主夹具 | 1920×1080 → 1080p |
| HDR 夹具 | transfer 16/primaries 9 → HDR10 |
| WebDAV 扫描 | 1080p · WebDAV，dynamicRange=HDR10 |
| 单测 | MatroskaProbeTests 通过，总 **31/31** |
| 脚本 | `Scripts/run-mkv-header.sh` PASS |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 OpenList/畸形 EBML | 待验证 |

证据：`reports/m3q-mkv-header.json`、`reports/m3q-mkv-header.txt`。

## 可复现差异与未验证

1. **只读前 2MB**；Tracks 在 2MB 之后的文件会失败。
2. **畸形/超大 EBML 未测**；未知尺寸/截断只做了基础处理。
3. **iOS 运行期扫描未跑**；只验证 macOS 强制 parser + iOS 构建。
4. **音频仍只验证 PCM/downmix，未扬声器听测**。
5. **HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit**未做。

## 下一项

M3r/M5aa：真实 OpenList/大头部 EBML；iOS 运行期扫描；扬声器听测；HDR 直通；真实 SMB3/Trakt；AirPlay；CloudKit。
