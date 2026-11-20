# M4h 验收记录：iOS 模拟器实际远程播放（WebDAV + Jellyfin）

日期：2026-11-20。分支：`m4h-mobile-remote`。基线：Infuse 8.5.10（参照客户端待装）。

上一轮验证了 iOS 本地 MP4 播放/续播。本轮在 iOS 27.2 模拟器里实际添加 WebDAV/Jellyfin 来源、扫描并播放远程条目，截取播放画面；此前这些链路只有桌面 probe 与构建验证。

## 交付内容

- **测试来源注入**：`OPENFUSE_TEST_WEBDAV_URL/USER/PASSWORD`、`OPENFUSE_TEST_JELLYFIN_URL/USER/PASSWORD`，应用启动后自动添加来源并扫描；仅测试环境变量。
- **自动播放选择**：`OPENFUSE_AUTOPLAY=1`、`OPENFUSE_AUTOPLAY_SOURCE=webdav|jellyfin`、`OPENFUSE_AUTOPLAY_TITLE=...`。
- **WebDAV 实际播放**：本地 WebDAV Basic Auth 服务器提供 H.264/AAC MP4；App 扫描入库，`AuthenticatedAssetLoader` 注入 Basic 头，AVPlayer 播放/推进。
- **Jellyfin 实际播放**：fixture 登录、扫描、PlaybackInfo，选择 MKV 条目后使用 `master.m3u8` H.264/AAC/TS 转码 URL，AVPlayer 在模拟器播放 60s HLS。
- **测试凭据修正**：未签名模拟器 Keychain 写入失败，自动注入来源之前拿不到密码，自动播放回退到本地样本；测试 bootstrap 改为内存凭据（ephemeral），生产 UI 仍走 Keychain。
- **测试 HUD**：仅在 autoplay 钩子显示当前时间/总时长；正常 UI 不显示。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| WebDAV 添加/扫描 | 模拟器内成功（服务器日志有 PROPFIND/GET/Range 与 Basic auth） |
| WebDAV 远程播放 | HUD **11.0 / 20.0s**，服务器 HEAD/GET Range 206，画面推进 |
| Jellyfin 登录/扫描 | 模拟器内成功 |
| Jellyfin 远程播放 | MKV→HLS，HUD **9.0 / 60.0s**，URL 为 master.m3u8 |
| 26 个单元测试 | **26/26 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 移动端 60s HLS | 标题筛选选中 Jellyfin movie-1，AVPlayer 播放至 9.0/60.0s |
| 音频/字幕/音轨 | **未验证** |

证据：

- `Evidence/42-ios-webdav-remote.jpg`
- `Evidence/43-ios-jellyfin-remote.jpg`
- `reports/m4h-mobile-remote.txt`

## 可复现差异与未验证

1. **音频未听测**：截图只证明画面与进度；模拟器音频输出、E-AC-3 5.1 未验证。
2. **测试 bootstrap 使用内存凭据**：仅本地模拟器绕过 Keychain 限制；生产来源 UI 仍走 Keychain，需在签名应用验证。
3. **字幕/音轨切换未接**；AVPlayer 默认轨。
4. **测试环境变量携带明文密码**，仅用于本地模拟器；生产仍走 Keychain/UI。
5. **tvOS/visionOS 无 runtime**，仍构建验证。
6. **真实 Jellyfin/OpenList 未验证**；服务器均为本地夹具。
7. **CloudKit/Trakt/iCloud 同步未做。**
8. **M3 画质元数据/T07 其他场景未补。**

## 下一项

M4i：修正移动端 HLS 选择并截取 60s 远程播放；字幕/音轨；音频听测；tvOS/visionOS runtime；真实 Jellyfin/OpenList；CloudKit/Trakt；M3 画质元数据/T07。
