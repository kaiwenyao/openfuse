# M5t 验收记录：Trakt OAuth 设置界面与持久化

日期：2026-11-20。分支：`m5t-trakt-oauth-ui`。基线：Infuse 8.5.10（参照客户端待装）。

Trakt 此前只能环境变量配置。现在有设置页：填写 Client ID/Secret/API 地址，保存到 UserDefaults，secret/token 存 Keychain；设备码授权与轮询按钮；环境变量仍作为测试覆盖。

## 交付内容

- `TraktService.configure`；`requestDeviceCode` / `pollDeviceToken`；实例可由 AppModel 配置。
- AppModel：
  - 读取 env 或持久化配置；
  - `saveTraktSettings`（UserDefaults + Keychain）；
  - `beginTraktDeviceCode` / `pollTraktToken`；
  - `traktConfigured`、状态消息。
- `SettingsView`：Client ID/Secret/API 地址、连接状态、设备码显示、保存/获取设备码/检查授权。
- Home 齿轮按钮打开设置（不再 inert）；`--show-settings` 测试钩子。
- `captureUI` 捕获最后可见窗口，使 sheet 可截图。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| 设置页 | 实际渲染；字段/状态/按钮完整 |
| 环境变量预填 | demo-client、http://127.0.0.1:8123、已连接（环境变量） |
| 设备码/轮询协议 | M4q probe/acceptance 已验证 |
| `swift test` | **29/29 通过** |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| UI 按钮点击 | 未自动化 |
| 真实 Trakt/Keychain 签名 | 待验证 |

证据：`Evidence/86-trakt-settings.jpg`、`reports/m5t-trakt-settings.txt`。

## 可复现差异与未验证

1. **设置页按钮点击未自动化**；只验证渲染与协议。
2. **未签名构建的 Keychain 保存/读取可能弹授权**；生产需 Developer ID。
3. **真实 Trakt 账号/token refresh/限流**未验证。
4. **设备码轮询未在 UI 中自动循环**；需用户点「检查」。
5. **音频人工听测、SMB3/并发、HDR/AirPlay 实机、CloudKit、M3 多根/损坏过滤**未做。

## 下一项

M5u：真实 Trakt/自动轮询；音频听测；SMB3/并发；HDR/AirPlay 实机；CloudKit；M3 多根/损坏过滤。
