import SwiftUI
import AppKit
import UserNotifications
import Darwin
import DownloadCore

@main struct DownloaderApp: App {
    @StateObject private var model = DownloadModel()
    init() {
        if CommandLine.arguments.contains("--headless") {
            Darwin.exit(Int32(HeadlessCLI.run()))
        }
    }
    var body: some Scene {
        MenuBarExtra("Downloader", systemImage: "arrow.down.circle") {
            Panel(model: model)
        }.menuBarExtraStyle(.window)
    }
}

@MainActor final class DownloadModel: ObservableObject {
    @Published var input = "" { didSet { if input != oldValue { info = nil; quality = .best } } }
    @Published var mode = DownloadMode.audioOnly
    @Published var audio = AudioFormat.m4a
    @Published var quality = VideoQuality.best
    @Published var wholePlaylist = true
    @Published var batchStatus = ""
    @Published var processed = 0
    @Published var total = 0
    var playlistURL: URL? { wholePlaylist ? YouTubeURL.playlist(input) : nil }
    @Published var info: MediaInfo?
    @Published var busy = false
    @Published var status = "Paste a YouTube URL to get started."
    @Published var progress: Double?
    @Published var detail = ""
    @Published var completed: URL?
    @Published var directory = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "outputDirectory") ?? NSHomeDirectory() + "/Downloads/YouTube", isDirectory: true)
    private var runner: Runner?
    private var task: Task<Void, Never>?
    private var cancelRequested = false
    private let tools = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")

    func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { directory = url; UserDefaults.standard.set(url.path, forKey: "outputDirectory") }
    }
    func cancel() { cancelRequested = true; task?.cancel(); runner?.cancel(); status = "Cancelling…" }
    func start(probeOnly: Bool = false) {
        guard !busy else { return }
        do {
            let playlist = playlistURL
            let url = try playlist ?? YouTubeURL.parse(input)
            for name in ["yt-dlp", "ffmpeg", "ffprobe", "deno", "process-launcher"] {
                guard FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent(name).path) else { throw DownloadError.message("Bundled tools are incomplete. Rebuild the app with scripts/package.py.") }
            }
            let request = DownloadRequest(url: url, mode: mode, audioFormat: audio, videoQuality: quality, outputDirectory: directory)
            busy = true; completed = nil; progress = nil; detail = ""; status = "Reading video information…"; cancelRequested = false
            batchStatus = ""; processed = 0; total = 0
            let worker = Runner(); runner = worker
            task = Task {
                defer { busy = false; runner = nil; task = nil }
                do {
                    var items: [(Int, String?)] = [(1, url.absoluteString)]
                    var folder = request.outputDirectory
                    var failures: [String] = []
                    var successes = 0
                    if let playlist = playlist {
                        status = "Reading playlist…"
                        let args = Arguments.common(tools: tools).filter { $0 != "--no-playlist" } + ["--yes-playlist", "--flat-playlist", "--dump-single-json", "--skip-download", "--", playlist.absoluteString]
                        let listing = try await call(worker, "yt-dlp", args)
                        try Task.checkCancellation()
                        guard let json = listing.split(separator: "\n").first(where: { $0.hasPrefix("{") }) else { throw DownloadError.message("Could not read the playlist.") }
                        let list = try JSONDecoder().decode(PlaylistInfo.self, from: Data(json.utf8))
                        guard !list.entries.isEmpty else { throw DownloadError.message("The playlist is empty or is not publicly accessible.") }
                        items = list.entries.enumerated().map { index, entry in
                            (index + 1, entry?.id.flatMap { try? YouTubeURL.parse("https://youtu.be/\($0)").absoluteString })
                        }
                        folder = folder.appendingPathComponent(Arguments.filename(list.title) + "-" + UUID().uuidString.prefix(8), isDirectory: true)
                        total = items.count; batchStatus = "\(list.title) · \(total) items"
                        if probeOnly { status = "The selected quality is the maximum for each playlist item."; return }
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        completed = folder
                    }
                    for (index, item) in items {
                    try Task.checkCancellation()
                    if playlist != nil { batchStatus = "Item \(index) of \(total) · \(successes) complete · \(failures.count) failed" }
                    do {
                    guard let item = item, let url = URL(string: item) else { throw DownloadError.message("This video was removed or is unavailable.") }
                    let request = DownloadRequest(url: url, mode: request.mode, audioFormat: request.audioFormat, videoQuality: request.videoQuality, outputDirectory: folder)
                    progress = nil; detail = ""; status = "Reading video information…"
                    let data = try await call(worker, "yt-dlp", Arguments.common(tools: tools) + ["--dump-single-json", "--skip-download", "--", url.absoluteString])
                    try Task.checkCancellation()
                    guard let json = data.split(separator: "\n").first(where: { $0.hasPrefix("{") }) else { throw DownloadError.message("Could not read video information.") }
                    let media = try JSONDecoder().decode(MediaInfo.self, from: Data(json.utf8)); try media.validate(); info = media
                    if probeOnly { status = "Available quality options loaded."; return }
                    if playlist == nil && request.mode == .videoAndAudio && !media.supports(request.videoQuality) { quality = .best; throw DownloadError.message("This video does not offer the selected quality. Choose another option.") }
                    let fm = FileManager.default
                    try fm.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
                    let work = request.outputDirectory.appendingPathComponent(".downloader-" + UUID().uuidString, isDirectory: true)
                    try fm.createDirectory(at: work, withIntermediateDirectories: false)
                    defer { try? fm.removeItem(at: work) }
                    status = "Downloading…"
                    let output = try await call(worker, "yt-dlp", Arguments.download(request, tools: tools, work: work), progressLines: true)
                    try Task.checkCancellation()
                    guard let final = output.split(separator: "\n").last(where: { $0.hasPrefix("FINAL:") }) else { throw DownloadError.message("The download tool did not report an output file.") }
                    var source = URL(fileURLWithPath: String(final.dropFirst(6)))
                    guard source.deletingLastPathComponent().standardizedFileURL == work.standardizedFileURL, fm.fileExists(atPath: source.path) else { throw DownloadError.message("The downloaded file could not be found.") }
                    if request.mode == .videoAndAudio {
                        status = "Merging or converting to MP4…"; progress = nil; detail = "High-resolution video conversion can take several minutes."
                        let inspection = try await call(worker, "ffprobe", ["-v", "quiet", "-show_streams", "-of", "json", source.path])
                        let object = try JSONSerialization.jsonObject(with: Data(inspection.utf8)) as? [String: Any]
                        let streams = object?["streams"] as? [[String: Any]] ?? []
                        guard let video = streams.first(where: { $0["codec_type"] as? String == "video" }), streams.contains(where: { $0["codec_type"] as? String == "audio" }) else { throw DownloadError.message("The output is missing a video or audio stream.") }
                        let codec = video["codec_name"] as? String ?? ""
                        let destination = work.appendingPathComponent("converted.mp4")
                        var args = ["-nostdin", "-v", "error", "-i", source.path, "-map", "0:v:0", "-map", "0:a:0"]
                        args += ["-c:v", ["h264", "hevc"].contains(codec) ? "copy" : "hevc_videotoolbox"]
                        if !["h264", "hevc"].contains(codec) { args += ["-b:v", "20M", "-allow_sw", "1"] }
                        if codec != "h264" { args += ["-tag:v", "hvc1"] }
                        let audioCodec = streams.first(where: { $0["codec_type"] as? String == "audio" })?["codec_name"] as? String
                        args += ["-c:a", audioCodec == "aac" ? "copy" : "aac"]
                        args += ["-movflags", "+faststart", destination.path]
                        _ = try await call(worker, "ffmpeg", args); source = destination
                    }
                    try Task.checkCancellation()
                    let validation = try await call(worker, "ffprobe", ["-v", "quiet", "-show_streams", "-of", "json", source.path])
                    let object = try JSONSerialization.jsonObject(with: Data(validation.utf8)) as? [String: Any]
                    let streams = object?["streams"] as? [[String: Any]] ?? []
                    guard streams.contains(where: { $0["codec_type"] as? String == "audio" }), request.mode == .audioOnly || streams.contains(where: { $0["codec_type"] as? String == "video" }) else { throw DownloadError.message("Output file validation failed.") }
                    try Task.checkCancellation()
                    let ext = request.mode == .audioOnly ? request.audioFormat.rawValue.lowercased() : "mp4"
                    let base = (playlist == nil ? "" : String(format: "%04d - ", index)) + Arguments.filename(media.title)
                    var target = request.outputDirectory.appendingPathComponent(base + "." + ext)
                    var number = 2
                    while fm.fileExists(atPath: target.path) { target = request.outputDirectory.appendingPathComponent("\(base) (\(number)).\(ext)"); number += 1 }
                    try fm.moveItem(at: source, to: target)
                    successes += 1
                    completed = playlist == nil ? target : folder
                    } catch {
                        if cancelRequested || Task.isCancelled { throw CancellationError() }
                        if playlist == nil { throw error }
                        failures.append("Item \(index): \(friendly(error))")
                    }
                    processed = index
                    }
                    progress = 1; detail = ""; status = failures.isEmpty ? "Download complete." : "Finished with \(failures.count) failed item(s). See the failure report in the playlist folder."
                    if playlist != nil {
                        batchStatus = "\(successes) of \(total) complete · \(failures.count) failed"
                        if !failures.isEmpty { try failures.joined(separator: "\n\n").write(to: folder.appendingPathComponent("download-failures.txt"), atomically: true, encoding: .utf8) }
                    }
                    let center = UNUserNotificationCenter.current()
                    if (try? await center.requestAuthorization(options: [.alert, .sound])) == true {
                        let content = UNMutableNotificationContent(); content.title = failures.isEmpty ? "Download complete" : "Download complete with failures"; content.body = playlist == nil ? (completed?.lastPathComponent ?? "") : batchStatus; content.sound = .default
                        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
                    }
                } catch { progress = nil; detail = ""; status = cancelRequested ? "Cancelled. Completed files remain in the download folder." : "Download failed: \(friendly(error))" }
            }
        } catch { status = error.localizedDescription }
    }
    private func call(_ worker: Runner, _ name: String, _ args: [String], progressLines: Bool = false) async throws -> String {
        let executable = tools.appendingPathComponent(name)
        return try await Task.detached {
            try worker.run(executable, args) { line in
                guard progressLines else { return }
                Task { @MainActor in
                    guard self.busy, !self.cancelRequested, self.runner === worker else { return }
                    if line.hasPrefix("PROGRESS:"), let data = String(line.dropFirst(9)).data(using: .utf8), let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        let downloaded = obj["downloaded_bytes"] as? Double ?? 0
                        let total = obj["total_bytes"] as? Double ?? obj["total_bytes_estimate"] as? Double ?? 0
                        self.progress = total > 0 ? min(downloaded / total, 1) : nil
                        let speed = obj["speed"] as? Double ?? 0; let eta = obj["eta"] as? Double
                        self.detail = String(format: "%.1f MB/s", speed / 1_000_000) + (eta.map { " · \(Int($0)) seconds remaining" } ?? "")
                    } else if line.hasPrefix("[ExtractAudio]") || line.hasPrefix("[Merger]") || line.hasPrefix("[VideoRemuxer]") { self.status = "Merging or converting…"; self.progress = nil }
                }
            }
        }.value
    }
    private func friendly(_ error: Error) -> String {
        let s = error.localizedDescription
        if s.contains("Sign in") || s.contains("Private video") || s.contains("age") { return "This video requires sign-in or YouTube verification. Only public videos that do not require sign-in are supported." }
        if s.contains("timed out") || s.contains("Unable to download") { return "The network or YouTube is temporarily unavailable. Try again later." }
        return String(s.suffix(700))
    }
}

struct Panel: View {
    @ObservedObject var model: DownloadModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: "arrow.down.circle.fill").font(.title).foregroundColor(.accentColor); VStack(alignment: .leading) { Text("Downloader").font(.headline); Text("YouTube → Your Mac").font(.caption).foregroundColor(.secondary) }; Spacer() }
            HStack {
                TextField("Paste a YouTube video or playlist URL", text: $model.input).textFieldStyle(.roundedBorder).onSubmit { model.start() }
                Button { if let text = NSPasteboard.general.string(forType: .string) { model.input = text } } label: { Image(systemName: "doc.on.clipboard") }.help("Paste")
            }.disabled(model.busy)
            Picker("Download mode", selection: $model.mode) { ForEach(DownloadMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(model.busy)
            Group {
                if YouTubeURL.playlist(model.input) != nil {
                    Toggle("Download the entire playlist", isOn: $model.wholePlaylist)
                    Text("Downloads in order to a separate folder and skips unavailable videos.").font(.caption).foregroundColor(.secondary)
                }
                if model.mode == .audioOnly {
                    Picker("Audio format", selection: $model.audio) { ForEach(AudioFormat.allCases, id: \.self) { Text($0.rawValue + ($0 == .m4a ? " · Recommended" : "")).tag($0) } }
                    Text("M4A for Apple devices · MP3 for compatibility · Opus for efficiency").font(.caption).foregroundColor(.secondary)
                } else {
                    Picker("Video format", selection: .constant("MP4")) { Text("MP4").tag("MP4") }
                    HStack {
                        Picker("Quality", selection: $model.quality) { ForEach(VideoQuality.allCases, id: \.self) { q in Text(q.label).tag(q).disabled(model.playlistURL == nil && q != .best && !(model.info?.supports(q) ?? false)) } }
                        Button("Load quality") { model.start(probeOnly: true) }
                    }
                    Text("Up to 4K. Converts to HEVC when required while retaining resolution.").font(.caption).foregroundColor(.secondary)
                }
            }.disabled(model.busy)
            Group {
            if !model.batchStatus.isEmpty {
                Text(model.batchStatus).font(.caption)
                if model.total > 0 { ProgressView(value: Double(model.processed), total: Double(model.total)) }
            }
            if let info = model.info { Text(info.title).font(.subheadline).lineLimit(2) }
            Divider()
            HStack { Image(systemName: "folder"); Text(model.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button("Change") { model.chooseDirectory() }.disabled(model.busy) }
            if model.busy { if let progress = model.progress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) } }
            Text(model.status).font(.caption).foregroundColor(.secondary).textSelection(.enabled).lineLimit(6)
            if !model.detail.isEmpty { Text(model.detail).font(.caption.monospacedDigit()).foregroundColor(.secondary) }
            }
            HStack {
                if model.busy { Button("Cancel") { model.cancel() } } else { Button("Download") { model.start() }.buttonStyle(.borderedProminent).disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                if let file = model.completed { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.disabled(model.busy)
            }
        }.padding(20).frame(width: 410)
    }
}
