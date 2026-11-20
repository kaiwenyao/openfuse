# M4y 验收记录：同步 HTTPS + 自签 CA 固定

日期：2026-11-20。分支 `m4y-sync-https`。基线 Infuse 8.5.10（参照客户端待装）。

M4w 的 token 仍走 HTTP 明文。本轮给 HTTP transport 增加 `OPENFUSE_SYNC_CA`：用 PEM/DER CA 作为唯一信任锚，校验服务器证书；fixture 支持 TLS。Mac 通过 HTTPS 推送，未固定 CA 的请求被拒绝。

## 交付内容

- `PinnedTrustDelegate`：`SecTrustSetAnchorCertificates` + `AnchorCertificatesOnly`，失败取消。
- `HTTPProgressTransport(url:token:caPath:)`；Mac/移动端读取 `OPENFUSE_SYNC_CA`。
- `Tools/progress_sync_fixture.py --tls-cert/--tls-key`。
- `Scripts/run-sync-https.sh`：生成 CA/服务器证书（SAN 127.0.0.1）、启动 HTTPS、curl 正负测、Mac 同步。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| curl + CA | **200** |
| curl 无 CA | **证书错误，拒绝** |
| OpenFuse HTTPS 同步 | **完成**，POST 被接受 |
| 脚本 | `Scripts/run-sync-https.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| iPhone CA 分发/公共 CA | 待验证 |

证据：`reports/m4y-https-sync.log`、`m4y-https-app.log`、`m4y-tls-cert.txt`、`m4y-https-sync.txt`。

## 可复现差异与未验证

1. **仅 Mac** 用宿主 CA 文件验证；iPhone 模拟器 CA 分发未完成。
2. **自签 CA**；公共 CA/企业 CA、TLS 版本/密码套件未审计。
3. **并发同步**未压测。
4. **真实 CloudKit/真机/音频/HDR/visionOS**未完成。

## 下一项

M4z/M6d：iPhone CA 分发、并发同步、CloudKit 真机；SMB >2GB/DFS；音频/HDR/visionOS。
