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

    @State private var mergedEpisodes: [MergedLibraryEpisode] = []
    @State private var selectedSeasonNumber: Int?
    @State private var selectedVersionID: String?
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showMerge = false

    private var group: LibraryGroup? { model.group(for: work) }
    private var primary: LibraryWork {
        model.currentWork(id: work.id) ?? group?.primary ?? work
    }
    private var isMovie: Bool { primary.kind == .movie }

    private var seasonNumbers: [Int] {
        Array(Set(mergedEpisodes.filter { $0.seasonNumber > 0 }.map(\.seasonNumber))).sorted()
    }

    private var visibleEpisodes: [MergedLibraryEpisode] {
        if isMovie { return mergedEpisodes }
        guard let season = selectedSeasonNumber else { return mergedEpisodes }
        return mergedEpisodes.filter { $0.seasonNumber == season }
    }

    private var movieVersions: [MergedLibraryVersion] {
        mergedEpisodes.first?.versions ?? []
    }

    private var selectedMovieVersion: MergedLibraryVersion? {
        movieVersions.first { $0.id == selectedVersionID } ?? movieVersions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                HStack(alignment: .top, spacing: 26) {
                    LibraryPoster(work: primary)
                        .frame(width: 210, height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 12) {
                        Text(primary.title)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        HStack(spacing: 8) {
                            if let year = primary.year { Text(String(year)) }
                            Text(isMovie ? "电影" : "剧集")
                            if let group, group.works.count > 1 {
                                Text(group.sourceLabel)
                            } else {
                                Text(primary.sourceKind == "jellyfin" ? "Jellyfin" : (primary.sourceKind == "webdav" ? "WebDAV" : "本地"))
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)

                        if let overview = primary.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(isMovie ? "本地视频文件" : "\(primary.seasonCount) 季 · \(primary.episodeCount) 集")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.secondary)
                        }

                        if isMovie {
                            movieControls
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(28)

                if !isMovie {
                    episodeSection
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $showEdit) {
            LibraryEditView(work: primary)
                .environmentObject(model)
        }
        .sheet(isPresented: $showMerge) {
            LibraryMergeView(current: primary)
                .environmentObject(model)
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
            HStack(spacing: 12) {
                if let group, group.works.count > 1 || model.libraryOverrides[primary.id]?.mergeGroupID != nil {
                    Button {
                        model.splitWork(primary)
                    } label: {
                        Label("拆分", systemImage: "scissors")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                }
                if model.libraryOverrides[primary.id]?.mergeGroupID != nil {
                    Button {
                        model.clearGrouping(workID: primary.id)
                    } label: {
                        Label("恢复自动", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                }
                Button {
                    showMerge = true
                } label: {
                    Label("合并到…", systemImage: "arrow.triangle.merge")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                Button {
                    showEdit = true
                } label: {
                    Label("编辑信息", systemImage: "pencil")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var movieControls: some View {
        if isLoading {
            ProgressView().controlSize(.small)
        } else if !movieVersions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if movieVersions.count > 1 {
                    Picker("版本", selection: Binding(
                        get: { selectedVersionID ?? movieVersions[0].id },
                        set: { selectedVersionID = $0 }
                    )) {
                        ForEach(movieVersions) { version in
                            Text(version.label).tag(version.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 620)
                }
                Button {
                    if let selectedMovieVersion {
                        model.playMergedVersion(selectedMovieVersion)
                    }
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.background)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("剧集")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(mergedEpisodes.count) 集 · \(Set(mergedEpisodes.flatMap { $0.versions.map(\.work.sourceKind) }).count) 个来源")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if seasonNumbers.count > 1 {
                    Picker("季", selection: Binding(
                        get: { selectedSeasonNumber ?? seasonNumbers[0] },
                        set: { selectedSeasonNumber = $0 }
                    )) {
                        ForEach(seasonNumbers, id: \.self) { number in
                            Text("第 \(number) 季").tag(number)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }
            ForEach(visibleEpisodes) { episode in
                HStack(spacing: 12) {
                    Text(episode.episodeLabel ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 56, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(episode.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.text)
                            if episode.versions.count > 1 {
                                Text("\(episode.versions.count) 个版本")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Theme.elevated, in: Capsule())
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        if let overview = episode.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Menu {
                        ForEach(episode.versions) { version in
                            Button(version.label) {
                                model.playMergedVersion(version)
                            }
                        }
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(10)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func load() async {
        isLoading = true
        let group = model.group(for: work) ?? LibraryGroup(
            id: work.id, key: work.mergeKey, primary: work, works: [work]
        )
        mergedEpisodes = model.mergedEpisodes(for: group)
        if let firstSeason = mergedEpisodes.first(where: { $0.seasonNumber > 0 })?.seasonNumber {
            selectedSeasonNumber = firstSeason
        }
        selectedVersionID = mergedEpisodes.first?.versions.first?.id
        isLoading = false
    }
}


struct LibraryEditView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let work: LibraryWork

    @State private var title: String
    @State private var year: String
    @State private var overview: String
    @State private var poster: String
    @State private var candidates: [TMDBMatch] = []
    @State private var isSearching = false

    init(work: LibraryWork) {
        self.work = work
        _title = State(initialValue: work.title)
        _year = State(initialValue: work.year.map(String.init) ?? "")
        _overview = State(initialValue: work.overview ?? "")
        var posterValue = ""
        if let parsed = PosterRef.parse(work.poster), parsed.kind != "jellyfin" {
            posterValue = parsed.value
        }
        _poster = State(initialValue: posterValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("编辑媒体信息")
                        .font(.system(size: 17, weight: .semibold))
                    Text("仅修改本地媒体库，不改服务器或文件名。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }

            Form {
                TextField("标题", text: $title)
                TextField("年份", text: $year, prompt: Text("2026"))
                TextField("海报 URL 或本地路径", text: $poster, prompt: Text("https://… 或 /Users/…/poster.jpg"))
                TextField("简介", text: $overview, axis: .vertical)
                    .lineLimit(4...8)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button {
                    Task { await searchTMDB() }
                } label: {
                    Label("搜索 TMDB 候选", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(isSearching || !model.tmdbAvailable)
                if isSearching { ProgressView().controlSize(.small) }
                if !model.tmdbAvailable {
                    Text("设置 OPENFUSE_TMDB_API_KEY 后可用")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("候选（点击填入字段）")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    ForEach(candidates, id: \.id) { match in
                        Button {
                            title = match.title
                            if let matchYear = match.year { year = String(matchYear) }
                            if let overview = match.overview { self.overview = overview }
                            if let url = model.tmdbImageURL(path: match.posterPath) {
                                poster = url.absoluteString
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(match.title) \(match.year.map { "(\($0))" } ?? "")")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                    if let overview = match.overview {
                                        Text(overview)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Theme.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text("#\(match.id)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.secondary)
                            }
                            .padding(8)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("清除本地覆盖", role: .destructive) {
                    model.clearOverride(workID: work.id)
                    dismiss()
                }
                Spacer()
                Button("保存") {
                    model.setOverride(
                        workID: work.id,
                        title: title,
                        year: Int(year),
                        overview: overview,
                        poster: poster.isEmpty ? nil : poster
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
        .background(Theme.background)
    }

    private func searchTMDB() async {
        isSearching = true
        let yearValue = Int(year)
        candidates = await model.searchTMDBCandidates(
            title: title,
            year: yearValue,
            kind: work.kind
        )
        isSearching = false
    }
}


struct LibraryMergeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let current: LibraryWork
    @State private var search = ""

    private var currentKey: String { model.groupKey(for: current) }

    private var candidates: [LibraryWork] {
        model.libraryWorks
            .filter { $0.kind == current.kind }
            .filter { model.groupKey(for: $0) != currentKey }
            .filter {
                search.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.overview ?? "").localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("合并到另一部作品")
                        .font(.system(size: 17, weight: .semibold))
                    Text("把《\(current.title)》及其来源/版本并入所选作品；不会修改文件或服务器。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
            }
            TextField("搜索作品", text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(candidates) { candidate in
                        Button {
                            model.mergeWork(current, into: candidate)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                    Text("\(candidate.kind == .movie ? "电影" : "剧集") · \(candidate.sourceKind)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.merge")
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(10)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.background)
    }
}
