# M2c 验收记录：真实 OpenList WebDAV

日期：2026-11-20。分支：`m3s-remote-corrupt` 后续（M2c）。基线：Infuse 8.5.10（参照客户端待装）。

此前 OpenList 只用 Python WebDAV 夹具。本轮用官方 OpenList Docker 镜像 + Local 存储，按真实 `/dav` 登录、扫描、播放、seek、Range、远程字幕全链路验证。百度网盘存储/账号仍未提供。

## 交付内容

- `Scripts/run-openlist-acceptance.sh`：
  - 起 `openlistteam/openlist:latest`，`OPENLIST_ADMIN_PASSWORD=test`；
  - API 登录 token + 创建 Local 存储；
  - 放入 1080p MP4 + 简中 SRT；
  - OpenFuse 添加 `http://127.0.0.1:5244/dav/`，扫描、播放、seek、Range 断言。
- 实测截图与库/播放报告。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| OpenList | Docker 最新镜像，数据卷 + Local 存储 |
| WebDAV 扫描 | 1 作品，`1080p · WebDAV`，contentKey |
| 播放/seek | seek 10 → **11.022s / 20.041s** |
| 远程字幕 | 自动选中远程 zh-Hans SRT |
| Range | HTTP **206**，0-1023/3533564 |
| 截图 | t=15s，双语字幕同步 |
| 脚本 | `Scripts/run-openlist-acceptance.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 百度网盘/真实云跳转 | 待验证 |

证据：`Evidence/95-openlist-real.jpg`、`reports/m2c-openlist-library.json`、`reports/m2c-openlist-play.json`、`reports/m2c-openlist-real.txt`。

## 可复现差异与未验证

1. **未接百度网盘账号**；OpenList 的云存储 302/限流/签名跳转未验证。
2. **HTTP 本地 Docker**；真实 OpenList HTTPS/反代/CORS 未验证。
3. **移动端 OpenList** 未跑；Mac 已验证。
4. **音频听测、HDR 测量、真实 SMB3/Trakt、CloudKit、visionOS 真机**未完成。

## 下一项

M2d/M6d：百度网盘账号/OpenList 云跳转；移动 OpenList；真机 visionOS；音频听测；HDR 测量；真实 SMB3/Trakt；CloudKit。
