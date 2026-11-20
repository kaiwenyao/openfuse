# M2i 验收记录：Jellyfin 用户权限隔离

日期：2026-11-20。分支 `m2i-jellyfin-permissions`。基线 Infuse 8.5.10（参照客户端待装）。

M2h 验证了位置隔离。本轮验证媒体库权限：test2 无任何库时 OpenFuse 扫描为 0，不泄漏；恢复权限后扫描到 2 个作品。

## 交付内容

- `Scripts/run-jellyfin-permissions.sh`：读取 test2 Policy，限制 `EnableAllFolders=false/EnabledFolders=[]`，扫描断言 0；恢复后断言 ≥2。
- 恢复策略在脚本中执行，避免污染测试服。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 受限 test2 | rawWorks **0** |
| 恢复后 test2 | rawWorks **2**（OpenFuse Jellyfin / MKV） |
| 脚本 | `Scripts/run-jellyfin-permissions.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| UI 用户切换/并发/HTTPS | 待验证 |

证据：`reports/m2i-jellyfin-restricted.json`、`m2i-jellyfin-allowed.json`、`m2i-jellyfin-permissions.txt`。

## 可复现差异与未验证

1. **UI 没有用户切换**；通过独立来源/support 验证。
2. **每文件夹 ACL/并发会话/HTTPS**未测。
3. **音频听测、HDR 测量、真实 Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

M2j/M6d：Jellyfin UI 用户切换/并发/HTTPS；SMB 多GB/DFS；音频听测；HDR 测量；真实 Trakt/CloudKit；visionOS 真机。
