> **0.7.0 已移除该功能。** 本文仅保留历史设计记录；应用不再提供进度同步入口、环境变量或凭据读取。

# M4z 验收记录：iPhone HTTPS 同步与 CA 固定

日期：2026-11-20。分支 `m4z-ios-sync-https`。基线 Infuse 8.5.10（参照客户端待装）。

M4y 只在 Mac 验证 CA 固定。本轮把测试 CA 复制到模拟器 app Documents，`OPENFUSE_SYNC_CA` 指向容器路径；iPhone 通过 HTTPS 拉取进度并自动续播。

## 交付内容

- `Scripts/run-ios-sync-https.sh`：生成 CA/服务器证书、启动 HTTPS、POST 记录、安装 app、复制 CA、启动并断言 resume。
- 复用 `PinnedTrustDelegate`；无新生产代码（移除调试日志）。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| iPhone HTTPS GET/POST | 到达服务 |
| resume | **11.00s** |
| CA | app Documents/ca.pem，仅该 CA 受信 |
| 脚本 | `Scripts/run-ios-sync-https.sh` PASS |
| `swift test` | **36/36 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| CA 分发 UI/公共 CA/并发 | 待验证 |

证据：`Evidence/109-ios-sync-https.jpg`、`reports/m4z-ios-https-*`、`reports/m4z-ios-sync-https.txt`。

## 可复现差异与未验证

1. **CA 通过测试脚本复制**；无用户导入 UI/配置描述文件。
2. **自签 CA**；公共/企业 CA、TLS 审计未做。
3. **并发同步冲突**未压测。
4. **真实 CloudKit/真机、SMB >2GB/DFS、切换面板自动化、音频/HDR/visionOS**未完成。

## 下一项

M5ao/M6d：SMB >2GB/DFS；CA 导入 UI、并发同步、CloudKit 真机；音频/HDR/visionOS。
