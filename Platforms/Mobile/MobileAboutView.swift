import SwiftUI

struct MobileAboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var spoiler = false

    var body: some View {
        NavigationStack {
            Form {
                Section("播放") {
                    LabeledContent("引擎", value: "AVPlayer")
                    LabeledContent("容器", value: "MP4 / MOV")
                    LabeledContent("MKV", value: "待接入 libmpv")
                    LabeledContent("音频", value: "AAC / 立体声")
                }
                Section("媒体库") {
                    LabeledContent("来源", value: "本地导入 + 内置示例 + 服务器扫描")
                    LabeledContent("Jellyfin/WebDAV", value: "可添加/扫描；远程播放待接入")
                }
                Section("关于") {
                    LabeledContent("版本", value: "0.4.0-mobile")
                    Text("iPhone/iPad 首版聚焦本地 MP4 播放与续播；服务器来源、MKV、字幕与 iCloud 同步在后续里程碑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
