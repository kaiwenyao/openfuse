import AppKit
import OpenFuseCore
import SwiftUI

struct WebDAVBrowserView: View {
    @EnvironmentObject private var model: AppModel
    let source: WebDAVSource

    @State private var pathStack: [String] = [""]
    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var opening: String?

    private var currentPath: String { pathStack.last ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            content
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            pathStack = model.webdavPath(for: source)
        }
        .onChange(of: pathStack) { _, newValue in
            model.setWebDAVPath(newValue, for: source)
        }
        .task(id: currentPath) {
            await load(path: currentPath)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if pathStack.count > 1 {
                    pathStack.removeLast()
                } else {
                    model.route = .home
                }
            } label: {
                Image(systemName: pathStack.count > 1 ? "chevron.left" : "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.elevated, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(source.baseURL.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    pathStack = [""]
                } label: {
                    Text(source.name)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)

                ForEach(Array(pathStack.indices.dropFirst()), id: \.self) { index in
                    Text("/").foregroundStyle(Theme.secondary.opacity(0.6))
                    Button {
                        pathStack = Array(pathStack.prefix(through: index))
                    } label: {
                        Text((pathStack[index] as NSString).lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == pathStack.count - 1 ? Theme.text : Theme.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.panel, in: Capsule())
            .lineLimit(1)

            Button {
                Task { await load(path: currentPath) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Theme.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            .help("刷新")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            Spacer()
            ProgressView("正在读取目录…")
                .foregroundStyle(Theme.secondary)
            Spacer()
        } else if let errorMessage, entries.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.secondary)
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Button("重试") {
                    Task { await load(path: currentPath) }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        } else if entries.isEmpty {
            Spacer()
            Text("这个目录是空的")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry)
                        Divider().overlay(Theme.stroke.opacity(0.5))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
    }

    private func row(_ entry: RemoteEntry) -> some View {
        Button {
            if entry.isDirectory {
                pathStack.append(entry.path)
            } else if entry.isPlayableVideo {
                opening = entry.path
                Task {
                    await model.openRemote(source: source, entry: entry, siblings: entries)
                    opening = nil
                }
            }
        } label: {
            HStack(spacing: 12) {
                entryIcon(entry)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(entry.isDirectory || entry.isPlayableVideo ? Theme.text : Theme.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if entry.isDirectory {
                            Text("文件夹")
                        } else {
                            Text(byteString(entry.size))
                            if let modified = entry.modifiedAt {
                                Text(modified.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if !entry.isDirectory && !entry.isPlayableVideo {
                            Text(entry.fileExtension.uppercased())
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary.opacity(0.85))
                }
                Spacer()
                if opening == entry.path {
                    ProgressView().controlSize(.small)
                } else if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                } else if entry.isPlayableVideo {
                    Image(systemName: "play.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.isDirectory && !entry.isPlayableVideo)
    }

    private func byteString(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func load(path: String) async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await model.loadDirectory(source: source, path: path)
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
        isLoading = false
    }
}

@ViewBuilder
private func entryIcon(_ entry: RemoteEntry) -> some View {
    if entry.isDirectory {
        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
    } else if entry.isPlayableVideo {
        Image(systemName: "film.fill").foregroundStyle(Theme.warm)
    } else if SubtitleCatalog.subtitleExtensions.contains(entry.fileExtension) {
        Image(systemName: "captions.bubble.fill").foregroundStyle(Theme.secondary)
    } else {
        Image(systemName: "doc.fill").foregroundStyle(Theme.secondary)
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加 WebDAV 来源")
                        .font(.system(size: 18, weight: .semibold))
                    Text("OpenList、Nextcloud、群晖等提供 WebDAV 的服务均可。凭据只保存在本机 Keychain。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            Form {
                TextField("名称", text: $name, prompt: Text("例如：OpenList"))
                TextField("服务器地址", text: $url, prompt: Text("https://example.com:5244/dav/"))
                    .textContentType(.URL)
                TextField("用户名", text: $username)
                SecureField("密码", text: $password)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Text("示例：OpenList 的 WebDAV 根路径通常是 /dav/，百度网盘目录会按原结构显示。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("连接并保存") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy || url.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
    }

    private func submit() async {
        isBusy = true
        errorMessage = nil
        let source = await model.addSource(name: name, urlText: url, username: username, password: password)
        isBusy = false
        if source != nil {
            dismiss()
        } else {
            errorMessage = model.statusMessage ?? "连接失败"
        }
    }
}
