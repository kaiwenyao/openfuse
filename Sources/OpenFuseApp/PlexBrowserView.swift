import OpenFuseCore
import SwiftUI

struct PlexBrowserView: View {
    @EnvironmentObject private var model: AppModel
    let source: PlexSource

    @State private var path = NavigationPath()
    @State private var sections: [PlexSection] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 18)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text("Plex Direct · \(source.baseURL.absoluteString)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button("关闭") { model.route = .home }
                            .buttonStyle(.bordered)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    if isLoading {
                        ProgressView().tint(Theme.accent)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(sections) { section in
                            NavigationLink(value: section) {
                                PlexSectionCard(section: section)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(34)
            }
            .background(Theme.background)
            .navigationDestination(for: PlexSection.self) { section in
                PlexSectionView(source: source, section: section)
                    .environmentObject(model)
            }
            .navigationDestination(for: PlexMetadata.self) { metadata in
                PlexMetadataView(source: source, metadata: metadata)
                    .environmentObject(model)
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard sections.isEmpty else { return }
        guard let client = model.plexClient(for: source) else {
            errorText = "缺少 Plex token"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sections = try await client.sections()
            if let key = ProcessInfo.processInfo.environment["OPENFUSE_PLEX_SECTION"],
               let section = sections.first(where: { $0.key == key }) {
                path.append(section)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct PlexSectionCard: View {
    let section: PlexSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panel)
                .frame(height: 118)
                .overlay {
                    Image(systemName: section.type == "movie" ? "film.stack" : "tv")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(section.type == "movie" ? "电影库" : "电视剧库")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
        }
    }
}

private struct PlexSectionView: View {
    @EnvironmentObject private var model: AppModel
    let source: PlexSource
    let section: PlexSection

    @State private var items: [PlexMetadata] = []
    @State private var loading = true
    @State private var errorText: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(section.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                if let errorText { Text(errorText).foregroundStyle(.orange) }
                if loading { ProgressView().tint(Theme.accent) }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 8) {
                                PlexThumb(source: source, item: item)
                                    .frame(height: 230)
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)
                                if let year = item.year {
                                    Text(String(year)).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(30)
        }
        .background(Theme.background)
        .task { await load() }
    }

    private func load() async {
        guard items.isEmpty else { loading = false; return }
        guard let client = model.plexClient(for: source) else { errorText = "缺少 Plex token"; loading = false; return }
        do {
            items = try await client.items(sectionKey: section.key)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

private struct PlexMetadataView: View {
    @EnvironmentObject private var model: AppModel
    let source: PlexSource
    let metadata: PlexMetadata

    @State private var children: [PlexMetadata] = []
    @State private var loading = true
    @State private var errorText: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    PlexThumb(source: source, item: metadata)
                        .frame(width: 170, height: 250)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(metadata.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.text)
                        if let year = metadata.year {
                            Text(String(year)).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        }
                        if let summary = metadata.summary {
                            Text(summary)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(5)
                        }
                        if isPlayable {
                            Button {
                                Task { await model.openPlexMetadata(metadata, source: source) }
                            } label: {
                                Label("播放", systemImage: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Theme.accent, in: Capsule())
                                    .foregroundStyle(Theme.background)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.orange) }
                if loading { ProgressView().tint(Theme.accent) }
                if !children.isEmpty {
                    Text(metadata.type == "show" ? "季" : "集")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(children) { child in
                            NavigationLink(value: child) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if child.type == "episode" {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Theme.panel)
                                            .frame(height: 98)
                                            .overlay {
                                                VStack(spacing: 4) {
                                                    Text(child.episodeLabel ?? "集")
                                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                                    Text(child.title)
                                                        .font(.system(size: 10))
                                                        .lineLimit(2)
                                                }
                                                .foregroundStyle(Theme.text)
                                                .multilineTextAlignment(.center)
                                                .padding(6)
                                            }
                                    } else {
                                        PlexThumb(source: source, item: child)
                                            .frame(height: 220)
                                    }
                                    Text(child.episodeLabel ?? "集")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.accent)
                                    Text(child.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(30)
        }
        .background(Theme.background)
        .task { await load() }
    }

    private var isPlayable: Bool {
        metadata.type == "movie" || metadata.type == "episode"
    }

    private func load() async {
        guard children.isEmpty else { loading = false; return }
        guard let client = model.plexClient(for: source) else { errorText = "缺少 Plex token"; loading = false; return }
        do {
            children = try await client.children(ratingKey: metadata.ratingKey)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

private struct PlexThumb: View {
    @EnvironmentObject private var model: AppModel
    let source: PlexSource
    let item: PlexMetadata

    var body: some View {
        Group {
            if let url = model.plexPosterURL(sourceID: source.id, itemID: item.ratingKey) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }

    private var placeholder: some View {
        Image(systemName: "play.rectangle.on.rectangle")
            .font(.system(size: 26))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension PlexMetadata {
    var episodeLabel: String? {
        guard let index, index > 0 else { return nil }
        if let parentIndex { return String(format: "S%02dE%02d", parentIndex, index) }
        return String(format: "E%02d", index)
    }
}
