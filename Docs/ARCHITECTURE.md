# OpenFuse Mac 实现说明（M1）

## 目标与边界

当前只做 Mac 本地文件播放。媒体库、远程来源、设置页尚未接入，接口位置在下面标出。所有播放验收以 `Fixtures/generated/openfuse-fixture.mkv` 为准。

## 目录

```
Package.swift
Sources/
  CMpv/                 libmpv C 模块（systemLibrary）
  OpenFuseCore/         模型、字幕发现、续播存储、libmpv 封装、OpenGL 视图
  OpenFuseApp/          SwiftUI 应用、首页、播放器、测试参数
  openfuse-probe/       无窗口探针，AVPlayer / libmpv 对照
Tests/OpenFuseCoreTests 字幕发现、语言标签、续播策略
Scripts/
  make_fixtures.sh      生成并校验测试片
  build-app.sh          组装 build/OpenFuse.app
  Info.plist
Tools/
  gen_frames.swift      逐帧生成时间码画面
  gen_audio.py          生成 6 声道报号
  gen_subtitles.py      生成简繁/无标签/缺字体 ASS
  analyze_audio.py      Goertzel 声道校验
  window_capture.swift  列出窗口 ID（截图受系统权限限制）
Docs/                   决策、素材、验收、证据
```

## 数据与会话

- `MediaFingerprint`：路径 + 大小 + mtime；路径作为续播键，替换文件仍保留进度。
- `SubtitleCatalog`：发现同主名和 `Subs/` 下的字幕，解析 `zh-Hans`/`zh-Hant`/`zh_TW`/`jpn` 等标记，拒绝不匹配主名或含未知段的文件。
- `PlaybackStore`：`~/Library/Application Support/OpenFuse/playback.json`，原子写入，按路径保存位置、时长、已看状态、音轨/字幕偏好。`ResumePolicy`：小于 5 s 不续播、距结尾 10 s 内不续播、95% 记为已看。
- `PlayerModel`：一次播放会话。负责选轨、保存、关闭；`MPVEngine` 只做 mpv 生命周期与命令。

## 播放启动顺序（关键）

1. SwiftUI 创建 `PlayerView` → `MPVGLView`。
2. `prepareOpenGL` 建立 GL 上下文并调用 `mpv_render_context_create`，成功后通知引擎。
3. `PlayerModel` 只有拿到 render context 才 `loadfile`。否则 mpv 会永久报 `vo/libmpv: No render context set.`，表现为黑屏、只有声音。
4. 文件加载后添加外挂字幕，刷新轨道，延迟约 1–2 s 等所有外挂轨就绪，再应用保存的轨道或 `zh-Hans` 默认。
5. 退出时保存位置并销毁 render context / mpv handle；下次打开由 `ResumePolicy` 决定起播点。

渲染由 `MPVGLView.draw` 驱动：mpv render API 输出到默认 FBO，`flushBuffer` 上交。测试抓帧在同一 `draw` 中 `glReadPixels`，因此反映真实输出而非外部抽帧。

## 线程

- mpv 事件循环在独立串行队列，`mpv_wait_event` 200 ms 超时。
- 属性变化通过 `DispatchQueue.main` 回到 UI；`time-pos` 限流 20 Hz。
- 命令加锁；`shutdown` 等待事件线程退出后再销毁 handle。
- Swift 5 语言模式以减少 C 回调与旧 AppKit 的迁移噪声；后续可评估 Swift 6 严格并发。

## 远程来源（M2 WebDAV 已实现）

- `WebDAVSource`：名称、根 URL、用户名；id 由 URL+用户名哈希；`sources.json` 持久化，密码存 Keychain。
- `WebDAVClient`（actor）：`list(path)` PROPFIND Depth 1、`stat(path)` Depth 0、`fetch(path, range)`；Basic auth；解析 XML 的 `displayname/resourcetype/getcontentlength/getcontenttype/getlastmodified/getetag`；路径按段编码/解码。
- `RemoteEntry`：path、name、url、isDirectory、size、contentType、modifiedAt、etag。
- `WebDAVClient.subtitleTracks(for:siblings:)`：复用本地匹配规则，构造 URL 型 `SubtitleTrack`，id 前缀 `remote:`。
- `MediaItem`：统一本地/远程；远程 fingerprint 键为 `webdav://<sourceID>/<path>`，HTTP 头（Basic）注入 libmpv；`PlaybackRecord` 增加 sourceKind/sourceID/remotePath/remoteURL。
- UI：首页来源卡片 + 添加来源表单；`WebDAVBrowserView` 面包屑/列表/错误重试；打开视频时先取同目录条目再发现字幕。

**安全注意：** 凭据作为 mpv `http-header-fields` 全局注入，跨域 302 时可能被转发。接真实 OpenList 前需改成本机代理，只在 origin 附带 Authorization。Keychain 首次读取可能弹系统授权，自动化用 `OPENFUSE_WEBDAV_PASSWORD` 覆盖。

## 远程来源接口（Jellyfin 预留）

播放器只依赖 URL 与轨道描述。M2 计划：

```swift
protocol MediaSource {
    var id: String { get }
    func list(path: String) async throws -> [RemoteEntry]
    func stat(path: String) async throws -> RemoteFile
    func openRange(path: String, offset: Int64, length: Int64) async throws -> Data
    func subtitleCandidates(for path: String) async throws -> [RemoteSubtitle]
}
```

WebDAV 需要保留 Unicode/百分号往返，校验 206 与 `Content-Range`，拖动时取消旧预读；Jellyfin 需要 Direct/Library 两种模式、PlaybackInfo 选版本与进度回写。它们都只替换“取流/列目录”，不改变 `PlayerModel` 的轨道与续播逻辑。

## 测试

`swift test` 覆盖纯逻辑；`openfuse-probe` 覆盖引擎；应用内参数（`--open`、`--freeze-at`、`--capture`、`--report`、`--reopen-test`、`--fullscreen`）覆盖端到端。所有报告写到指定路径，便于 CI 收集。

## 待办

M2：WebDAV/OpenList、Jellyfin、Range/缓存/重连、远程字幕、进度回写。
M3：SQLite 库、TMDB、聚合首页、详情、搜索、增量扫描。
M4：CloudKit/Trakt、iPhone/iPad/tvOS。
M5：SMB/Plex/Emby、HDR、投屏、下载、打包与权益。
M6：visionOS 与全矩阵验收。
