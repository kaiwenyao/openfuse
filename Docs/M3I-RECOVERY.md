# M3i 验收记录：WebDAV 目录超时恢复

日期：2026-11-20。分支：`m3i-recovery`。基线：Infuse 8.5.10（参照客户端待装）。

T07 要求扫描中断/超时不丢失旧内容。本轮让 WebDAV scanner 在单个目录 PROPFIND 失败（504/超时）时继续扫描其他目录，并在替换媒体库时保留失败目录下的旧作品；其他目录正常刷新。

## 交付内容

- `ScannedLibrary.failedPaths`：记录本次扫描失败的目录。
- `LibraryScanner.scanWebDAV`：`client.list` 异常时记录路径并继续，不再整次抛错；取消仍立即抛出。
- `LibraryStore.replace(source:preservingRemotePrefixes:)`：
  - 查询该源下 episodes 的 remote_path 是否落在失败前缀；
  - 保留这些 work，其余照常删除；随后 upsert 新扫描结果；
  - 所有目录失败时等价于保留整源。
- AppModel：WebDAV 扫描使用 failedPaths 保留策略，状态显示「N 个目录失败，已保留旧条目」。
- 夹具：`webdav_fixture.py --fail-path PATH`，匹配目录 PROPFIND 返回 504。
- 测试：`Scripts/test-webdav-recovery.sh`；另加 LibraryStore 保留前缀单元测试。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 初始扫描 | 2 作品 / 2 集 |
| 失败目录 | `Shows/示例剧` PROPFIND 504（日志确认） |
| 失败后重扫 | **2 作品 / 2 集**，状态「5 个目录失败，已保留旧条目」 |
| 保留内容 | 《示例剧 · WebDAV NFO》仍在；电影正常刷新 |
| `swift test` | **26/26 通过**（新增保留前缀测试） |
| iOS/iPadOS、tvOS、visionOS | **BUILD SUCCEEDED** |
| iOS device Release | **BUILD SUCCEEDED** |
| Mac 构建 | 成功 |

输出：

```
PASS: WebDAV 504 directory kept old works; other works rescanned
```

证据：`reports/m3i-recovery-base.json`、`reports/m3i-recovery-failed.json`、`reports/m3i-webdav-recovery.txt`。

## 可复现差异与未验证

1. **仅目录级失败恢复**；单个文件 404/解析失败、海报/NFO 下载失败不回滚。
2. **无重试/退避**；失败目录直接跳过，下一次全量扫描再试。
3. **Jellyfin/本地扫描没有等价恢复**；Jellyfin 单页失败仍中止。
4. **未测扫描中播放、断点恢复、重启后只更新目标条目**；T07 仍部分完成。
5. **真实 OpenList/百度网盘超时行为未验证**；夹具只有 504。
6. **移动 runtime 仍未启动**；iOS runtime 下载约 91%。
7. **Mac M3 尾项**：画质元数据补全；T07 其他场景。

## 下一项

M4g：runtime 完成后三端实际启动/截图；字幕/音轨、真实 Jellyfin HLS 参数、tvOS/visionOS 远程来源、CloudKit/Trakt；M3 T07 其他场景/画质元数据。
