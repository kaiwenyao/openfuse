# macOS 首版验收：WebDAV 与 Jellyfin

日期：2026-11-20。范围仅 macOS 客户端。复现基线：仓库 `main` + 本轮改动；Infuse 8.5.10（build 8.5.5815）已安装但未用于自动对比。

## 交付物

| 产物 | 路径 |
| --- | --- |
| 可双击启动的应用 | `build/OpenFuse.app` |
| 自包含 zip（内嵌 50 个 dylib） | `build/OpenFuse-macOS-self-contained.zip` |
| 构建 | `Scripts/build-app.sh [release]` |
| 打包 | `Scripts/package-app.sh` |
| 单测 | `swift test` |

```bash
brew install mpv                 # libmpv 0.42.0
Scripts/build-app.sh             # -> build/OpenFuse.app
open build/OpenFuse.app
Scripts/package-app.sh           # -> build/OpenFuse-macOS-self-contained.zip
```

`Package.swift` 现在只在检测到 `/opt/homebrew/include/smb2/libsmb2.h` 或 `OPENFUSE_SMB2=1` 时编译 `CSMB2` 并定义 `OPENFUSE_SMB2`；`SMBClient`/`SMBLibraryScanner` 在未启用时提供抛错桩。WebDAV/Jellyfin 构建不再要求 libsmb2，原有 SMB 构建方式保留（`OPENFUSE_SMB2=1 Scripts/build-app.sh`，需先运行 `Scripts/install-libsmb2.sh`）。

## 自动化结果

```
swift test
Executed 45 tests, with 0 failures
```

新增/覆盖：

- `JellyfinPaginationTests`
  - 501 个直接子项：3 页（0/200/400），返回 501 项，最后一项 `ep-500` 可解析。
  - 5001 个递归条目：返回 5001 项，最后一项 `ep-5000`。
  - 中间页 HTTP 500：扫描结果标记 `hasTransientFailure`，不产出可替换索引；重试成功后 501 个作品全部返回。
  - 单库 401：标记为 `revokedLibraryNames`，不按临时失败处理。
  - 分页中途取消：抛出 `LibraryScanError.cancelled`。
- `ResumeMerge`：服务器较新的 5:00 重看位置优先于本地较早的 40:00；本地时间更新的记录仍优先。
- `PlaybackStore.mergeRemotePosition`：旧服务器时间不覆盖本地新记录。
- `WebDAVListFilterTests`：PROPFIND depth=1 的自身目录项被过滤，深层目录不会出现“进入自己”。
- `JellyfinSubtitleURLTests`：没有 `DeliveryUrl` 的外挂字幕回退到 `/Videos/{item}/{source}/Subtitles/{index}/Stream.ass`，生成绝对 URL 并带 `api_key`。
- 末尾保护从固定 10 秒改为 `min(10, 5% 时长)`，60 秒样片 45 秒处仍可续播。

## 实际窗口操作

### WebDAV

1. 首页「添加来源」→ 填 `http://127.0.0.1:8088/`、`openfuse/openfuse` → 连接并保存。
2. 「浏览」→ `Movies` → `OpenFuse Fixture (2026)` → 播放 `OpenFuse Fixture (2026).mkv`。
3. 播放器默认选到外挂 `中文（简体）(ASS)`；字幕菜单切到 `中文（繁體）(ASS)`，画面出现「第四句：接近片尾，用於驗證末尾拖動。」
4. 三次拖动：8.9s、27.0s、45.3s；27s 处显示「第三句：繁體中文字幕軌道，拖動後應重新同步。」，45s 处显示第四句。
5. 返回：回到 `Local WebDAV / Movies / OpenFuse Fixture (2026)`，文件与两个字幕仍在列表中，而不是回首页。
6. 本地记录：`position=45.875`、`preferredSubtitleTrackID=remote:...zh-Hant.ass`；首页「继续观看」显示 00:45。
7. 从首页继续观看重新打开：从约 45s 开始，仍选中 `中文（繁體）(ASS)`，音轨 E-AC-3 5.1。

### Jellyfin

1. 首页「Jellyfin」→ `http://127.0.0.1:8096`、`test/test` → 登录并保存。
2. 电影库：`Movies` → `OpenFuse Fixture (2026)` → 版本 `MKV · 直连` → 播放。
3. 字幕菜单列出 `中文（简体）(ASS)`、`中文（繁體）(ASS)`（服务器外挂字幕）和内置 `中文（简体）·中日双语 - Chinese - ASS`；选繁体后 45s 画面显示繁体第四句。
4. 退出后服务器 `UserData.PlaybackPositionTicks=449580000`（44.958s，74.93%），`Played=false`；再退出一次在 19.375s 处写回 `193750000`（32.29%）。
5. 电视剧库：`TV` → `OpenFuse Show` → `Season 1` → `OpenFuse Show S01E01` → 播放；标题、E-AC-3 5.1、外挂 ASS 均正确。退出回到 `Home Jellyfin / TV / OpenFuse Show / Season 1`。
6. 跨设备重看：把服务器位置改为 5s（`Sessions/Playing/Stopped`，更新的 `LastPlayedDate`），本机记录仍在 45s/已看完；重新打开后从约 5s 开始（截图时 8.625s），未被本地较晚但更靠后的位置覆盖。
7. 首页「继续观看」的 Jellyfin 卡恢复到 45s 并选中繁体轨道。

## 截图与报告

- `Docs/Evidence/mac-first/01-home.jpg`：三张续播卡、两个来源、2 作品/2 集。
- `03-webdav-zh-hant-45s.jpg`：WebDAV 45s、繁体 ASS、E-AC-3 5.1。
- `04-jellyfin-zh-hant-45s.jpg`：Jellyfin 45s、外挂繁体 ASS。
- `05-jellyfin-episode.jpg`：剧集播放与轨道。
- `06-jellyfin-return.jpg`、`07-webdav-return.jpg`：退出后的原目录位置。
- `episode-seek-report.json`、`movie-seek-report.json`：`position=30.5/45.25`、`selectedSubtitle=jellyfin-sub:...:1`、`audioChannels=6`、`videoCodec=hevc / Main 10`。
- `library-counts.txt`：`jellyfin 2 works/2 episodes`、`webdav 2 works/2 episodes`。

## 本机测试服务

```bash
# WebDAV（Python，PROPFIND depth 0/1、Range、Basic auth）
python3 Tools/webdav_fixture_server.py \
  --root build/mac-first/webdav --port 8088 --user openfuse --password openfuse

# Jellyfin 12.4.0
docker run -d --name openfuse-jellyfin -p 8096:8096 \
  -v "$PWD/build/mac-first/jellyfin/config:/config" \
  -v "$PWD/build/mac-first/jellyfin/cache:/cache" \
  -v "$PWD/build/mac-first/jellyfin/media:/media" \
  jellyfin/jellyfin:latest
```

Jellyfin 测试库：`Movies=/media/Movies`、`TV=/media/TV`，用户 `test/test`，`MinResumeDurationSeconds=0`。

样片由 `Scripts/make_fixtures.sh` 生成：HEVC Main 10 1920×1080、E-AC-3 5.1 448k、内置简体 ASS + 同名 zh-Hans/zh-Hant 外挂 ASS，60 秒。

## 凭据处理

本机为 ad-hoc 签名开发构建。macOS 对未稳定签名的应用读取 Keychain 会弹出登录密码框，实际会卡住首页海报加载。因此默认把来源凭据写入 `~/Library/Application Support/OpenFuse/credentials.json`（`0600`），Keychain 仅在 `OPENFUSE_KEYCHAIN=1` 时启用。正式签名分发时应改回 Keychain 默认并删除该文件。

## 尚待验证

1. **OpenList/百度网盘**：没有可用账号；本轮 WebDAV 用本地 Python DAV 服务，未复验签名链接变化与百度目录。
2. **Jellyfin HTTPS/反代**：本机为 HTTP 直连，未配置证书或反向代理。
3. **真实超大库**：501/5001 用 URLProtocol 合成响应验证，未在 5001 条真实 Jellyfin 库上跑。
4. **人耳听音**：只验证解码为 E-AC-3 5.1/6ch、默认输出设备与播放无报错；未做人工听感或声道定位。
5. **Infuse 8.5.10 对照**：已安装，但本轮未逐项对照其选轨、返回与续播；以 OpenFuse 实际窗口结果为准。
6. **SMB 构建**：本机未安装 libsmb2，未回归 `OPENFUSE_SMB2=1` 的 SMB 路径；WebDAV/Jellyfin 构建已验证不依赖它。
7. **Docker 代理**：为拉取 `jellyfin/jellyfin` 将 Docker Desktop 代理从失效的 `localhost:7897` 临时改为系统代理；Jellyfin 容器仍在运行。
