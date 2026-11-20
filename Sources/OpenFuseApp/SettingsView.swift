import OpenFuseCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Trakt 观看同步使用设备码授权；token 保存在 Keychain。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            Form {
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
    }
}
