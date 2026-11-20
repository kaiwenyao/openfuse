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
    @State private var selectedItem: JellyfinItem?

    private var currentParentID: String? { path.last?.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            content
        }
        .background(Theme.background.ignoresSafeArea())
        .task(id: currentParentID ?? "root") {
            await load()
        }
        .sheet(item: $selectedItem) { item in
            JellyfinDetailView(source: source, item: item)
                .environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if path.isEmpty {
                    model.route = .home
                } else {
                    path.removeLast()
                }
            } label: {
                Image(systemName: path.isEmpty ? "xmark" : "chevron.left")
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
                Button(source.name) { path = [] }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                ForEach(Array(path.enumerated()), id: \.element.id) { index, item in
                    Text("/").foregroundStyle(Theme.secondary.opacity(0.6))
                    Button(item.name) {
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
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 20)],
                    alignment: .leading,
                    spacing: 22
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

    private func card(_ entry: JellyfinItem) -> some View {
        Button {
            if entry.isFolder {
                path.append(entry)
            } else if entry.isPlayable {
                selectedItem = entry
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.elevated)
                    if let imageURL = model.jellyfinImageURL(source: source, item: entry) {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: entry.isFolder ? "folder.fill" : "film.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                    } else {
                        Image(systemName: entry.isFolder ? "folder.fill" : "film.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
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

                Text(entry.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(entry.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.isFolder && !entry.isPlayable)
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

struct JellyfinDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let source: JellyfinSource
    let item: JellyfinItem

    @State private var detail: JellyfinItem?
    @State private var playback: JellyfinPlaybackInfo?
    @State private var selectedSourceID: String?
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var currentDetail: JellyfinItem { detail ?? item }
    private var currentSource: JellyfinMediaSource? {
        guard let playback, !playback.mediaSources.isEmpty else { return nil }
        return playback.mediaSources.first { $0.id == selectedSourceID } ?? playback.mediaSources[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                poster
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentDetail.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if let label = currentDetail.episodeLabel {
                        Text([label, currentDetail.seriesName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    if let year = currentDetail.productionYear {
                        Text("\(year)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                    if let runtime = currentDetail.runTimeTicks, runtime > 0 {
                        Text(Timecode.long(JellyfinTicks.seconds(runtime)))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.secondary)
                    }
                    if let overview = currentDetail.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button("关闭") { dismiss() }
            }

            if let playback, playback.mediaSources.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("版本")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    Picker("版本", selection: Binding(
                        get: { selectedSourceID ?? playback.mediaSources[0].id },
                        set: { selectedSourceID = $0 }
                    )) {
                        ForEach(playback.mediaSources) { media in
                            Text(versionLabel(media)).tag(media.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if let currentSource {
                Text("\(currentSource.name) · \(currentSource.container?.uppercased() ?? "—") · \(versionMethod(currentSource))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                Button("播放") {
                    Task { await play() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy || playback == nil)
            }
        }
        .padding(22)
        .frame(width: 640)
        .background(Theme.background)
        .task { await loadDetail() }
    }

    private var poster: some View {
        Group {
            if let url = model.jellyfinImageURL(source: source, item: currentDetail, maxWidth: 220) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Color.black
                    }
                }
            } else {
                Color.black
            }
        }
        .frame(width: 150, height: 225)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func versionLabel(_ media: JellyfinMediaSource) -> String {
        var parts = [media.name]
        if let container = media.container { parts.append(container.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func versionMethod(_ media: JellyfinMediaSource) -> String {
        if media.supportsDirectPlay == true { return "直连" }
        if media.supportsDirectStream == true { return "重封装" }
        return "转码"
    }

    private func loadDetail() async {
        isBusy = true
        do {
            async let detailTask = model.loadJellyfinItem(source: source, itemID: item.id)
            async let playbackTask = model.loadJellyfinPlaybackInfo(source: source, itemID: item.id)
            detail = try await detailTask
            playback = try await playbackTask
            selectedSourceID = playback?.mediaSources.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func play() async {
        guard let playback, let selectedSourceID else { return }
        isBusy = true
        await model.openJellyfinItem(source: source, itemID: item.id, preferredMediaSourceID: selectedSourceID)
        isBusy = false
        dismiss()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(serverKind == "emby" ? "添加 Emby" : "添加 Jellyfin")
                        .font(.system(size: 18, weight: .semibold))
                    Text("使用独立测试账号。登录令牌保存在本机 Keychain。")
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
            serverKind: serverKind
        )
        isBusy = false
        if source != nil {
            dismiss()
        } else {
            errorMessage = model.statusMessage ?? "登录失败"
        }
    }
}
