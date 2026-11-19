# M2a 验收记录：WebDAV / OpenList 远程来源

日期：2026-11-19。分支：`m2-remote-sources`。基线：Infuse 8.5.10（本机未安装，参照对照待采样）。

本轮打通「添加 WebDAV 来源 → 按真实目录浏览 → 直接播放 → 远程外挂字幕 → 拖动 → 退出续播」的第一条远程路径。真实 OpenList + 百度网盘账号没有提供，协议层与播放链路先用仓库内的本地 WebDAV 夹具验证；真实服务标记为「待验证」。

## 交付内容

- **添加来源**：首页「添加来源」表单，填写名称、服务器地址、用户名、密码；先 `PROPFIND` 验证再保存。元数据写入 `sources.json`，密码写入 Keychain（`com.openfuse.webdav` / source id）。自动化测试可用 `OPENFUSE_WEBDAV_PASSWORD` 临时覆盖，密码不进入日志、报告或 URL。
- **目录浏览**：WebDAV `PROPFIND Depth: 1`，解析 `displayname`、`resourcetype`、`getcontentlength`、`getlastmodified`、`etag`；文件夹优先、本地化排序；面包屑、返回、刷新、错误与重试。
- **路径处理**：Unicode、空格、括号、百分号按段编码；`100% 测试`、`电影/...` 往返一致；服务端 href 百分号解码后再相对化。
- **远程播放**：libmpv 直接打开 HTTP(S) URL；Basic 凭据通过 `http-header-fields` 注入；HEVC Main 10 仍走 VideoToolbox，E-AC-3 5.1 正常解码。
- **远程外挂字幕**：播放时列出同目录条目，用与本地相同的匹配规则发现 `.ass`，`sub-add` 远程 URL；简繁切换、字体回退、拖动后同步与本地一致。
- **Range 与拖动**：服务端支持 `Range`/206；拖动时 mpv 会取消旧 GET 并从中段重新请求。夹具服务端记录请求，验收脚本据此断言。
- **续播**：记录键为 `webdav://<sourceID>/<path>`，保存位置、音轨/字幕偏好、来源类型与远程路径；首页「继续观看」卡片点击后按 source id 找到来源并重开。
- **本地夹具**：`Tools/webdav_fixture.py`，Basic auth、PROPFIND、GET/HEAD、单段 Range、416、请求日志、可限速；目录结构与测试片同名外挂字幕。

## 架构

```
BrowserView ──PROPFIND──> WebDAVClient(actor) ──> URLSession (Basic auth)
    │                           │
    │                           └─ Range probe / stat / list
    └── openRemote(entry) ──> MediaItem(webdav) ──> PlayerModel ──> libmpv
                                   │                              └─ http-header-fields
                                   └─ subtitles from sibling listing
```

- `WebDAVClient` 只做协议：列目录、stat、单段 Range 读取；不把整文件读入内存。
- `MediaItem` 统一本地与远程：播放 URL、续播 fingerprint、字幕目录、HTTP 头、来源标识。
- `PlayerModel` 不再假设 URL 是本地文件；`sub-add` 对远程 URL 使用绝对地址；外部字幕匹配同时接受 URL 与本地路径。
- 播放会话仍然“先有 render context 再 loadfile”；远程文件加载较慢时，拖动请求会排队到 duration 可用后执行，避免 mpv 命令失败。

## 复现

```bash
# 1. 协议层：PROPFIND、Unicode、Range、401
Scripts/test-webdav.sh

# 2. 端到端：远程播放 + 远程 ASS + 限速 Range 拖动 + 首页续播
Scripts/run-webdav-acceptance.sh
```

脚本会自行启动 `Tools/webdav_fixture.py`（默认端口 8101/8103/8104），构建应用并用隔离的 `OPENFUSE_SUPPORT_DIR`、`OPENFUSE_WEBDAV_PASSWORD=test` 运行，产物在 `build/`。

手工启动夹具：

```bash
python3 Tools/webdav_fixture.py --setup --port 8099
# http://127.0.0.1:8099/dav/  test / test
```

真实 OpenList：服务器地址填 OpenList 的 `.../dav/`，用户名/密码使用独立测试账号；当前实现未验证百度网盘的跳转与限流。

## 实测结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | 13/13 通过（新增 WebDAV XML、路径编码、远程字幕、远程进度字段） | 终端 |
| 协议探针 | PROPFIND 列目录、Unicode `100% 测试`、3 份外挂、Range 206、MKV magic `1a45dfa3` | `Scripts/test-webdav.sh` 输出 |
| 401 | 错误密码被拒绝 | 同上 |
| 远程播放 | 60.000 s，HEVC Main 10，`hwdec=videotoolbox`；远程 `zh-Hans` 自动选中 | `reports/m2-webdav-play.json`、Evidence 09 |
| 远程简繁 | 9.917 s 选中 `remote:...zh-Hant.ass` | `reports/m2-webdav-zh-hant.json`、Evidence 10 |
| 远程拖动 | 限速 700 KB/s：首个 GET 在 9,175,040 字节处取消，新请求从 14,531,875 / 17,653,872 字节继续；冻结在 41.042 s | `reports/m2-webdav-range-log.jsonl`、`m2-webdav-seek.json`、Evidence 11 |
| 远程续播 | 保存 25.083 s；重开从 25.08 继续，6 s 后 30.583 s，字幕偏好保留 | `reports/m2-webdav-resume.json` |
| 目录 UI | 根目录 Movies / Shows 可浏览，显示来源名与地址 | Evidence 07 |
| 首页来源 | 来源卡片、浏览/移除、添加来源入口 | Evidence 08 |

端到端脚本的实际末尾输出：

```
PASS: remote playback + remote ASS, Range seek (3 GETs), resume 25.083s
```

## 可复现差异与未验证

1. **真实 OpenList / 百度网盘未验证。** 没有提供账号，只用本地 WebDAV 夹具；登录、限流、令牌过期、签名跳转、目录规模都待实测。
2. **重定向凭据风险。** mpv 的 `http-header-fields` 是全局 HTTP 头；如果 OpenList 返回跨域 302 到百度/CDN，Authorization 可能被带到目标主机。正式接真实服务前要改为本机代理，只在 origin 注入凭据，并逐跳校验。当前夹具无重定向。
3. **Keychain 首次授权。** ad-hoc 签名的构建每次 CDHash 变化，读取旧密码会触发系统授权；自动化用环境变量绕过。缺少超时/提示 UI，真实用户第一次点击来源时可能等待系统弹窗。待做：后台读取 + 明确提示 + “重新输入密码”。
4. **目录规模与性能。** `PROPFIND Depth: 1` 一次列全目录，没有分页/虚拟滚动；大目录的首屏与内存未测。首帧、拖动 P95 尚未做 20 次统计；限速测试只证明路径和取消行为。
5. **缓存与重连。** 没做磁盘缓存、断线重连、预读策略；mpv 自身缓冲之外没有应用层控制。
6. **HTTPS 证书。** 只信任系统信任链；自签名 OpenList 会失败，未提供忽略证书选项（避免默认不安全）。
7. **海报库。** 远程条目仍以文件夹浏览呈现；电影/剧/季/集海报库属于 M3，尚未实现。
8. **服务端进度。** WebDAV 没有观看进度 API，进度只在本机 `playback.json`；Jellyfin 回写留到下一项。
9. **UI 参照。** Infuse 未安装，目录/添加来源页面的坐标、字号、默认值没有同机对照。
10. **窗口截图限制。** 浏览器/首页截图来自应用自身 `cacheDisplay`；播放器视频层仍用渲染帧单独取证。

## 下一项

Jellyfin：Direct Mode 登录与视图/条目、PlaybackInfo 选版本与直链/转码、保留服务器片名/封面/轨道、进度上报；随后 Library Mode 与海报库在 M3 接入。真实 Jellyfin 账号同样先用本地夹具（可用 Docker/独立测试实例）验证协议，缺账号的组合标「待验证」。
