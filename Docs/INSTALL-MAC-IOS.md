# OpenFuse 安装与续签（macOS / iPhone / iPad）

版本：0.5.5（仓库公开，安装/发布与 anypaste 对齐）
日期：2026-11-20

## 一、macOS：一条命令安装与升级

私有仓库，先用已登录的 `gh` 取安装脚本，再运行：

```bash
curl -fL --proto '=https' --proto-redir '=https' \
  -o install-openfuse-macos.sh \
  https://github.com/kaiwenyao/openfuse/releases/latest/download/install-openfuse-macos.sh \
  && bash install-openfuse-macos.sh

# 或从私有仓库取（需 gh 已登录）：
# gh release download v0.5.5 -R kaiwenyao/openfuse \
#   -p install-openfuse-macos.sh -O /tmp/install-openfuse-macos.sh
# bash /tmp/install-openfuse-macos.sh
```

我已在本机跑过这条命令（`--no-launch`），安装到 `/Applications/OpenFuse.app`：

```
Installed 0.5.5 at /Applications/OpenFuse.app
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
- 与 anypaste 统一的默认签名策略：默认 `--sign local`（持久身份，升级复用），`--sign adhoc` 显式降级；运维参数：`--uninstall`（删 app 与签名身份，保留来源/Keychain/观看记录）、`--reset-identity`、`--sign local`（10 年自签身份，一次信任后升级复用）、`--prefix`、`--keep-backup`；并拒绝 root、检查 arm64/x86_64 与 macOS 14+。

实测升级（同一条命令重复执行）：

| 检查 | 结果 |
| --- | --- |
| 来源 | 升级前 1 个，升级后仍 1 个，可正常浏览 WebDAV 目录 |
| Keychain | 升级前 7 条，添加真实来源后 8 条，升级后仍 8 条；读取未弹窗 |
| 观看进度 | `继续观看` 卡升级后仍显示 S03E13 `02:09 / 23:57` |

产物：

| 文件 | 说明 |
| --- | --- |
| `build/OpenFuse-macos.zip` | 自包含 .app（含 50 个 dylib），资产名与 anypaste 一致 |
| `build/OpenFuse-macos.zip.sha256` | 与 zip 同目录；Release 说明里也记录完整值 |
| `build/install-openfuse-macos.sh` | 安装脚本 |
| GitHub Release | `v0.5.5`（公开仓库 `kaiwenyao/openfuse`；资产为 `OpenFuse-macos.zip`、`.sha256`、安装脚本） |
| 安装入口 | 与 anypaste 相同：`releases/latest/download/install-openfuse-macos.sh`，无需登录 |

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

构建状态：`xcodebuild -destination generic/platform=iOS` 已用 MPVKit 编译通过（未签名）。产物大小：Debug 63 MB、Release 56 MB（内嵌 27 个 framework），安装到真机时由 Xcode 自动签名。脚本在无设备时会打印上面四步并退出，不会误装。

模拟器已做的事（不代表真机）：iPhone 18 Pro 模拟器上安装并启动 `com.openfuse.mobile`，用 `SIMCTL_CHILD_OPENFUSE_TEST_JELLYFIN_*` 注入真实 Jellyfin 账号（仅在内存/临时来源，不落 Keychain），`OPENFUSE_AUTOPLAY_*` 打开《进击的巨人》S03E13 并跳到 300 s，截图确认 HLS 转码播放与音轨信息。

## 三、移动端播放能力现状

| 能力 | 状态 |
| --- | --- |
| 本地 MP4/MOV、WebDAV 认证 MP4 | 已有（AVPlayer） |
| Jellyfin 剧→季→集、HLS 转码播放、音字幕选择、进度回写、续播 | 已有，模拟器可跑；真机待验 |
| Jellyfin 直放/转码选择 | 已有界面与逻辑，待真机验证 |
| Jellyfin 外挂 ASS（简/繁） | 已实现：Jellyfin 12 不返回 `DeliveryUrl` 时回退 `/Videos/{id}/{source}/Subtitles/{index}/Stream.ass`，下载到 `SubtitleCache` 后按纯文本渲染，默认简体、可切繁體 |
| Jellyfin 进度回写与跨设备续播 | 已实现：`Sessions/Playing`、`/Progress`、`/Stopped`；无本地记录时用服务器位置起播；播到结尾时服务器标记 `Played=true` |
| 移动端自动下一集 | 两条路径都已实现：AVPlayer 用 `AVPlayerItemDidPlayToEndTime` + 临近结尾阈值；libmpv 用 `eof-reached` 触发 `nextEpisodeItem` 并重建播放器。真实 HLS 在结尾前停住、WebDAV 大文件在模拟器里读取很慢，两者都未能在本轮触发，需真机/本地文件复测 |
| WebDAV 上的 MKV 直放（HEVC Main 10 / E-AC-3 5.1 / 内外挂 ASS） | 已实现（模拟器验证）：SPM 依赖 `mpvkit/MPVKit`（libmpv + ffmpeg + libass），Metal/MoltenVK 渲染；外挂 ASS 通过 `sub-add` 加载并默认简体；包体增加约 90 MB（含 16 MB 字体） |
| ASS 样式排版 | 外挂 ASS 解析保留 `\N` 换行并去样式标签，按纯文本显示；斜体/定位/字体回退未做 |

## 四、验收表（Mac / iPhone / iPad × WebDAV / Jellyfin）

| | WebDAV | Jellyfin |
| --- | --- | --- |
| **Mac** | ✅ 已实测：S03E13 HEVC Main 10、内外挂 ASS、简繁切换、前中后拖动、退出回原季、续播；S01E01 E-AC-3 5.1 下混立体声 | ✅ 已实测：剧→季→集、直放、字幕切换、进度回写并恢复、退出回季、续播、自动下一集 |
| **iPhone** | 🟡 模拟器通过（libmpv）：正常流程=添加指向 `…/Attack on Titan (2013)/Season 03` 的来源 → 扫描出 23 集 → 打开 S03E13 → 直放 MKV，HEVC Main 10 出画，默认「中文（简体）(ASS)」；外挂繁體同样渲染正常、无方框；`Sex Education S01E01` 的 E-AC-3 5.1 解码 6ch 后经 audiounit 下混 2ch。注：扫描整个 WebDAV 根目录在移动端过慢，建议来源地址直接指到剧/季目录；真机待验 | 🟡 模拟器实测通过（iPhone 18 Pro）：真实 Jellyfin 的 S03E13 经 HLS 转码播放；外挂 ASS 走 Stream 回退下载后默认简体，`AUTOPLAY_SUBTITLE_INDEX=2` 切到繁體，画面分别显示「什么 我到底在怕什么 / 什麼 我到底在怕什麼」；服务器进度回写 301 s，清空本地记录后用服务器 300 s 起播，实测从 302.2 s 续播并保持简体 |
| **iPad** | 🟡 模拟器通过（iPad Pro 13"）：来源指向 Season 03 → S03E13 由 libmpv 直放，简体 ASS 正常、视频按宽屏铺满；旋转/分屏仍待真机 | 🟡 模拟器通过（iPad Pro 13"）：HLS + 简体字幕，布局已修为全屏居中；横竖屏/分屏待验 |

## 五、还差什么

1. 两台真机插线 + Xcode 登录免费 Apple 账户，才能执行第二节的安装命令并填上表中 ⏳ 的格子。
2. WebDAV MKV 直放需要给 iOS 端加一个支持 MKV/ASS 的播放引擎（mpv 交叉编译或 VLCKit）；这是移动端与 Mac 端唯一的实质性能力差距。
