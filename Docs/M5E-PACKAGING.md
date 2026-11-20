# M5e 验收记录：macOS 自包含打包

日期：2026-11-20。分支：`m5e-self-contained`。基线：Infuse 8.5.10（参照客户端待装）。

此前 `OpenFuse.app` 在运行时链接 `/opt/homebrew/opt/mpv/lib/libmpv.2.dylib`，离开 brew 环境无法启动。现在把 libmpv 及非系统依赖复制进 `Contents/Frameworks`，改写为 `@rpath`，重签并验证；打包后实际播放 MKV 成功。

## 交付内容

- `Tools/bundle_runtime.py`：递归解析绝对 Homebrew 与 `@rpath`/`@loader_path` 依赖，复制 50 个 dylib，改 install name，加 `@executable_path/../Frameworks` rpath，逐库签名。
- `Scripts/bundle-runtime.sh`：先重建 app（保证依赖为绝对路径），再打包、`codesign --verify --deep --strict`、检查无 `/opt/homebrew`。
- `Scripts/package-app.sh`：生成 `build/OpenFuse-macOS-self-contained.zip`，`unzip -t` 校验。
- 删除可执行文件里过期的 Homebrew rpath。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| Frameworks | **50 个 dylib**，含 libmpv.2、libavcodec.63、libass.9 |
| App 体积 | **67 MB**；zip **27 MB** |
| lsof | libmpv/libavcodec/libass 均从 `Contents/Frameworks` 加载 |
| `/opt/homebrew` 加载数 | **0** |
| codesign verify deep strict | 通过（ad-hoc） |
| 播放 | MKV 60s，位置 4.583s，HEVC Main 10，E-AC-3 6ch，CoreAudio |
| `swift test` | **28/28 通过** |
| 五端/device 构建 | 既有构建通过；本轮无 Swift 代码改动 |

证据：`Evidence/62-self-contained-playback.jpg`、`reports/m5e-packaging.txt`。

## 可复现差异与未验证

1. **未公证/未分发**：ad-hoc 签名，Gatekeeper 在另一台 Mac 可能拦截；无 Developer ID/notary。
2. **仅 arm64**：未验证 Intel/Universal；Homebrew 构建机仍需要 mpv 才能打包。
3. **未在无 Homebrew 的干净机器启动**；通过 install-name/lsof 证明不加载 brew。
4. **音频未听测**；HEVC/EAC3 解码路径已在打包 app 中跑通。
5. **Emby/SMB、HDR/AirPlay、CloudKit/Trakt、Plex 直连浏览/音轨/版本**未做。
6. **M3 T07/WebDAV MKV 分辨率**未做。

## 下一项

M5f：Developer ID/公证、Universal；Plex 直连浏览/音轨/版本；Emby；SMB；HDR/AirPlay；CloudKit/Trakt；音频听测；M3 尾项。
