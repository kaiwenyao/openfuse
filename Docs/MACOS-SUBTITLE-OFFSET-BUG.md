# macOS 字幕时间偏移问题报告

排查日期为 2026-11-25。工作区基线为 `ce8ac76`，实测版本为已安装的 OpenFuse 0.9.1 和工作区打包的 0.9.3。

已确认两类问题。手输的小数偏移在播放器里生效，菜单和编辑框却按一位小数显示。带数学负号 `−` 的输入会丢失负号，令字幕朝相反方向移动。测试使用本地 MP4 和已知时间戳的外挂 SRT。

## 菜单和输入框显示的精度低于实际偏移

### 手动复现

1. 打开本地影片，选择一条外挂 SRT 字幕轨。下面的样片命令生成一条从 `00:00:05,000` 到 `00:00:06,000` 的字幕。
2. 在 macOS 播放器底栏点击字幕，选择「输入秒数…」，输入 `0.04` 并应用。
3. 查看字幕菜单，再次打开输入框。菜单显示「同步（0 秒）」，输入框预填 `0.0`。
4. 比较播放位置为 5.02 秒时的画面。偏移为 0 时可以看到字幕，设为 `0.04` 秒后看不到字幕。关闭影片并重新打开，选中同一字幕轨，偏移仍然生效。

期望菜单和输入框都能表达实际生效的 `0.04` 秒。重新打开输入框后直接应用，应保留原偏移。只有实际生效的偏移为 0 时，菜单才显示「同步（0 秒）」。

### 播放器实测

以下各项均在播放位置 5.02 秒、播放器已暂停时取样。用应用的测试报告读取偏移值和 mpv 当前字幕文本，并检查黑底样片的实际渲染帧。0.9.1 和 0.9.3 的结果一致。

| 操作 | 应用记录的偏移（秒） | 菜单文案 | 画面中的字幕 |
| --- | ---: | --- | --- |
| 选择简体轨，设为 0 | 0 | 同步（0 秒） | 可见 |
| 简体轨设为 `0.04` | 0.04 | 同步（0 秒） | 不可见 |
| 改选繁体轨并设为 `-0.1` | -0.1 | 提前 0.1 秒 | 繁体轨字幕可见 |
| 重开影片并选回简体轨 | 0.04 | 同步（0 秒） | 不可见 |
| 简体轨重置为 0 | 0 | 同步（0 秒） | 可见 |

直接运行现有格式化函数也复现了另一组差异。已应用 `0.15` 秒时，菜单显示「延后 0.2 秒」，编辑框预填 `0.1`。根据提交路径，直接点击「应用」会把偏移改为 `0.1` 秒。该组验证了格式化结果，未逐次点击输入弹窗。

### 代码定位

- `SubtitleOffsetText.summary(_:)` 先舍入到十分之一秒，因此会把部分非零偏移显示为「同步」。[SubtitleOffset.swift](../Sources/OpenFuseData/SubtitleOffset.swift#L5)
- `PlayerModel.beginSubtitleDelayInput()` 用 `%.1f` 预填。提交时会重新解析这个字符串并应用。[AppModel.swift](../Sources/OpenFuseApp/AppModel.swift#L3690)
- `PlayerModel.setSubtitleDelay(_:)` 发布偏移并保存到当前影片和字幕轨的记录。恢复轨道时会重新应用保存的值。[AppModel.swift](../Sources/OpenFuseApp/AppModel.swift#L3657)
- `MPVEngine.setSubtitleDelay(_:)` 按三位小数设置 `sub-delay`，所以像 `0.04` 这样的值能实际改变渲染时间。[MPVEngine.swift](../Sources/OpenFuseCore/MPVEngine.swift#L368)

## 部分负数输入被解析成正数

在字幕偏移弹窗粘贴 `−0.1`。首字符为 U+2212 数学负号。按现有解析和提交路径，这个值会被解析为 `+0.1` 秒。

| 输入 | 直接运行现有解析函数的结果（秒） | 期望 |
| --- | ---: | --- |
| `-0.1` | -0.1 | 提前 0.1 秒 |
| `−0.1` | +0.1 | 提前 0.1 秒 |
| `-.1` | +1.0 | 提前 0.1 秒，或明确提示格式无效 |
| `提前 0.1 秒` | +0.1 | 提前 0.1 秒，或明确提示格式无效 |
| `1,5` | +1.5 | 延后 1.5 秒 |

该表来自对实际 Swift 解析函数的直接调用。函数已归一化全角正负号和逗号小数点，但没有处理 U+2212。它使用正则搜索第一个符合条件的数字片段。正则要求小数点前有数字，因此 `-.1` 会匹配到 `1`。方向短语也会只取数字，忽略「提前」。弹窗提交直接使用解析结果。[SubtitleOffset.swift](../Sources/OpenFuseData/SubtitleOffset.swift#L14) · [AppModel.swift](../Sources/OpenFuseApp/AppModel.swift#L3696)

## 样片和复现命令

在仓库根目录运行。示例需要 `ffmpeg`，可使用已构建的 macOS 应用，也可先运行 `swift build --product OpenFuse`。样片、截图和测试配置都写到临时目录。传入 `--sub-delay` 走应用设置偏移的逻辑，可以复现实际画面与菜单的差异。验证第二类问题时请走输入弹窗或直接调用解析函数。

```bash
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/openfuse-offset.XXXXXX")"
ffmpeg -v error -f lavfi -i 'color=c=black:size=320x180:rate=60:duration=8' \
  -c:v libx264 -pix_fmt yuv420p "$test_dir/sample.mp4"

cat > "$test_dir/sample.zh-Hans.srt" <<'SRT'
1
00:00:05,000 --> 00:00:06,000
OPENFUSE TIMING MARKER
SRT

app="$PWD/.build/debug/OpenFuse"
for offset in 0 0.04; do
  OPENFUSE_SUPPORT_DIR="$test_dir/profile" \
  OPENFUSE_CREDENTIAL_MODE=session \
  OPENFUSE_DISABLE_THUMB_PREFETCH=1 \
  "$app" --open "$test_dir/sample.mp4" --freeze-at 0.1 --seek 5.02 \
    --sub-delay "$offset" --capture "$test_dir/frame-$offset.png" \
    --report "$test_dir/report-$offset.json" --capture-after 4 --quit-after 4.5
done
printf '%s\n' "$test_dir"
```

查看报告中的 `position`、`paused`、`subDelay`、`subDelaySummary` 和 `subText`，同时比较两张 PNG。复查保存时，重开同一文件并省略 `--sub-delay`。

## 回归验证范围

- 在工作区构建上，以 5.000 秒的首条字幕核对了 `0`、`+0.1` 和 `-0.1`。零偏移时 4.95 秒无字幕、5.05 秒有字幕。延后 0.1 秒时 5.05 秒无字幕、5.15 秒有字幕。提前 0.1 秒时 4.85 秒无字幕、4.95 秒有字幕。
- `swift test --filter 'SubtitleOffsetTests|SubtitleCatalogTests|PlaybackClockTests'` 共通过 13 项。现有偏移测试覆盖常见输入和按轨存储，缺少精细小数往返、U+2212 负号、解析方向短语的回归样例。[SubtitleOffsetTests.swift](../Tests/OpenFuseCoreTests/SubtitleOffsetTests.swift)
- 更大偏移的既有播放验证可参考 [run-three-features.sh](../Scripts/run-three-features.sh#L92)。本次实测范围为 macOS 本地外挂 SRT。

修复任务可使用 [Agent 提示词](MACOS-SUBTITLE-OFFSET-FIX-PROMPT.md)。
