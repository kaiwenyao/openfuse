import OpenFuseCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppTheme.storageKey) private var appearance = AppTheme.light.rawValue
    @State private var switchTarget: JellyfinSource?
    @State private var showCAImporter = false
    @State private var tmdbKey = ""
    @State private var omdbKey = ""

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
                    Text("外观即时生效；进度同步 Bearer Token 保存在 Keychain。")
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
                Section("影视资料") {
                    SecureField("TMDB API key（留空保持已保存值）", text: $tmdbKey)
                    SecureField("OMDb API key（可选，留空保持）", text: $omdbKey)
                    Text("密钥保存在登录 Keychain；TMDB 用于影片/剧集资料，OMDb 用于 IMDb、烂番茄和 Metacritic 评分。只发送片名、年份和公开 ID。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                    HStack {
                        if model.metadataBusy { ProgressView().controlSize(.small) }
                        if let status = model.metadataKeyStatus {
                            Text(status)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("保存") {
                            model.saveMetadataKeys(tmdb: tmdbKey, omdb: omdbKey)
                            tmdbKey = ""
                            omdbKey = ""
                        }
                        Button("保存并验证") {
                            model.saveMetadataKeys(tmdb: tmdbKey, omdb: omdbKey)
                            tmdbKey = ""
                            omdbKey = ""
                            Task { await model.validateMetadataKeys() }
                        }
                        .disabled(model.metadataBusy)
                    }
                }
                Section("进度同步") {
                    TextField("同步地址（http/https）", text: $model.syncURLText)
                    SecureField("Bearer Token（留空保持）", text: $model.syncTokenInput)
                    HStack {
                        Text(model.syncCAPath ?? "未固定 CA（使用系统信任）")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("选择 CA…") { showCAImporter = true }
                    }
                    HStack {
                        if model.syncBusy { ProgressView().controlSize(.small) }
                        if let status = model.syncStatus {
                            Text(status).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button("保存并同步") {
                            Task { await model.saveAndSyncSettings() }
                        }
                        .disabled(model.syncBusy)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
        .fileImporter(
            isPresented: $showCAImporter,
            allowedContentTypes: [.data]
        ) { result in
            if case .success(let url) = result {
                _ = model.saveSyncSettings(
                    urlText: model.syncURLText,
                    token: model.syncTokenInput,
                    caURL: url
                )
                Task { await model.syncWithSettings() }
            }
        }
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
