# M4m 验收记录：远程精确 seek 与 Jellyfin 外挂字幕管线

日期：2026-11-20。分支：`m4m-seek-jf-subs`。基线：Infuse 8.5.10（参照客户端待装）。

本轮先修远程 seek：使用带 completion 的精确 seek、seek 前暂停、完成后等待；WebDAV 远程 seek 到 10s 后字幕切到第二句。另加入 Jellyfin 外挂字幕 DeliveryUrl 下载管线与夹具，但本轮未成功进入播放器验证画面。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| WebDAV 精确 seek | HUD **10.0/20.0s**，画面 source 15.0s |
| 远程字幕同步 | 显示「第二句：拖动后字幕仍同步。 / 二番目の字幕。シーク後も同期。」 |
| 服务器 | 字幕 GET 200，视频 Range 206 |
| Jellyfin 外挂字幕 | 夹具 DeliveryUrl/下载到 SubtitleCache 已实现；本轮 autoplay 返回主页，画面**未验证** |
| `swift test` | **27/27 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| visionOS runtime | 下载约 **74.0%**，未安装 |

证据：`Evidence/53-ios-webdav-seek-subtitle.jpg`、`reports/m4m-seek-jfsubs.txt`。

## 可复现差异与未验证

1. **Jellyfin 外挂字幕本轮未验证**：下载代码/夹具已加，但 autoplay 未打开播放器；需修选择/返回主页逻辑。
2. **Jellyfin 内嵌字幕仍由 AVKit 处理**；未接自绘。
3. **音频未听测**。
4. **visionOS runtime 未安装**，仅构建。
5. **CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率**未做。
6. **ASS 样式/字体覆盖**仍无移动端 libass。

## 下一项

M4n：Jellyfin 外挂字幕播放验证/失败分支、音频听测、visionOS runtime、CloudKit/Trakt、M3 T07/WebDAV MKV 分辨率。
