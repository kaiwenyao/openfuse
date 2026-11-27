import OpenFuseData
import SwiftUI

/// On-demand WebDAV / OpenList browser. One PROPFIND (Depth 1) per directory,
/// using the same path rules as the Mac browser.
struct MobileWebDAVBrowserView: View {
    @EnvironmentObject private var model: MobileLibraryModel
    let source: WebDAVSource

    @State private var nav = RemotePathState()
    @State private var entries: [RemoteEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playError: String?
    @State private var opening: String?
    /// A listing that finishes after the user has moved on must not replace the
    /// directory now on screen.
    @State private var loadToken = UUID()
    @State private var loadGeneration = 0
    @State private var didStartAcceptance = false
    @State private var playPhase: AcceptancePlayPhase = .idle
    @State private var probedMP4: MobilePlaybackItem?
    @State private var probedMKV: MobilePlaybackItem?
    @State private var didScheduleScan = false

    private var currentPath: String { nav.path }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            fileList
        }
        .navigationTitle(nav.isRoot ? source.name : RemotePath.displayName(nav.stack.last ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(path: currentPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("刷新")
            }
        }
        .onChange(of: nav.path) { _, _ in
            loadToken = UUID()
            entries = []
            errorMessage = nil
            playError = nil
        }
        .task(id: currentPath) {
            await load(path: currentPath)
        }
        .task {
            await runAcceptanceScriptIfRequested()
        }
        .onChange(of: model.browserPlayback?.url) { _, url in
            guard url == nil else { return }
            advanceAcceptancePlayback()
        }
    }

    private var pathBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    pathButton(source.name, index: 0)
                    ForEach(Array(nav.stack.indices.dropFirst()), id: \.self) { index in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        pathButton(RemotePath.displayName(nav.stack[index]), index: index)
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 16) {
                Button("上一级") { _ = nav.up() }
                    .disabled(nav.isRoot)
                Button("根目录") { _ = nav.reset() }
                    .disabled(nav.isRoot)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            if let playError {
                Text(playError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func pathButton(_ title: String, index: Int) -> some View {
        let current = index == nav.stack.count - 1
        return Button {
            if index == 0 {
                _ = nav.reset()
            } else {
                _ = nav.jump(to: index)
            }
        } label: {
            Text(title)
                .font(.caption.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
        .disabled(current)
    }

    @ViewBuilder
    private var fileList: some View {
        if isLoading && entries.isEmpty && errorMessage == nil {
            ProgressView("正在读取目录…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, entries.isEmpty {
            ContentUnavailableView {
                Label("无法读取目录", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") {
                    Task { await load(path: currentPath) }
                }
                .buttonStyle(.bordered)
            }
        } else if entries.isEmpty {
            ContentUnavailableView("这个目录是空的", systemImage: "folder", description: Text("没有文件，也没有文件夹。"))
        } else {
            List(entries) { entry in
                row(entry)
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await load(path: currentPath)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: RemoteEntry) -> some View {
        if entry.isDirectory {
            Button {
                openFolder(entry)
            } label: {
                rowLabel(entry)
            }
            .disabled(isLoading)
            .accessibilityHint("打开文件夹")
        } else if entry.isPlayableVideo {
            Button {
                Task { await play(entry) }
            } label: {
                rowLabel(entry)
            }
            .disabled(opening != nil)
            .accessibilityHint("播放")
        } else {
            rowLabel(entry)
                .accessibilityHint("不可播放")
        }
    }

    private func rowLabel(_ entry: RemoteEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(entry))
                .font(.body.weight(.semibold))
                .foregroundStyle(entry.isDirectory || entry.isPlayableVideo ? Color.cyan : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isDirectory ? entry.folderDisplayName : entry.baseName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(typeLabel(entry))
                    if !entry.isDirectory, entry.size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    }
                    if let modified = entry.modifiedAt {
                        Text(modified.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if opening == entry.path {
                ProgressView()
                    .controlSize(.small)
            } else if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else if entry.isPlayableVideo {
                Image(systemName: "play.circle")
                    .font(.body)
                    .foregroundStyle(.cyan)
            }
        }
        .contentShape(Rectangle())
    }

    /// Clicks during a listing are ignored, and `RemotePathState` refuses to
    /// stack the same path twice.
    private func openFolder(_ entry: RemoteEntry) {
        guard nav.enter(entry.path, busy: isLoading || opening != nil) else { return }
    }

    private func play(_ entry: RemoteEntry) async {
        guard opening == nil else { return }
        opening = entry.path
        defer { opening = nil }
        if let item = await model.remotePlaybackItem(source: source, entry: entry, siblings: entries) {
            playError = nil
            model.browserPlayback = item
        } else {
            playError = model.status ?? "无法播放 \(entry.baseName)"
        }
    }

    private func load(path: String) async {
        let token = UUID()
        loadToken = token
        loadGeneration += 1
        isLoading = true
        errorMessage = nil
        do {
            let listing = try await model.loadWebDAVDirectory(source: source, path: path)
            guard loadToken == token, !Task.isCancelled else { return }
            entries = listing
        } catch is CancellationError {
            return
        } catch {
            guard loadToken == token, !Task.isCancelled else { return }
            entries = []
            errorMessage = error.localizedDescription
        }
        guard loadToken == token else { return }
        isLoading = false
    }

    private func iconName(_ entry: RemoteEntry) -> String {
        if entry.isDirectory { return "folder.fill" }
        if entry.isPlayableVideo { return "film.fill" }
        switch entry.fileExtension {
        case "ass", "ssa", "srt", "vtt", "sup", "pgs": return "captions.bubble.fill"
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp": return "photo"
        case "pdf": return "doc.richtext"
        case "nfo", "txt", "xml": return "doc.text"
        case "zip", "rar", "7z", "tar", "gz", "bz2": return "doc.zipper"
        default: return "doc"
        }
    }

    private func typeLabel(_ entry: RemoteEntry) -> String {
        if entry.isDirectory { return "文件夹" }
        let ext = entry.fileExtension
        if entry.isPlayableVideo { return ext.isEmpty ? "视频" : "视频 · \(ext.uppercased())" }
        switch ext {
        case "ass", "ssa", "srt", "vtt", "sup", "pgs": return "字幕 · \(ext.uppercased())"
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp": return "图片 · \(ext.uppercased())"
        case "pdf": return "PDF"
        case "nfo": return "NFO"
        case "zip", "rar", "7z", "tar", "gz", "bz2": return "压缩包 · \(ext.uppercased())"
        case "": return "未知"
        default: return ext.uppercased()
        }
    }
}

private enum AcceptancePlayPhase {
    case idle, mp4, mkv, done
}

extension MobileWebDAVBrowserView {
    /// Drives the real browser when a simulator acceptance launch asks for it.
    /// Normal use never enters this path.
    private func runAcceptanceScriptIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard !didStartAcceptance, env["OPENFUSE_BROWSE_ACCEPTANCE"] == "1" else { return }
        didStartAcceptance = true
        let commands = (env["OPENFUSE_BROWSE_SCRIPT"] ?? "")
            .split(separator: "|")
            .map { String($0) }
            .filter { !$0.isEmpty }
        var steps: [[String: Any]] = []
        await waitForLoad(after: 0)
        steps.append(snapshot(command: "open"))
        var probes: [[String: Any]] = []
        for command in commands {
            let generation = loadGeneration
            let pathBefore = nav.path
            if command == "probe" {
                probes = await probeVideos()
            } else if command == "up" {
                _ = nav.up()
            } else if command == "root" {
                _ = nav.reset()
            } else if command.hasPrefix("jump:"), let index = Int(command.dropFirst("jump:".count)) {
                _ = nav.jump(to: index)
            } else if command.hasPrefix("enter:") {
                let path = String(command.dropFirst("enter:".count))
                _ = nav.enter(path, busy: false)
            }
            if nav.path != pathBefore {
                await waitForLoad(after: generation)
            }
            steps.append(snapshot(command: command))
        }
        let indexed = model.works.filter { $0.sourceKind == "webdav" && $0.sourceID == source.id }.count
        let report: [String: Any] = [
            "sourceID": source.id,
            "indexedBeforeScan": indexed,
            "preflight": model.acceptanceContext,
            "steps": steps,
            "probes": probes,
        ]
        writeJSON(report, name: "browse-report.json")
        print("BROWSE_READY \(currentPath)")
        if env["OPENFUSE_BROWSE_SKIP_PLAY"] == "1" {
            await waitForScan()
            return
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        if let mp4 = probedMP4 {
            playPhase = .mp4
            model.browserPlayback = mp4
        } else if let mkv = probedMKV {
            playPhase = .mkv
            model.browserPlayback = mkv
        } else {
            await waitForScan()
        }
    }

    private func advanceAcceptancePlayback() {
        guard playPhase == .mp4 || playPhase == .mkv else { return }
        guard model.browserPlayback == nil else { return }
        if playPhase == .mp4, let mkv = probedMKV {
            playPhase = .mkv
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                model.browserPlayback = mkv
            }
        } else {
            playPhase = .done
            guard !didScheduleScan else { return }
            didScheduleScan = true
            Task { await waitForScan() }
        }
    }

    private func waitForScan() async {
        let marker = documentsDirectory().appendingPathComponent("scan-now")
        var found = false
        for _ in 0..<120 {
            if FileManager.default.fileExists(atPath: marker.path) {
                found = true
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard found else {
            writeJSON(["ok": false, "error": "timed out waiting for scan-now"], name: "browse-scan.json")
            print("BROWSE_SCAN_TIMEOUT")
            return
        }
        var scan: [String: Any] = ["ok": false]
        do {
            try await model.scanWebDAV(source)
            let works = model.works.filter { $0.sourceID == source.id }
            scan = [
                "ok": true,
                "count": works.count,
                "titles": works.map(\.title),
                "status": model.status ?? "",
            ]
        } catch {
            scan = ["ok": false, "error": error.localizedDescription, "status": model.status ?? ""]
        }
        writeJSON(scan, name: "browse-scan.json")
        print("BROWSE_SCANNED \(scan["count"] ?? 0)")
    }

    private func probeVideos() async -> [[String: Any]] {
        var result: [[String: Any]] = []
        for entry in entries where entry.isPlayableVideo {
            guard let item = await model.remotePlaybackItem(source: source, entry: entry, siblings: entries) else {
                result.append(["path": entry.path, "error": model.status ?? "无法播放"])
                continue
            }
            var resume = -1.0
            if item.requiresMPV {
                probedMKV = item
            } else {
                model.recordProgress(item: item, duration: 100, position: 40)
                if let again = await model.remotePlaybackItem(source: source, entry: entry, siblings: entries) {
                    resume = again.resumePosition ?? -1
                    probedMP4 = again
                } else {
                    probedMP4 = item
                }
            }
            result.append([
                "path": entry.path,
                "title": item.title,
                "requiresMPV": item.requiresMPV,
                "remotePath": item.remotePath ?? "",
                "resumeKey": item.fingerprint.resumeKey,
                "sourceID": item.sourceID,
                "hasAuth": item.httpHeaders["Authorization"]?.hasPrefix("Basic ") == true,
                "sidecarCount": item.sidecarSubtitles.count,
                "sidecars": item.sidecarSubtitles.map {
                    ["language": $0.language ?? "", "name": $0.displayName, "local": $0.url?.isFileURL == true]
                },
                "resumePosition": resume,
            ])
        }
        return result
    }

    private func snapshot(command: String) -> [String: Any] {
        [
            "command": command,
            "path": nav.path,
            "stack": nav.stack,
            "error": errorMessage ?? "",
            "entries": entries.map { entry in
                [
                    "name": entry.isDirectory ? entry.folderDisplayName : entry.baseName,
                    "path": entry.path,
                    "directory": entry.isDirectory,
                    "ext": entry.fileExtension,
                    "video": entry.isPlayableVideo,
                ] as [String: Any]
            },
        ]
    }

    private func waitForLoad(after generation: Int) async {
        for _ in 0..<200 {
            if loadGeneration > generation && !isLoading { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func writeJSON(_ object: [String: Any], name: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            print("BROWSE_REPORT_FAILED \(name)")
            return
        }
        try? data.write(to: documentsDirectory().appendingPathComponent(name), options: .atomic)
    }
}
