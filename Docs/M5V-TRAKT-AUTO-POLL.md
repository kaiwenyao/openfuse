# M5v 验收记录：Trakt 设备码自动轮询

日期：2026-11-20。分支：`m5v-trakt-auto-poll`。基线：Infuse 8.5.10（参照客户端待装）。

M5t 设置页需要手动点「检查」。本轮获取设备码后按 interval 自动轮询 token，成功保存并停止；手动检查会取消自动任务；关闭设置页会取消轮询。

## 交付内容

- `AppModel.startTraktPolling`：按 device code interval 轮询，处理 pending/失败/过期。
- `cancelTraktPolling`；SettingsView onDisappear 取消；手动检查先取消自动任务。
- 成功保存 token（Keychain；测试可用 `OPENFUSE_TRAKT_SKIP_KEYCHAIN=1`）。
- CLI `--trakt-auto-auth` 测试钩子。
- 验收脚本 `Scripts/run-trakt-auto-auth.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设备码 | `/oauth/device/code` 200 |
| 自动轮询 | 1.07s 后 `/oauth/device/token` 200 |
| App 状态 | 「Trakt 授权成功」 |
| 脚本 | `Scripts/run-trakt-auto-auth.sh` PASS |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实 Trakt/Keychain | 待验证 |

证据：`reports/m5v-trakt-auto.jsonl`、`reports/m5v-trakt-auto.txt`。

## 可复现差异与未验证

1. **真实 Trakt 账号/token refresh/限流**未验证。
2. **测试跳过 Keychain**；未签名 App 的 Keychain 保存/读取仍可能弹授权。
3. **过期/网络错误路径**未做真实长时测试。
4. **音频人工听测**仍受系统权限阻断。
5. **真实 SMB3/大文件压力、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

M5w：真实 Trakt/Keychain；音频听测；SMB3/大文件；HDR/AirPlay 实机；CloudKit；M3 多根/损坏过滤。
