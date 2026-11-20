# 当前交付目标：Mac 上的 WebDAV 和 Jellyfin

更新于 2026-11-20。开发基线为 main 的 `1a20827`。本轮只交付 macOS 客户端，支持通过 OpenList WebDAV 访问原始目录，以及通过 Jellyfin 浏览电影库和电视剧库。以 Infuse 8.5.10 Mac 的可观察行为为参照，重点是找片、播放、选轨、返回与续播。界面使用 OpenFuse 有辨识度的原创布局与素材。原路线中的其余平台、协议、云服务及购买流程暂缓。

## 当前进度和证据

| 项目 | 已核实 | 本轮需要补的证据 |
| --- | --- | --- |
| 本机环境 | 本机安装的 Infuse 为 8.5.10，build 8.5.5815。OpenFuse 的构建脚本本次在 libmpv 预检处退出。用独立临时构建目录运行 swift test，在编译 CSMB2 时缺少 libsmb2 头文件 | 在这台 Mac 编译、运行测试、启动普通用户能双击打开的应用。参考客户端的权益状态与同机播放表现待测 |
| 播放器 | [本地播放记录](M1-ACCEPTANCE.md)有 HEVC Main 10、E-AC-3 5.1 输入、立体声输出、简繁 ASS 渲染帧以及退出续播记录 | 用两种远程来源走实际窗口操作，验证选轨、拖动、重新打开和中文显示 |
| WebDAV | [OpenList 报告](Evidence/reports/m2c-openlist-real.txt)记录 Docker OpenList 的 Local 存储，经 HTTP 列库、范围读取、拖动和远程 SRT。另有[目录超时保留索引的用例](M3I-RECOVERY.md) | 百度网盘经 OpenList HTTPS、签名链接变化、长片拖动及远程 ASS。测试服务与个人环境结果分别标注 |
| Jellyfin | [服务器报告](Evidence/reports/m2e-real-jellyfin.txt)记录 Jellyfin 12.4.0 测试服的直放及退出后写回 11.022 秒。测试片长约 20 秒，测试服调整过续播阈值 | 分页大库、扫描中断、从服务器较早位置重看、反代下播放。Mac 的转码结果需由 Mac 验证 |
| 历史测试 | [阶段快照](STAGE-2026-11-20.md)记载当时 36/36 通过 | 本次两个命令都停在编译或依赖预检阶段。本机双源 GUI 流程尚待实测 |

## 下一位开发者的实施顺序

1. **先恢复可运行的 Mac 基线。** 复用现有 SwiftUI、libmpv、SQLite 及脚本。检查 Package.swift、Scripts/build-app.sh、Scripts/package-app.sh。解决本机 libmpv 构建依赖，让只开发这两个来源的 Mac 构建摆脱对 SMB 头文件的强制依赖，兼顾已有 SMB 构建方式。运行单测、打包并从 Finder 启动，记录启动命令及产物。
2. **先修会漏片的索引。** [JellyfinClient](../Sources/OpenFuseData/Jellyfin.swift) 的 items 和 libraryItems 仅取一页，上限分别为 500 和 5000。[扫描器](../Sources/OpenFuseData/LibraryScanner.swift)把单库请求错误转换为空数组，随后 [AppModel](../Sources/OpenFuseApp/AppModel.swift) 替换整源的本地索引，且此入口未把取消令牌传入扫描器。实现分页和取消，避免超时、不完整或过期的扫描覆盖上次完整结果。区分临时读取失败与服务器明确撤销库访问权，后者需及时反映。用合成数据覆盖 501 个直接子项、5001 个递归条目、中途失败、取消后重扫及权限撤回。
3. **把日常观影流程走通。** 从空白配置通过界面添加 WebDAV 或 Jellyfin。WebDAV 保留目录层级，Jellyfin 打开电影库或剧→季→集，支持两条路径下的播放与首页续播。当前 [AppModel](../Sources/OpenFuseApp/AppModel.swift) 在关闭时直接切回首页，且以本地和服务器进度的较大值决定起点；验证从深层目录返回、服务端回退重看和本机离线续播，再修正行为。[播放器](../Sources/OpenFuseApp/PlayerView.swift) 的倍速菜单固定显示 1.0x，需反映实际选择。首页优先突出两个目标来源、媒体库与继续观看。
4. **做普通用户路径的双源验收。** 复用受控服务和仓库样片。分别通过两种来源打开同一份 HEVC Main 10、E-AC-3 5.1 和外挂 ASS 素材，用窗口操作切换简繁、在三个时间点拖动、退出、重开。记录字幕画面、声音输出方式、光标所在条目、恢复位置及 Jellyfin 服务器回写。按设备与权益可用情况在同机 Infuse 复核默认选轨、续播和返回行为。开发脚本预选的结果与实际点击结果分别登记。有可用测试账号时补验真实 HTTPS 和百度后端，标明所用来源。
5. **交付可复验的构建。** 提供 .app 或 zip、构建/启动命令、测试结果、一条 WebDAV 和一条 Jellyfin 的界面操作记录，以及尚待实测的条件。两个来源通过此轮 Mac 验收后再讨论扩展范围。

交付时附上三个能直接判断成败的结果：大库最后一项可以找到且打开；某一页超时后旧索引仍可用并能重试；用户能从原目录或剧集的位置接着找片，并从首页恢复到刚才选择的版本、进度及字幕。
