# M5f 验收记录：Emby 来源

日期：2026-11-20。分支：`m5f-emby`。基线：Infuse 8.5.10（参照客户端待装）。

Emby 与 Jellyfin 使用同一套 HTTP API。`JellyfinSource` 增加 `serverKind`（jellyfin/emby），扫描入库与播放 sourceKind 跟随 kind；UI 的添加来源表单可在 Jellyfin/Emby 间选择，CLI 加 `--emby-*`；直接浏览页显示 Emby Direct。

## 交付内容

- `JellyfinSource.serverKind` + `kind`；ID 材料包含 kind；旧 Jellyfin 来源保持默认。
- `scanJellyfin` 返回 sourceKind=kind，电影/剧/集均标记 emby。
- `MediaItem` 播放上下文的 `serverKind` 决定 `sourceKind`；续播键 `emby://`。
- AppModel `addJellyfinSource(serverKind:)`；播放/重开 Recent 支持 emby。
- UI：AddJellyfinSheet 类型选择；Emby Direct 浏览标题。
- CLI：`--emby-url/-user/-pass/-name/-scan`；`OPENFUSE_EMBY_*` 测试凭据。
- 验收脚本 `Scripts/run-emby-acceptance.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 添加/扫描 | **2 作品/3 集**，全部 sourceKind=emby |
| 直接浏览 | Emby Direct 电影库/电视剧库渲染 |
| 库播放 | sourceKind=emby，第 1 集，冻结 **9.917s** |
| `swift test` | **28/28 通过** |
| iOS/iPadOS、tvOS、visionOS、device | 全部 **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |
| 真实 Emby | **待验证**：使用 Jellyfin 兼容夹具 |

证据：`Evidence/63-emby-library.jpg`、`64-emby-playback.jpg`、`reports/m5f-emby-*`、`reports/m5f-emby.txt`。

## 可复现差异与未验证

1. **真实 Emby 未验证**：版本差异、鉴权头、token 生命周期、转码参数。
2. **Emby 进度回写未单独验证**：复用 Jellyfin 上报路径，未看服务器日志。
3. **Emby 与 Jellyfin 聚合去重**：同服务器同内容可能双重条目，未处理。
4. **SMB、HDR/AirPlay、CloudKit/Trakt、音频听测、M3 尾项**未做。
5. **Plex 直连/音轨/版本**仍缺。

## 下一项

M5g：真实 Emby/Jellyfin 验证、聚合去重；Plex 直连/音轨/版本；SMB；HDR/AirPlay；CloudKit/Trakt；音频听测；M3 尾项。
