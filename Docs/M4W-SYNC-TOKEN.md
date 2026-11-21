> **0.7.0 已移除该功能。** 本文仅保留历史设计记录；应用不再提供进度同步入口、环境变量或凭据读取。

# M4w 验收记录：同步服务 Bearer token

日期：2026-11-20。分支 `m4w-sync-token`。基线 Infuse 8.5.10（参照客户端待装）。

M4u 的 HTTP 进度服务无鉴权。本轮给 HTTP transport 加 Bearer token，Mac/iPhone 通过 `OPENFUSE_SYNC_TOKEN` 配置；fixture 强制校验，并做无 token 401 负测。

## 交付内容

- `HTTPProgressTransport(url:token:)`：所有 GET/POST 带 `Authorization: Bearer <token>`。
- Mac `OPENFUSE_SYNC_TOKEN`；移动端同名环境变量。
- `Tools/progress_sync_fixture.py --token`：401 拒绝未授权请求。
- `Scripts/run-cross-device-sync.sh`：启动带 token 服务，先断言无 token 401，再跑 Mac→iPhone 续播。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 无 token GET | **401** |
| Mac 推送 | 带 token 成功 |
| iPhone 拉取 | 带 token 成功，resume **11.00s** |
| 脚本 | `Scripts/run-cross-device-sync.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| TLS/并发/CloudKit/真机 | 待验证 |

证据：`Evidence/106-sync-token-resume.jpg`、`reports/m4w-sync-*`、`reports/m4w-sync-token.txt`。

## 可复现差异与未验证

1. **仍为 HTTP，token 明文传输**；生产需 HTTPS。
2. **token 下发/轮换/存储**未做；仅环境变量。
3. **并发写冲突**未压测。
4. **真实 CloudKit/真机**未测。
5. **Jellyfin UI 切换/HTTPS、SMB 多GB/DFS、音频/HDR/visionOS**未完成。

## 下一项

Jellyfin 用户切换已在 [M4x 验收](Docs/M4X-JELLYFIN-USER-SWITCH.md) 完成。剩余 M4y/M6d：切换面板自动化、同步 HTTPS/并发/CloudKit 真机、SMB 多GB/DFS、音频/HDR/visionOS。
