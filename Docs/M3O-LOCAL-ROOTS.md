# M3o 验收记录：多根本地库

日期：2026-11-20。分支：`m3o-local-roots`。基线：Infuse 8.5.10（参照客户端待装）。

本地扫描此前每次只处理一个目录，没有根目录列表/管理。现在持久化 `local-roots.json`，每个根独立 sourceID（路径哈希），可扫描全部、单独移除；作品/集按原有合并规则聚合。

## 交付内容

- `LocalRoot` / `LocalRootStore`（JSON 持久化、upsert/remove）。
- AppModel `localRoots`；`addLocalRoot`、`scanAllLocalRoots`、`removeLocalRoot`。
- `--scan-local` 自动登记根；`--remove-local-root` 测试钩子。
- 扫描菜单：添加并扫描、扫描全部本地根目录、移除根目录。
- 验收脚本 `Scripts/run-local-roots.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 两根本地库 | rawWorks=2，Alpha Movie + Beta Movie |
| 移除 B | rawWorks=1，仅 Alpha Movie |
| 根目录持久化 | `local-roots.json` 剩余 1 个根 |
| 脚本 | `Scripts/run-local-roots.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |

证据：`reports/m3o-local-roots.json`、`reports/m3o-local-roots-store.json`、`reports/m3o-local-roots.txt`。

## 可复现差异与未验证

1. **跨根重复文件**按标题合并，但版本仍保留两条；未按文件内容去重。
2. **无目录监听/自动重扫**；需手动扫描。
3. **SMB/WebDAV 损坏过滤**未做。
4. **音频听测、HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit**未做。

## 下一项

跨根内容去重已在 [M3p 验收](Docs/M3P-LOCAL-DEDUPE.md) 完成。剩余 M3q/M5z：全文件/抽样哈希策略、SMB/WebDAV 指纹/损坏过滤、音频听测、HDR 直通、真实 SMB3/Trakt、AirPlay、CloudKit。
