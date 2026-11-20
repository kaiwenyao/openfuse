# M5l 验收记录：SMB 来源（libsmb2）

日期：2026-11-20。分支：`m5l-smb`。基线：Infuse 8.5.10（参照客户端待装）。

Homebrew 没有 libsmb2 formula。本轮从源码构建 libsmb2 7.0，加入 CSMB2 模块，实现 SMB2 来源：列表、递归扫描、下载到缓存、libmpv 播放。用 impacket SMB2 服务器（端口 1445）完成登录/扫描/播放验收。

## 交付内容

- `Scripts/install-libsmb2.sh`：源码构建/安装 libsmb2 到 /opt/homebrew。
- `Sources/CSMB2`：C shim/module map；`Package.swift` 条件依赖（仅 macOS）。
- `SMBClient`：`smb2_parse_url`（支持端口）、connect、opendir/readdir、stat/open/pread（64KiB 分块，按 stat 大小处理服务器 EOF 错误）。
- `SMBSourceStore` + Keychain；`SMBLibraryScanner` 递归视频；`MediaItem.Origin.smb`。
- App：SMB 添加/扫描/删除、来源卡、媒体库标签；播放下载到 `SMBCache` 后交给 mpv；`--smb-*` CLI。
- 验收 `Scripts/run-smb-acceptance.sh`（自动创建 impacket venv/服务器）。
- 自包含打包会把 libsmb2 复制进 Frameworks。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| SMB 登录/列表 | impacket SMB2，test/test |
| 扫描 | 1 作品/1 集，sourceKind **smb**，卡片标签 SMB |
| 下载 | 17,654,819 bytes，SHA-256 与夹具一致 |
| 播放 | sourceKind smb，位置 **9.958s**，remotePath `/Movie/OpenFuse.SMB.mkv` |
| 缓存 | `SMBCache/<hash>.mkv` |
| 自包含 | libsmb2 在 Frameworks；lsof 0 Homebrew |
| `swift test` | **28/28 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 SMB/SMB3/DFS | 待验证 |

证据：`Evidence/74-smb-library.jpg`、`75-smb-playback.jpg`、`reports/m5l-smb-*.json`、`reports/m5l-smb.txt`。

## 可复现差异与未验证

1. **当前是全文件下载后播放**，不是边下边播/远程 seek；大文件不可接受，需本地 HTTP Range 代理。
2. **仅 macOS**：CSMB2/system library 不参与 iOS/tvOS/visionOS 构建。
3. **真实 SMB 服务器**、SMB3 签名/加密、DFS、域账号、超时未测；只测 impacket SMB2。
4. **SMB 无 NFO/海报/外挂字幕发现**；媒体库用占位海报。
5. **凭据**：Keychain 或 `OPENFUSE_SMB_PASSWORD`；没有 UI 凭据隔离/多账号策略。
6. **版本级去重、HDR/AirPlay 实机、CloudKit/Trakt、音频、M3 多根/损坏过滤**未做。

## 下一项

M5m：SMB Range 代理/边下边播、真实服务器、NFO/字幕；版本级去重；HDR/AirPlay 实机；CloudKit/Trakt；音频；M3 多根/损坏过滤。
