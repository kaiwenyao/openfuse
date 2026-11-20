# OpenFuse 安装与续签（macOS / iPhone / iPad）

版本：0.2.0 · 提交 `af2f28d`（Mac 安装包）、`2fa2608`（iOS 构建与 USB 脚本）
日期：2026-11-20

## 一、macOS：一条命令安装与升级

私有仓库，先用已登录的 `gh` 取安装脚本，再运行：

```bash
gh release download v0.2.0-af2f28d -R kaiwenyao/openfuse \
  -p install-openfuse-macos.sh -O /tmp/install-openfuse-macos.sh
bash /tmp/install-openfuse-macos.sh
```

我已在本机跑过这条命令（`--no-launch`），安装到 `/Applications/OpenFuse.app`：

```
Installed 0.2.0 (af2f28d) at /Applications/OpenFuse.app
User data kept: 1 sources, 8 Keychain credential(s), playback history present.
```

离线安装（已有 ZIP）：

```bash
bash install-openfuse-macos.sh --app OpenFuse-macOS-0.2.0-af2f28d.zip
```

行为：

- 默认装到 `/Applications`；不可写时回落 `~/Applications`（`--prefix DIR` 可指定）。
- 下载后校验 `SHA-256`（`OpenFuse-macOS-0.2.0-af2f28d.zip.sha256`），再校验 bundle id 与签名。
- 先备份旧版再替换；替换或校验失败自动回滚；重复执行即升级。
- 默认 ad-hoc 签名；`--sign local` 创建/复用 10 年自签身份 `OpenFuse Local Signing`，升级不再因签名变化触发 Keychain 授权（首次会请求一次钥匙串/信任确认）。
- 不申请辅助功能、输入监控或屏幕录制权限；OpenFuse 不需要它们。
- 安装后打印来源数量、Keychain 凭据数量、观看记录是否存在，证明升级没有破坏数据。

实测升级（同一条命令重复执行）：

| 检查 | 结果 |
| --- | --- |
| 来源 | 升级前 1 个，升级后仍 1 个，可正常浏览 WebDAV 目录 |
| Keychain | 升级前 7 条，添加真实来源后 8 条，升级后仍 8 条；读取未弹窗 |
| 观看进度 | `继续观看` 卡升级后仍显示 S03E13 `02:09 / 23:57` |

产物：

| 文件 | 说明 |
| --- | --- |
| `build/OpenFuse-macOS-0.2.0-af2f28d.zip` | 自包含 .app（含 50 个 dylib） |
| `build/OpenFuse-macOS-0.2.0-af2f28d.zip.sha256` | `e8b1f798…03ff79`（重打包会变，以 Release 资产为准） |
| `build/install-openfuse-macos.sh` | 安装脚本 |
| GitHub Release | `v0.2.0-af2f28d`（私有仓库，需登录 gh） |

## 二、iPhone / iPad：数据线安装与 7 天续签

前置（每台一次，需要你本人操作）：

1. 数据线连接 Mac，设备上点“信任此电脑”并输入密码。
2. 设备：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启。
3. Xcode → Settings… → Accounts → 用**免费 Apple 账户**登录，选中 Personal Team；必要时 Manage Certificates → “+” → Apple Development。
4. 首次安装后：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。

安装或续签（两条设备依次插线，各跑一次；不带 `--device` 时只有一台会自动选中）：

```bash
Scripts/install-openfuse-ios.sh --device "iPhone 的名字"
Scripts/install-openfuse-ios.sh --device "iPad 的名字"
```

脚本会：检查 Xcode / XcodeGen / Apple Development 身份 / 已连接设备 → 用稳定 Bundle ID `com.openfuse.mobile` 和自动签名构建 → `devicectl` 覆盖安装并启动 → 读取 `embedded.mobileprovision` 的到期日并打印剩余天数。免费 Personal Team 的签名 7 天到期，到期前重复同一条命令即可续签；覆盖安装保留 App 数据与 Keychain（Bundle ID 与 Team 不变）。

当前状态：本机没有连接 iPhone/iPad，也没有 Apple Development 身份，因此**设备安装尚未执行**。脚本在无设备时会打印上面四步并退出，不会误装。

模拟器已做的事（不代表真机）：iPhone 18 Pro 模拟器上安装并启动 `com.openfuse.mobile`，用 `SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_*` 注入真实 Jellyfin 账号（仅在内存/临时来源，不落 Keychain），`OPENFUSE_AUTOPLAY_*` 打开《进击的巨人》S03E13 并跳到 300 s，截图确认 HLS 转码播放与音轨信息。

## 三、移动端播放能力现状

| 能力 | 状态 |
| --- | --- |
| 本地 MP4/MOV、WebDAV 认证 MP4 | 已有（AVPlayer） |
| Jellyfin 剧→季→集、HLS 转码播放、音字幕选择、进度回写、续播 | 已有，模拟器可跑；真机待验 |
| Jellyfin 直放/转码选择 | 已有界面与逻辑，待真机验证 |
| Jellyfin 外挂 ASS（简/繁） | 已实现：Jellyfin 12 不返回 `DeliveryUrl` 时回退 `/Videos/{id}/{source}/Subtitles/{index}/Stream.ass`，下载到 `SubtitleCache` 后按纯文本渲染，默认简体、可切繁體 |
| Jellyfin 进度回写与跨设备续播 | 已实现：`Sessions/Playing`、`/Progress`、`/Stopped`；无本地记录时用服务器位置起播；播到结尾时服务器标记 `Played=true` |
| 移动端自动下一集 | 已实现：`AVPlayerItemDidPlayToEndTime` + `time >= duration-2.5` 兜底，切集时重建播放器；真实 Jellyfin HLS 在 1428/1436.5 s 处提前停住，模拟器未触发，需真机或本地文件复测 |
| WebDAV 上的 MKV 直放（HEVC Main 10 / E-AC-3 5.1 / 内外挂 ASS） | 已实现（模拟器验证）：SPM 依赖 `mpvkit/MPVKit`（libmpv + ffmpeg + libass），Metal/MoltenVK 渲染；外挂 ASS 通过 `sub-add` 加载并默认简体；包体增加约 90 MB（含 16 MB 字体） |
| ASS 样式排版 | 外挂 ASS 解析保留 `\N` 换行并去样式标签，按纯文本显示；斜体/定位/字体回退未做 |

## 四、验收表（Mac / iPhone / iPad × WebDAV / Jellyfin）

| | WebDAV | Jellyfin |
| --- | --- | --- |
| **Mac** | ✅ 已实测：S03E13 HEVC Main 10、内外挂 ASS、简繁切换、前中后拖动、退出回原季、续播；S01E01 E-AC-3 5.1 下混立体声 | ✅ 已实测：剧→季→集、直放、字幕切换、进度回写并恢复、退出回季、续播、自动下一集 |
| **iPhone** | 🟡 模拟器通过（libmpv）：真实 WebDAV 的 S03E13 MKV 直放，HEVC Main 10 出画；外挂 简体/繁體 ASS 由 libass 渲染，内置 Noto Sans CJK 字体无方框；`Sex Education S01E01` 的 E-AC-3 5.1 解码为 6ch 后经 audiounit 下混为 2ch 立体声；真机待验 | 🟡 模拟器实测通过（iPhone 18 Pro）：真实 Jellyfin 的 S03E13 经 HLS 转码播放；外挂 ASS 走 Stream 回退下载后默认简体，`AUTOPLAY_SUBTITLE_INDEX=2` 切到繁體，画面分别显示「什么 我到底在怕什么 / 什麼 我到底在怕什麼」；服务器进度回写 301 s，清空本地记录后用服务器 300 s 起播，实测从 302.2 s 续播并保持简体 |
| **iPad** | ⏳ 待真机：同上；MKV 直放缺引擎 | 🟡 模拟器播放通过（iPad Pro 13"）：同一路 HLS + 简体字幕；修复了播放器右上角对齐导致的视频缩角/字幕贴边问题，现为全屏居中；横竖屏与分屏待验（本机 Xcode 27 没有 Simulator 界面程序，无法脚本旋转） |

## 五、还差什么

1. 两台真机插线 + Xcode 登录免费 Apple 账户，才能执行第二节的安装命令并填上表中 ⏳ 的格子。
2. WebDAV MKV 直放需要给 iOS 端加一个支持 MKV/ASS 的播放引擎（mpv 交叉编译或 VLCKit）；这是移动端与 Mac 端唯一的实质性能力差距。
