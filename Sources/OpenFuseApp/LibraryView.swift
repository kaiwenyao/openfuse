import AppKit
import OpenFuseCore
import SwiftUI

struct LibraryPoster: View {
    @EnvironmentObject private var model: AppModel
    let work: LibraryWork

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.4, brightness: 0.35),
                            Color(hue: hue + 0.08, saturation: 0.5, brightness: 0.16),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let parsed = PosterRef.parse(work.poster) {
                switch parsed.kind {
                case "jellyfin":
                    if let url = model.jellyfinPosterURL(sourceID: work.sourceID, itemID: parsed.value, tag: parsed.extra) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            default:
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                case "file":
                    if let image = NSImage(contentsOfFile: parsed.value) {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        placeholder
                    }
                case "remote":
                    if let url = URL(string: parsed.value) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            default:
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                default:
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: work.kind == .movie ? "film" : "tv")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
            Text(work.title)
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .lineLimit(3)
        }
    }

    private var hue: Double {
        Double(abs(work.title.hashValue % 360)) / 360.0
    }
}

struct LibraryCard: View {
    @EnvironmentObject private var model: AppModel
    let group: LibraryGroup

    private var work: LibraryWork { group.primary }

    var body: some View {
        Button {
            model.route = .library(work)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                LibraryPoster(work: work)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text(work.kind == .movie ? "电影" : "剧集")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(8)
                    }
                Text(work.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let year = work.year { parts.append(String(year)) }
        if work.kind == .series {
            if work.seasonCount > 0 { parts.append("\(work.seasonCount) 季") }
            if work.episodeCount > 0 { parts.append("\(work.episodeCount) 集") }
        } else if let version = model.libraryVersions(itemID: work.id + "-main").first {
            parts.append(version.name)
        }
        if group.works.count > 1 {
            parts.append(group.sourceLabel)
        } else if parts.isEmpty {
            parts.append(work.sourceKind == "jellyfin" ? "Jellyfin" : (work.sourceKind == "webdav" ? "WebDAV" : "本地"))
        }
        return parts.joined(separator: " · ")
    }
}

struct LibraryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let work: LibraryWork

    @State private var seasons: [LibrarySeason] = []
    @State private var episodes: [LibraryEpisode] = []
    @State private var selectedSeasonID: String?
    @State private var versions: [LibraryVersion] = []
    @State private var selectedVersionID: String?
    @State private var isLoading = true
    @State private var selectedWorkID: String?

    private var group: LibraryGroup? { model.group(for: work) }
    private var activeWork: LibraryWork {
        guard let selectedWorkID else { return group?.primary ?? work }
        return group?.works.first { $0.id == selectedWorkID } ?? group?.primary ?? work
    }

    private var currentEpisode: LibraryEpisode? {
        episodes.first
    }

    private var currentVersions: [LibraryVersion] {
        if !versions.isEmpty { return versions }
        guard let episode = currentEpisode else { return [] }
        return model.libraryVersions(itemID: episode.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                HStack(alignment: .top, spacing: 26) {
                    LibraryPoster(work: activeWork)
                        .frame(width: 210, height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(activeWork.title)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        HStack(spacing: 8) {
                            if let year = activeWork.year { Text(String(year)) }
                            Text(activeWork.kind == .movie ? "电影" : "剧集")
                            Text(activeWork.sourceKind == "jellyfin" ? "Jellyfin" : (activeWork.sourceKind == "webdav" ? "WebDAV" : "本地"))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)

                        if let group, group.works.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(group.works) { candidate in
                                    Button {
                                        selectedWorkID = candidate.id
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(sourceLabel(candidate.sourceKind))
                                            Text("\(candidate.episodeCount)")
                                                .foregroundStyle(Theme.secondary)
                                        }
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            activeWork.id == candidate.id ? Theme.accent.opacity(0.25) : Theme.panel,
                                            in: Capsule()
                                        )
                                        .overlay(Capsule().stroke(
                                            activeWork.id == candidate.id ? Theme.accent : Theme.stroke,
                                            lineWidth: 1
                                        ))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(activeWork.id == candidate.id ? Theme.accent : Theme.secondary)
                                }
                            }
                        }

                        if let overview = activeWork.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(activeWork.kind == .movie ? "本地视频文件" : "\(activeWork.seasonCount) 季 · \(activeWork.episodeCount) 集")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.secondary)
                        }

                        if activeWork.kind == .movie {
                            movieControls
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(28)

                if activeWork.kind == .series {
                    episodeSection
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await load() }
        .onChange(of: selectedWorkID) { _, _ in
            Task { await load() }
        }
        .onChange(of: selectedSeasonID) { _, newValue in
            guard let newValue else { return }
            episodes = model.libraryEpisodes(workID: activeWork.id, seasonID: newValue)
            if let episode = episodes.first {
                versions = model.libraryVersions(itemID: episode.id)
                selectedVersionID = versions.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.route = .home
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.elevated, in: Circle())
            }
            .buttonStyle(.plain)
            Text("媒体库")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var movieControls: some View {
        if isLoading {
            ProgressView().controlSize(.small)
        } else if let episode = currentEpisode {
            VStack(alignment: .leading, spacing: 8) {
                if currentVersions.count > 1 {
                    Picker("版本", selection: Binding(
                        get: { selectedVersionID ?? currentVersions[0].id },
                        set: { selectedVersionID = $0 }
                    )) {
                        ForEach(currentVersions) { version in
                            Text(version.name).tag(version.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 460)
                }
                Button {
                    let version = currentVersions.first { $0.id == selectedVersionID } ?? currentVersions.first
                    model.playLibrary(work: activeWork, episode: episode, version: version)
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.background)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("剧集")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if seasons.count > 1 {
                    Picker("季", selection: Binding(
                        get: { selectedSeasonID ?? seasons[0].id },
                        set: { selectedSeasonID = $0 }
                    )) {
                        ForEach(seasons) { season in
                            Text(season.title).tag(season.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }
            ForEach(episodes.sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }) { episode in
                HStack(spacing: 12) {
                    Text(episode.episodeLabel ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                        if let overview = episode.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        model.playLibrary(work: activeWork, episode: episode)
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func sourceLabel(_ kind: String) -> String {
        switch kind {
        case "jellyfin": return "Jellyfin"
        case "webdav": return "WebDAV"
        default: return "本地"
        }
    }

    private func load() async {
        isLoading = true
        seasons = model.librarySeasons(workID: activeWork.id)
        if let first = seasons.first {
            selectedSeasonID = first.id
            episodes = model.libraryEpisodes(workID: activeWork.id, seasonID: first.id)
        } else {
            episodes = model.libraryEpisodes(workID: activeWork.id)
        }
        if let episode = episodes.first {
            versions = model.libraryVersions(itemID: episode.id)
            selectedVersionID = versions.first?.id
        }
        isLoading = false
    }
}
