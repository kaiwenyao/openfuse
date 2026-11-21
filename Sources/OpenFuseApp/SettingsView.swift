import OpenFuseCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppTheme.storageKey) private var appearance = AppTheme.light.rawValue
    @State private var switchTarget: JellyfinSource?

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { appearance },
            set: { value in
                appearance = value
                if let theme = AppTheme(rawValue: value) { theme.apply() }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 20, weight: .semibold))
                    Text("外观即时生效；媒体资料由公共服务或服务器提供，无需配置密钥。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            Form {
                Section("外观") {
                    Picker("主题", selection: appearanceBinding) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("默认明亮主题；「跟随系统」随 macOS 外观切换。播放器始终使用深色背景。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                }
                if !model.jellyfinSources.isEmpty {
                    Section("Jellyfin 用户") {
                        ForEach(model.jellyfinSources) { source in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                    Text("\(source.username) · \(source.baseURL.absoluteString)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Button("切换用户…") { switchTarget = source }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
        .sheet(item: $switchTarget) { source in
            JellyfinUserSwitchSheet(source: source)
                .environmentObject(model)
        }
    }
}

private struct JellyfinUserSwitchSheet: View {
    let source: JellyfinSource
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("切换 Jellyfin 用户")
                .font(.system(size: 17, weight: .semibold))
            Text("\(source.name) · \(source.baseURL.absoluteString)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.secondary)
            TextField("用户名", text: $username)
            SecureField("密码", text: $password)
            if busy { ProgressView().controlSize(.small) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("切换并重新扫描") {
                    busy = true
                    Task {
                        _ = await model.switchJellyfinUser(
                            source,
                            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password
                        )
                        busy = false
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(busy || username.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.background)
        .onAppear { username = source.username }
    }
}
