import OpenFuseData
import SwiftUI

struct MobileSourcesView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var addKind: SourceKind?
    @State private var errorText: String?

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

                Section("说明") {
                    Text("凭据存入 iOS Keychain；密码/token 不写入 sources.json。WebDAV MP4/MOV 走认证资源加载器；Jellyfin MP4 直连，MKV 走服务器 HLS 转码 URL。")
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
                }
                Section {
                    Text(kind == .webdav
                         ? "地址示例：https://openlist.example.com/dav/"
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
                                await model.addWebDAV(name: name, urlText: url, username: username, password: password)
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
}
