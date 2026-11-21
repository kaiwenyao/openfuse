import AppKit
import OpenFuseCore
import SwiftUI

struct JellyfinBrowserView: View {
    @EnvironmentObject private var model: AppModel
    let source: JellyfinSource

    @State private var path: [JellyfinItem] = []
    @State private var entries: [JellyfinItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var detailItemID: String?
    @State private var detailEpisodeID: String?

    private var currentParentID: String? { path.last?.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            if let detailItemID {
                JellyfinDetailPage(
                    source: source,
                    itemID: detailItemID,
                    initialEpisodeID: detailEpisodeID,
                    onBack: {
                        self.detailItemID = nil
                        self.detailEpisodeID = nil
                        model.setJellyfinDetailSelection(source: source, detailItemID: nil)
                    }
                )
            } else {
                content
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            path = model.jellyfinPath(for: source)
            detailItemID = model.jellyfinDetailItemID(for: source)
            detailEpisodeID = model.jellyfinSelectedEpisodeID(for: source)
        }
        .onChange(of: path) { _, newValue in
            model.setJellyfinPath(newValue, for: source)
        }
        .task(id: currentParentID ?? "root") {
            guard detailItemID == nil else { return }
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if detailItemID != nil {
                    detailItemID = nil
                    detailEpisodeID = nil
                    model.setJellyfinDetailSelection(source: source, detailItemID: nil)
                } else if path.isEmpty {
                    model.route = .home
                } else {
                    path.removeLast()
                }
            } label: {
                Image(systemName: (detailItemID == nil && path.isEmpty) ? "xmark" : "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.elevated, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Text(source.kind == "emby" ? "Emby Direct" : "Jellyfin Direct")
                    Text("·")
                    Text(source.baseURL.absoluteString)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Button(source.name) {
                    detailItemID = nil
                    path = []
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                    Text("/").foregroundStyle(Theme.secondary.opacity(0.6))
                    Button(item.name) {
                        detailItemID = nil
                        path = Array(path.prefix(through: index))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == path.count - 1 ? Theme.text : Theme.secondary)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.panel, in: Capsule())
            .lineLimit(1)

            Button {
                Task { await load() }
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
            ProgressView("正在读取 Jellyfin…")
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
                Button("重试") { Task { await load() } }
                    .buttonStyle(.bordered)
            }
            Spacer()
        } else if entries.isEmpty {
            Spacer()
            Text("这个媒体库是空的")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 20)],
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(entries) { entry in
                        card(entry)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    /// Library entries and episodes use 16:9 art; movies and show posters use
    /// 2:3. The aspect container belongs to the grid cell so an AsyncImage's
    /// intrinsic size can never stretch across neighbouring columns.
    private func cardAspect(_ entry: JellyfinItem) -> CGFloat {
        switch entry.itemType {
        case "Movie", "Series", "Season":
            return 2.0 / 3.0
        default:
            return 16.0 / 9.0
        }
    }

    private func card(_ entry: JellyfinItem) -> some View {
        Button {
            if entry.isFolder {
                guard !isLoading, path.last?.id != entry.id else { return }
                path.append(entry)
            } else if entry.isPlayable {
                detailItemID = entry.id
                detailEpisodeID = entry.itemType == "Episode" ? entry.id : nil
                model.setJellyfinDetailSelection(
                    source: source,
                    detailItemID: entry.id,
                    seasonID: entry.seasonID,
                    episodeID: detailEpisodeID
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.elevated)
                    if let imageURL = model.jellyfinImageURL(
                        source: source,
                        item: entry,
                        maxWidth: entry.itemType == "Movie" || entry.itemType == "Series" ? 400 : 640
                    ) {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            case .failure:
                                placeholderIcon(entry)
                            default:
                                ProgressView().controlSize(.small)
                            }
                        }
                    } else {
                        placeholderIcon(entry)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(cardAspect(entry), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    if entry.isPlayable {
                        Text(entry.episodeLabel ?? (entry.productionYear.map(String.init) ?? "播放"))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(9)
                    }
                }
                .clipped()

                Text(entry.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.isFolder && !entry.isPlayable)
        .accessibilityLabel("\(entry.name) \(entry.subtitle)")
    }

    @ViewBuilder
    private func placeholderIcon(_ entry: JellyfinItem) -> some View {
        Image(systemName: entry.isFolder ? "folder.fill" : "film.fill")
            .font(.system(size: 28))
            .foregroundStyle(Theme.secondary)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            if let parent = currentParentID {
                entries = try await model.loadJellyfinItems(source: source, parentID: parent)
            } else {
                entries = try await model.loadJellyfinViews(source: source)
            }
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
        isLoading = false
    }
}

struct AddJellyfinSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var serverKind = "jellyfin"
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var sessionOnly = CredentialStore.defaultMode == .session

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(serverKind == "emby" ? "添加 Emby" : "添加 Jellyfin")
                        .font(.system(size: 18, weight: .semibold))
                    Text("登录令牌默认存入本机 Keychain；密码本身不会写入任何文件。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            Form {
                Picker("类型", selection: $serverKind) {
                    Text("Jellyfin").tag("jellyfin")
                    Text("Emby").tag("emby")
                }
                .pickerStyle(.segmented)
                TextField("名称", text: $name, prompt: Text(serverKind == "emby" ? "例如：家里 Emby" : "例如：家里 Jellyfin"))
                TextField("服务器地址", text: $url, prompt: Text("http://192.168.1.10:8096"))
                    .textContentType(.URL)
                TextField("用户名", text: $username)
                SecureField("密码", text: $password)
                Toggle("仅本次会话（令牌不写入 Keychain）", isOn: $sessionOnly)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Text("使用 `/Users/AuthenticateByName` 登录；不会把密码写入 sources.json。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                Button("登录并保存") {
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
        let source = await model.addJellyfinSource(
            name: name,
            urlText: url,
            username: username,
            password: password,
            serverKind: serverKind,
            rememberInKeychain: !sessionOnly
        )
        isBusy = false
        if source != nil {
            dismiss()
        } else {
            errorMessage = model.statusMessage ?? "登录失败"
        }
    }
}
