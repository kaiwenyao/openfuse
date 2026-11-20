import OpenFuseCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var switchTarget: JellyfinSource?
    @State private var showCAImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Trakt 使用设备码授权；进度同步 Bearer Token 保存在 Keychain。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            Form {
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
                Section("Trakt") {
                    TextField("Client ID", text: $model.traktClientID)
                    SecureField("Client Secret", text: $model.traktClientSecret)
                    TextField("API 地址", text: $model.traktBaseURL)
                }
            }
            .formStyle(.grouped)

            if let message = model.traktMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(model.traktConfigured ? Theme.accent : Theme.secondary)
            }
            if let code = model.traktUserCode, let url = model.traktVerificationURL {
                HStack(spacing: 12) {
                    Text("设备码")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                    Text(code)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text(url)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("已完成授权，检查") {
                        Task { await model.pollTraktToken() }
                    }
                    .disabled(model.traktBusy)
                }
                .padding(10)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                if model.traktBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("保存配置") { _ = model.saveTraktSettings() }
                Button("获取设备码") {
                    Task { await model.beginTraktDeviceCode() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.traktBusy || model.traktClientID.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
        .onDisappear { model.cancelTraktPolling() }
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
