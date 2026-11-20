import OpenFuseData
import SwiftUI
import UniformTypeIdentifiers

struct MobileSourcesView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var addKind: SourceKind?
    @State private var errorText: String?
    @State private var showCAImporter = false

    enum SourceKind: String, Identifiable {
        case webdav
        case jellyfin
        var id: String { rawValue }
        var title: String { self == .webdav ? "WebDAV / OpenList" : "Jellyfin" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("WebDAV / OpenList") {
                    if model.webdavSources.isEmpty {
                        Text("尚未添加。支持 Basic Auth 的 WebDAV 目录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.webdavSources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.headline)
                            Text(source.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("扫描") {
                                    Task {
                                        do { try await model.scanWebDAV(source) }
                                        catch { errorText = error.localizedDescription }
                                    }
                                }
                                .buttonStyle(.bordered)
                                Button("删除", role: .destructive) { model.removeWebDAV(source) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    Button {
                        addKind = .webdav
                    } label: {
                        Label("添加 WebDAV", systemImage: "plus")
                    }
                }

                Section("Jellyfin") {
                    if model.jellyfinSources.isEmpty {
                        Text("尚未添加。输入服务器地址与独立测试账号。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.jellyfinSources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.headline)
                            Text(source.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("扫描") {
                                    Task {
                                        do { try await model.scanJellyfin(source) }
                                        catch { errorText = error.localizedDescription }
                                    }
                                }
                                .buttonStyle(.bordered)
                                Button("删除", role: .destructive) { model.removeJellyfin(source) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    Button {
                        addKind = .jellyfin
                    } label: {
                        Label("添加 Jellyfin", systemImage: "plus")
                    }
                }

                Section("进度同步") {
                    TextField("同步地址（http/https）", text: $model.syncURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Bearer Token（留空保持）", text: $model.syncTokenInput)
                    HStack {
                        Text(model.syncCAPath == nil ? "未固定 CA（系统信任）" : "已固定 CA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("选择 CA…") { showCAImporter = true }
                    }
                    HStack {
                        if model.syncBusy { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("保存并同步") {
                            Task {
                                if model.saveSyncSettings(
                                    urlText: model.syncURLText,
                                    token: model.syncTokenInput,
                                    caURL: nil
                                ) {
                                    await model.syncWithSettings()
                                }
                            }
                        }
                        .disabled(model.syncBusy)
                    }
                    if let status = model.syncStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("说明") {
                    Text("凭据存入 iOS Keychain；密码/token 不写入 sources.json。WebDAV 的 MKV 由 libmpv 直放（外挂 ASS、E-AC-3 下混），MP4/MOV 与 Jellyfin HLS 走 AVPlayer。扫描整个根目录较慢，可把地址填到剧集或季目录（例如 …/电视剧/Attack on Titan (2013)/Season 03）来加快。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let status = model.status {
                    Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
                if let errorText {
                    Section { Text(errorText).font(.footnote).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("媒体来源")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showCAImporter, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result {
                    if model.saveSyncSettings(
                        urlText: model.syncURLText,
                        token: model.syncTokenInput,
                        caURL: url
                    ) {
                        Task { await model.syncWithSettings() }
                    }
                }
            }
            .sheet(item: $addKind) { kind in
                MobileAddSourceForm(kind: kind)
                    .environmentObject(model)
            }
        }
    }
}

private struct MobileAddSourceForm: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    let kind: MobileSourcesView.SourceKind

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var subpath = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.title) {
                    TextField("名称", text: $name)
                    TextField("服务器地址", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                    if kind == .webdav {
                        TextField("子目录（可选）", text: $subpath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    Text(kind == .webdav
                         ? "地址示例：https://openlist.example.com/dav/。子目录例如 电视剧/Attack on Titan (2013)/Season 03 —— 指向剧或季目录可以显著加快扫描。"
                         : "地址示例：https://jellyfin.example.com")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加 \\(kind.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        isSaving = true
                        Task {
                            if kind == .webdav {
                                await model.addWebDAV(name: name, urlText: Self.join(url, subpath), username: username, password: password)
                            } else {
                                await model.addJellyfin(name: name, urlText: url, username: username, password: password)
                            }
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || url.isEmpty || username.isEmpty)
                }
            }
        }
    }

    /// Appends the optional sub-directory to the server URL, encoding each
    /// segment so Chinese folder names work.
    static func join(_ base: String, _ subpath: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = subpath.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !extra.isEmpty else { return trimmed }
        var result = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        for segment in extra.split(separator: "/") {
            let encoded = String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            result += "/" + encoded
        }
        return result
    }
}
