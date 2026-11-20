# M5m 验收记录：SMB 本地 HTTP Range 边下边播

日期：2026-11-20。分支：`m5m-smb-stream`。基线：Infuse 8.5.10（参照客户端待装）。

M5l 先全文件下载再播放。本轮改为回环 HTTP 服务器：mpv 对 `127.0.0.1:<port>/stream` 发 Range 请求，服务器用 libsmb2 pread 按 64KiB 从 SMB 读块并回写；支持 HEAD/206/Content-Range，不再产生 SMBCache 文件。

## 交付内容

- `SMBStreamServer`：BSD socket listener（Network.framework NWListener 在当前环境返回 EINVAL，独立 Swift 也可复现），HTTP/1.1 解析、Range/HEAD、64KiB 分块。
- `SMBClient.size/read`；`MediaItem.smb` 改为回环 HTTP URL，仍保留 `smb://` 续播键。
- AppModel 启动/关闭播放器时启停 server；不再下载整文件。
- 验收脚本改为 `--seek 30 --freeze-at 31`，断言 31s、回环 URL、无 SMBCache。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| SMB 扫描 | 1 作品/1 集，sourceKind smb |
| 播放 | 回环 `http://127.0.0.1:<port>/stream` |
| Seek | `--seek 30` → 报告 **31.0s** |
| 整文件缓存 | **无 SMBCache 文件** |
| 服务器 | impacket SMB2，test/test |
| 自动化 | `Scripts/run-smb-acceptance.sh` PASS |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 SMB3/DFS/大文件 | 待验证 |

证据：`Evidence/76-smb-stream-seek.jpg`、`reports/m5m-smb-stream.json`、`reports/m5m-smb-library.json`、`reports/m5m-smb-stream.txt`。

## 可复现差异与未验证

1. **未测真实 SMB3/DFS/签名/加密/域账号**；仅 impacket SMB2。
2. **大文件与并发 Range**：单连接串行、每 64KiB 打开/关闭 SMB 句柄，未做句柄复用/背压/限速。
3. **SMB 仍无 NFO/海报/字幕发现**。
4. **仅 macOS**；iOS/tvOS/visionOS 无 SMB。
5. **音频未听测**；HDR/AirPlay 实机、CloudKit/Trakt、版本级去重、M3 多根/损坏过滤未做。

## 下一项

M5n：SMB 句柄复用/并发/大文件、真实 SMB3；NFO/字幕；HDR/AirPlay 实机；CloudKit/Trakt；音频；版本级去重；M3 多根/损坏过滤。
