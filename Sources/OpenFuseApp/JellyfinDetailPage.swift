import AppKit
import OpenFuseCore
import SwiftUI

/// In-window Jellyfin work page: hero backdrop, season/episode selection,
/// ratings, people and the selected file's technical summary. Selecting an
/// episode only updates this page; playback starts from the play button.
struct JellyfinDetailPage: View {
    @EnvironmentObject private var model: AppModel
    let source: JellyfinSource
    let itemID: String
    let initialEpisodeID: String?
    var onBack: () -> Void

    @State private var item: JellyfinItem?
    @State private var series: JellyfinItem?
    @State private var seasons: [JellyfinItem] = []
    @State private var episodes: [JellyfinItem] = []
    @State private var selectedSeasonID: String?
    @State private var selectedEpisodeID: String?
    @State private var playback: JellyfinPlaybackInfo?
    @State private var selectedSourceID: String?
    @State private var externalRatings: [String] = []
    @State private var externalRatingsFromSeries = false
    @State private var people: [JellyfinPerson] = []
    @State private var peopleFromSeries = false
    @State private var isLoading = true
    @State private var isPlaybackLoading = false
    @State private var playBusy = false
    @State private var errorMessage: String?
    @State private var showMediaInfo = false
    @State private var selectionToken = UUID()

    private var currentItem: JellyfinItem { item ?? placeholderItem }
    private var placeholderItem: JellyfinItem {
        JellyfinItem(id: itemID, name: "", itemType: nil, collectionType: nil, parentID: nil,
                     seriesID: nil, seriesName: nil, seasonID: nil, indexNumber: nil,
                     parentIndexNumber: nil, productionYear: nil, overview: nil,
                     runTimeTicks: nil, imageTags: nil, userData: nil, dateCreated: nil,
                     mediaSources: nil)
    }
    private var isSeries: Bool { series != nil || currentItem.itemType == "Episode" }
    private var currentSource: JellyfinMediaSource? {
        guard let playback, !playback.mediaSources.isEmpty else { return nil }
        return playback.mediaSources.first { $0.id == selectedSourceID }
            ?? playback.mediaSources.first { $0.supportsDirectPlay == true }
            ?? playback.mediaSources[0]
    }
    private var mediaSummary: JellyfinMediaSummary? {
        currentSource.map(JellyfinMediaSummary.init(source:))
    }
    private var heroItem: JellyfinItem {
        if let series, series.backdropImageTag != nil { return series }
        return currentItem
    }
    private var hasBackdrop: Bool {
        model.jellyfinImageURL(source: source, item: heroItem, type: "Backdrop", maxWidth: 1600) != nil
    }
    private var heroTextColor: Color { hasBackdrop ? .white : Theme.text }

    var body: some View {
        Group {
            if isLoading && item == nil {
                Spacer()
                ProgressView("正在读取资料…")
                    .foregroundStyle(Theme.secondary)
                Spacer()
            } else if let errorMessage, item == nil {
                Spacer()
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                    Button("重试") { Task { await loadInitial() } }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            hero
                            if isSeries {
                                seasonSelector
                                episodeStrip
                                    .id("episodes-section")
                            }
                            ratingsSection
                            castSection
                            technicalSection
                                .id("technical-section")
                        }
                        .padding(.bottom, 28)
                    }
                    .onAppear {
                        if ProcessInfo.processInfo.environment["OPENFUSE_DETAIL_SCROLL_TECHNICAL"] == "1" {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo("technical-section", anchor: .bottom)
                                }
                            }
                        } else if initialEpisodeID != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                proxy.scrollTo("episodes-section", anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .task { await loadInitial() }
    }

    // MARK: - Hero

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            wideHero.frame(minWidth: 1000)
            narrowHero
        }
    }

    private var wideHero: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
                .frame(height: 350)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 350)
            heroInfo(textColor: heroTextColor)
                .padding(.horizontal, 26)
                .padding(.bottom, 22)
                .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var narrowHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroBackground
                .frame(height: 190)
                .clipped()
            heroInfo(textColor: Theme.text)
                .padding(18)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let url = model.jellyfinImageURL(
            source: source,
            item: heroItem,
            type: "Backdrop",
            maxWidth: 1600
        ) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallbackHeroBackground
                }
            }
        } else {
            fallbackHeroBackground
        }
    }

    private var fallbackHeroBackground: some View {
        ZStack {
            Theme.panel
            if let poster = model.jellyfinImageURL(
                source: source,
                item: currentItem,
                maxWidth: 400
            ) {
                HStack {
                    AsyncImage(url: poster) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.leading, 24)
                    Spacer()
                }
            }
        }
    }

    private func heroInfo(textColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleText)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(2)
            Text(metadataLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textColor.opacity(0.78))
                .lineLimit(2)
            if let overview = currentItem.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 12))
                    .foregroundStyle(textColor.opacity(0.86))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await play() }
                } label: {
                    Label(playLabel, systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(playback == nil || playBusy)
                if isPlaybackLoading { ProgressView().controlSize(.small).tint(.white) }
                if let source = currentSource {
                    Text(versionText(source))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(textColor.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private var titleText: String {
        if currentItem.itemType == "Episode" {
            return [currentItem.episodeLabel, currentItem.name].compactMap { $0 }.joined(separator: " · ")
        }
        return currentItem.name
    }

    private var metadataLine: String {
        var parts: [String] = []
        if let ticks = currentItem.runTimeTicks, ticks > 0 {
            parts.append(Timecode.long(JellyfinTicks.seconds(ticks)))
        }
        if let release = currentItem.releaseLabel ?? series?.releaseLabel { parts.append(release) }
        if let rating = currentItem.officialRating ?? series?.officialRating, !rating.isEmpty { parts.append(rating) }
        let genres = currentItem.genres ?? series?.genres
        if let genres, !genres.isEmpty { parts.append(genres.joined(separator: " · ")) }
        return parts.joined(separator: "  ·  ")
    }

    private var playLabel: String {
        guard let position = currentItem.userData?.playbackPositionTicks, position > 0 else {
            return "播放"
        }
        return "继续观看"
    }

    private func versionText(_ source: JellyfinMediaSource) -> String {
        source.name.isEmpty ? "当前版本" : source.name
    }

    // MARK: - Seasons and episodes

    @ViewBuilder
    private var seasonSelector: some View {
        if seasons.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("季")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons) { season in
                            Button {
                                Task { await selectSeason(season) }
                            } label: {
                                Text(season.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        selectedSeasonID == season.id ? Theme.accent.opacity(0.18) : Theme.panel,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedSeasonID == season.id ? Theme.accent : Theme.text)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(season.name)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var episodeStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分集")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let selected = episodes.first(where: { $0.id == selectedEpisodeID }) {
                    Text(selected.episodeLabel ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 24)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(episodes) { episode in
                            episodeCard(episode)
                                .id(episode.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 2)
                }
                .onAppear {
                    if let selectedEpisodeID {
                        proxy.scrollTo(selectedEpisodeID, anchor: .center)
                    }
                }
                .onChange(of: selectedEpisodeID) { _, newValue in
                    if let newValue {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func episodeCard(_ episode: JellyfinItem) -> some View {
        let selected = episode.id == selectedEpisodeID
        let progress = watchProgress(episode)
        return Button {
            Task { await selectEpisode(episode) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.elevated)
                    if let url = model.jellyfinImageURL(source: source, item: episode, maxWidth: 480) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Image(systemName: "film.fill").foregroundStyle(Theme.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "film.fill").foregroundStyle(Theme.secondary)
                    }
                    if progress > 0 {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.black.opacity(0.55))
                                Capsule().fill(Theme.accent)
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                    }
                }
                .frame(width: 172, height: 97)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Theme.accent : Color.clear, lineWidth: 2)
                )

                Text([episode.episodeLabel, episode.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.text)
                    .lineLimit(1)
                    .frame(width: 172, alignment: .leading)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                        .frame(width: 172, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(episode.episodeLabel ?? "") \(episode.name)")
    }

    private func watchProgress(_ episode: JellyfinItem) -> Double {
        guard let position = episode.userData?.playbackPositionTicks,
              let duration = episode.runTimeTicks, duration > 0 else { return 0 }
        return min(max(Double(position) / Double(duration), 0), 1)
    }

    // MARK: - Ratings

    private var ratingsSection: some View {
        let chips = ratingChips
        return Group {
            if !chips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("评分")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips, id: \.self) { chip in
                                Text(chip)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Theme.panel, in: Capsule())
                                    .foregroundStyle(Theme.text)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var ratingChips: [String] {
        var chips: [String] = []
        let seriesLabel = "整剧 · "
        if let rating = currentItem.communityRating, rating > 0 {
            chips.append(String(format: "社区评分 %.1f/10", rating))
        } else if let rating = series?.communityRating, rating > 0 {
            chips.append(String(format: "\(seriesLabel)社区评分 %.1f/10", rating))
        }
        if let rating = currentItem.criticRating, rating > 0 {
            chips.append(String(format: "影评人 %.0f%%", rating))
        } else if let rating = series?.criticRating, rating > 0 {
            chips.append(String(format: "\(seriesLabel)影评人 %.0f%%", rating))
        }
        chips.append(contentsOf: externalRatings.map { externalRatingsFromSeries ? "本剧 · \($0)" : $0 })
        return chips
    }

    // MARK: - Cast

    private var castSection: some View {
        Group {
            if !people.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(peopleFromSeries ? "本剧演职员" : "演职员")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(people) { person in
                                personCard(person)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func personCard(_ person: JellyfinPerson) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(Theme.elevated)
                if let url = model.jellyfinPersonImageURL(source: source, person: person) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            personPlaceholder
                        }
                    }
                } else {
                    personPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            Text(person.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
            Text(roleLabel(person))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .frame(width: 72)
    }

    private var personPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(Theme.secondary)
    }

    private func roleLabel(_ person: JellyfinPerson) -> String {
        let type = (person.type ?? "").lowercased()
        let kind: String
        switch type {
        case "director": kind = "导演"
        case "actor": kind = "演员"
        case "writer": kind = "编剧"
        case "producer": kind = "制片"
        default: kind = person.type ?? ""
        }
        if let role = person.role, !role.isEmpty, type == "actor" {
            return "\(kind) · \(role)"
        }
        return kind
    }

    // MARK: - Technical information

    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let playback, playback.mediaSources.count > 1 {
                Text("版本")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Picker("版本", selection: Binding(
                    get: { selectedSourceID ?? playback.mediaSources[0].id },
                    set: { newValue in
                        selectedSourceID = newValue
                        showMediaInfo = false
                        model.setJellyfinDetailSelection(
                            source: source,
                            detailItemID: itemID,
                            seasonID: selectedSeasonID,
                            episodeID: selectedEpisodeID,
                            mediaSourceID: newValue
                        )
                    }
                )) {
                    ForEach(playback.mediaSources) { media in
                        Text(media.name.isEmpty ? media.id : media.name).tag(media.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let summary = mediaSummary {
                Text(summary.shortLine)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                DisclosureGroup("媒体信息", isExpanded: $showMediaInfo) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.detailLines, id: \.0) { pair in
                            HStack(alignment: .top, spacing: 12) {
                                Text(pair.0)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Theme.secondary)
                                    .frame(width: 74, alignment: .leading)
                                Text(pair.1)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                Spacer(minLength: 0)
                            }
                        }
                        if summary.detailLines.isEmpty {
                            Text("服务器没有返回更多参数")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 11.5, weight: .medium))
                .tint(Theme.accent)
            } else if isPlaybackLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取文件参数…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Loading

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        let token = UUID()
        selectionToken = token
        do {
            let base = try await model.loadJellyfinItem(source: source, itemID: itemID)
            guard selectionToken == token else { return }
            item = base
            if base.itemType == "Episode", let seriesID = base.seriesID {
                let seriesDetail = try? await model.loadJellyfinItem(source: source, itemID: seriesID)
                let seasonEntries = (try? await model.loadJellyfinItems(source: source, parentID: seriesID)) ?? []
                guard selectionToken == token else { return }
                series = seriesDetail
                seasons = seasonEntries.filter { $0.itemType == "Season" }
                    .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
                let savedSeason = model.jellyfinSelectedSeasonID(for: source)
                selectedSeasonID = savedSeason
                    ?? base.seasonID
                    ?? seasons.first?.id
                if let seasonID = selectedSeasonID {
                    let seasonEpisodes = (try? await model.loadJellyfinItems(source: source, parentID: seasonID)) ?? []
                    guard selectionToken == token else { return }
                    episodes = seasonEpisodes.filter { $0.itemType == "Episode" }
                        .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
                }
                selectedEpisodeID = episodes.contains(where: { $0.id == initialEpisodeID })
                    ? initialEpisodeID
                    : (episodes.first(where: { $0.id == base.id })?.id ?? episodes.first?.id ?? base.id)
                if let selectedEpisodeID,
                   let selected = episodes.first(where: { $0.id == selectedEpisodeID }) {
                    item = (try? await model.loadJellyfinItem(source: source, itemID: selectedEpisodeID)) ?? selected
                }
            }
            guard selectionToken == token else { return }
            model.setJellyfinDetailSelection(
                source: source,
                detailItemID: itemID,
                seasonID: selectedSeasonID,
                episodeID: selectedEpisodeID,
                mediaSourceID: model.jellyfinSelectedMediaSourceID(for: source)
            )
            await loadPlaybackAndExtras(for: currentItem)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func selectSeason(_ season: JellyfinItem) async {
        let token = UUID()
        selectionToken = token
        selectedSeasonID = season.id
        episodes = []
        let seasonEpisodes = (try? await model.loadJellyfinItems(source: source, parentID: season.id)) ?? []
        guard selectionToken == token else { return }
        episodes = seasonEpisodes.filter { $0.itemType == "Episode" }
            .sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }
        guard let first = episodes.first else {
            selectedEpisodeID = nil
            playback = nil
            return
        }
        selectedEpisodeID = first.id
        item = (try? await model.loadJellyfinItem(source: source, itemID: first.id)) ?? first
        model.setJellyfinDetailSelection(
            source: source,
            detailItemID: itemID,
            seasonID: season.id,
            episodeID: first.id,
            mediaSourceID: model.jellyfinSelectedMediaSourceID(for: source)
        )
        await loadPlaybackAndExtras(for: currentItem)
    }

    private func selectEpisode(_ episode: JellyfinItem) async {
        guard episode.id != selectedEpisodeID else { return }
        let token = UUID()
        selectionToken = token
        selectedEpisodeID = episode.id
        item = (try? await model.loadJellyfinItem(source: source, itemID: episode.id)) ?? episode
        model.setJellyfinDetailSelection(
            source: source,
            detailItemID: itemID,
            seasonID: selectedSeasonID,
            episodeID: episode.id,
            mediaSourceID: model.jellyfinSelectedMediaSourceID(for: source)
        )
        await loadPlaybackAndExtras(for: currentItem)
    }

    private func loadPlaybackAndExtras(for item: JellyfinItem) async {
        let token = UUID()
        selectionToken = token
        isPlaybackLoading = true
        playback = nil
        selectedSourceID = nil
        do {
            let info = try await model.loadJellyfinPlaybackInfo(source: source, itemID: item.id)
            guard selectionToken == token, currentItem.id == item.id else { return }
            playback = info
            let preferred = model.jellyfinSelectedMediaSourceID(for: source)
            selectedSourceID = info.mediaSources.first(where: { $0.id == preferred })?.id
                ?? info.mediaSources.first?.id
            if ProcessInfo.processInfo.environment["OPENFUSE_EXPAND_MEDIA_INFO"] == "1" {
                showMediaInfo = true
            }
            externalRatings = await model.jellyfinExternalRatings(for: item)
            externalRatingsFromSeries = false
            if externalRatings.isEmpty, let series {
                externalRatings = await model.jellyfinExternalRatings(for: series)
                externalRatingsFromSeries = !externalRatings.isEmpty
            }
            guard selectionToken == token else { return }
            if let itemPeople = item.people, !itemPeople.isEmpty {
                people = itemPeople
                peopleFromSeries = false
            } else if let seriesPeople = series?.people, !seriesPeople.isEmpty {
                people = seriesPeople
                peopleFromSeries = true
            } else {
                people = []
                peopleFromSeries = false
            }
        } catch {
            guard selectionToken == token else { return }
            errorMessage = error.localizedDescription
        }
        isPlaybackLoading = false
        writeDebugState()
    }

    private func writeDebugState() {
        guard ProcessInfo.processInfo.environment["OPENFUSE_DEBUG_JELLYFIN_DETAIL"] == "1" else { return }
        var payload: [String: Any] = [
            "title": currentItem.name,
            "itemID": currentItem.id,
            "selectedEpisodeID": selectedEpisodeID ?? "",
            "selectedSeasonID": selectedSeasonID ?? "",
            "selectedMediaSourceID": selectedSourceID ?? "",
            "playTargetItemID": currentItem.id,
            "isSeries": isSeries,
            "people": people.map { ["name": $0.name, "role": $0.role ?? "", "type": $0.type ?? ""] },
            "ratings": ratingChips,
        ]
        if let summary = mediaSummary {
            payload["shortLine"] = summary.shortLine
            payload["details"] = summary.detailLines.map { [$0.0, $0.1] }
        }
        let dir = model.acceptanceDirectory()
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("jellyfin-detail.json"), options: .atomic)
        }
    }

    private func play() async {
        guard let playback, let selectedSourceID else { return }
        playBusy = true
        await model.openJellyfinItem(
            source: source,
            itemID: currentItem.id,
            preferredMediaSourceID: selectedSourceID
        )
        playBusy = false
    }
}
