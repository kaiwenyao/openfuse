import OpenFuseData
import SwiftUI

struct MobileSourcesView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var addKind: SourceKind?
    @State private var errorText: String?
    @State private var browsing: WebDAVSource?
    @State private var pendingBrowse: WebDAVSource?

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
                            Button {
                                browsing = source
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.name).font(.headline)
                                        Text(source.baseURL.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)
                                }
                            }
                            .buttonStyle(.plain)
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
                    Text("点按 WebDAV 来源进入目录，只读取当前这一层，不会自动扫描。扫描仍由「扫描」按钮入库。凭据存入 iOS Keychain；密码/token 不写入 sources.json。WebDAV 的 MKV 由 libmpv 直放（外挂 ASS、E-AC-3 下混），MP4/MOV 与 Jellyfin HLS 走 AVPlayer。扫描整个根目录较慢，可把地址填到剧集或季目录（例如 …/电视剧/Attack on Titan (2013)/Season 03）来加快。")
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
            .navigationDestination(item: $browsing) { source in
                MobileWebDAVBrowserView(source: source)
                    .environmentObject(model)
            }
            .onChange(of: addKind?.id) { _, _ in
                guard addKind == nil, let source = pendingBrowse else { return }
                pendingBrowse = nil
                browsing = source
            }
            .sheet(item: $addKind) { kind in
                MobileAddSourceForm(kind: kind) { source in
                    pendingBrowse = source
                }
                .environmentObject(model)
            }
            .task {
                await startBrowseAcceptanceIfRequested()
            }
        }
    }

    /// Simulator-only: prove a bad address stays unsaved, then open the root.
    private func startBrowseAcceptanceIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["OPENFUSE_BROWSE_ACCEPTANCE"] == "1", browsing == nil else { return }
        let refused = await model.addWebDAV(
            name: "无效地址",
            urlText: "http://127.0.0.1:9/dav/",
            username: "u",
            password: "p"
        )
        model.acceptanceContext["connection"] = refused == nil ? (model.status ?? "failed") : "unexpected-success"
        print("BROWSE_PREFLIGHT connection=\(model.acceptanceContext["connection"] ?? "")")
        if env["OPENFUSE_BROWSE_EXPECT_AUTH"] == "1",
           let url = env["OPENFUSE_TEST_WEBDAV_URL"],
           let user = env["OPENFUSE_TEST_WEBDAV_USER"] {
            let denied = await model.addWebDAV(
                name: "错误密码",
                urlText: url,
                username: user,
                password: "definitely-wrong"
            )
            model.acceptanceContext["auth"] = denied == nil ? (model.status ?? "failed") : "unexpected-success"
            model.acceptanceContext["savedAfterAuthFailure"] = model.webdavSources.contains { $0.name == "错误密码" } ? "yes" : "no"
            print("BROWSE_PREFLIGHT auth=\(model.acceptanceContext["auth"] ?? "") saved=\(model.acceptanceContext["savedAfterAuthFailure"] ?? "")")
        }
        guard let url = env["OPENFUSE_TEST_WEBDAV_URL"],
              let user = env["OPENFUSE_TEST_WEBDAV_USER"],
              let password = env["OPENFUSE_TEST_WEBDAV_PASSWORD"] else { return }
        guard let source = await model.addWebDAV(
            name: "验收 WebDAV",
            urlText: url,
            username: user,
            password: password
        ) else {
            model.acceptanceContext["add"] = model.status ?? "failed"
            print("BROWSE_ADD_FAIL \(model.status ?? "")")
            return
        }
        model.acceptanceContext["add"] = "ok"
        print("BROWSE_ADD_OK \(source.id)")
        browsing = source
    }
}

private struct MobileAddSourceForm: View {
    @EnvironmentObject private var model: MobileLibraryModel
    @Environment(\.dismiss) private var dismiss
    let kind: MobileSourcesView.SourceKind
    var onWebDAVSaved: (WebDAVSource) -> Void = { _ in }

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var subpath = ""
    @State private var isSaving = false
    @State private var errorText: String?

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
                         ? "地址示例：https://openlist.example.com/dav/。保存前会读取根目录以确认地址和密码，通过后直接打开该目录，不会扫描入库。子目录例如 电视剧/Attack on Titan (2013)/Season 03。"
                         : "地址示例：https://jellyfin.example.com")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("添加 \(kind.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        isSaving = true
                        errorText = nil
                        Task {
                            if kind == .webdav {
                                if let source = await model.addWebDAV(
                                    name: name,
                                    urlText: Self.join(url, subpath),
                                    username: username,
                                    password: password
                                ) {
                                    onWebDAVSaved(source)
                                    dismiss()
                                } else {
                                    errorText = model.status ?? "连接失败"
                                }
                            } else {
                                await model.addJellyfin(name: name, urlText: url, username: username, password: password)
                                dismiss()
                            }
                            isSaving = false
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
