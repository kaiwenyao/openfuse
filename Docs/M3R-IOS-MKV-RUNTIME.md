# M3r 验收记录：iOS 运行期远程 MKV 解析

日期：2026-11-20。分支：`m3r-ios-mkv-runtime`。基线：Infuse 8.5.10（参照客户端待装）。

M3q 只验证了 macOS 强制 parser + iOS 构建。本轮在 iPhone 18 Pro 模拟器实际启动，使用 `OPENFUSE_TEST_WEBDAV_*` 扫描 WebDAV HDR MKV，直接查沙盒 SQLite 验证 resolution/dynamic_range，并截图。

## 交付内容

- 验收脚本 `Scripts/run-ios-mkv-runtime.sh`：启动 WebDAV fixture、构建/安装/启动模拟器、读取 app 容器 SQLite、截图。
- 不新增产品代码；验证 M3q 的 parser 在 iOS 运行期生效。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设备 | iPhone 18 Pro 模拟器 / iOS 27.2 |
| WebDAV 版本 | `1080p · WebDAV` |
| resolution | **1080p** |
| dynamic_range | **HDR10** |
| 截图 | iPhone 库可见 WebDAV 作品 |
| 脚本 | `Scripts/run-ios-mkv-runtime.sh` PASS |
| `swift test` | **31/31 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |

证据：`Evidence/90-ios-mkv-runtime.jpg`、`reports/m3r-ios-mkv.txt`。

## 可复现差异与未验证

1. **只测夹具**；真实 OpenList/百度网盘目录/大头部未测。
2. **前 2MB 之后 Tracks** 仍会失败。
3. **畸形 EBML** 未测。
4. **音频仍只验证 PCM/downmix，未扬声器听测**。
5. **HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit**未做。

## 下一项

EDR HDR 直通已在 [M5ab 验收](Docs/M5AB-HDR-PASSTHROUGH.md) 完成参数验证。剩余 M5ac：Metal/EDR 渲染与测量、音频听测/设备路由、SMB/WebDAV 指纹、真实 SMB3/Trakt、AirPlay、CloudKit、真实 OpenList。
