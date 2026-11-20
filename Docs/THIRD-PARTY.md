# 第三方组件与许可记录（M1）

本仓库不复制第三方源码，只记录运行依赖。实际发行前需按最终二进制重新核对。

| 组件 | 版本 | 用途 | 许可 | 当前获取方式 |
| --- | --- | --- | --- | --- |
| mpv / libmpv | 0.42.0 | 解封装、解码、ASS 渲染、音频输出 | GPL-2.0-or-later（部分 LGPL-2.1-or-later） | Homebrew `mpv` |
| FFmpeg | 9.0.2（Homebrew 构建） | libmpv 的编解码与解封装后端 | LGPL/GPL（取决于编译选项） | Homebrew 依赖 |
| libass | Homebrew 版本 | ASS/SSA 渲染 | ISC | Homebrew 依赖 |
| Noto Sans SC（测试字体） | 2026-11 下载 | 测试片内嵌字体 | SIL Open Font License 1.1 | `Scripts/make_fixtures.sh` 下载，不入库 |
| 系统字体 PingFang SC / Hiragino Sans | macOS 27.2.1 | 测试字幕样式与回退 | 系统许可 | 本机系统 |
| SQLite | 系统自带（libsqlite3） | 本地媒体库 | Public Domain | macOS SDK |
| TMDB API | v3（可选，需用户 key） | 片名/简介/海报元数据 | TMDB API 服务条款，需署名 | 用户环境变量 `OPENFUSE_TMDB_API_KEY`；仓库不含 key |
| XcodeGen | 2.48.0 | 生成 iOS Xcode 工程（构建期） | MIT | Homebrew；不随应用分发 |

注意：

- 当前 `.app` 链接 `/opt/homebrew` 下的 libmpv/FFmpeg，不是自包含分发物。
- GPL 组件进入发行包会影响整体许可与商店分发；M5 打包阶段需要在「自建 LGPL 构建」与「GPL 开源发行」之间做决定。
- 测试字体只用于生成夹具，不入库；许可证随下载保存在 `Fixtures/generated/NotoSansSC-LICENSE.txt`。
