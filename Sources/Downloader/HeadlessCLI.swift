import CryptoKit
import Darwin
import Foundation
import DownloadCore

private struct HeadlessManifest: Codable {
    var jobId: String
    var sourceURL: String
    var playlistTitle: String?
    var audioFormat: String
    var outputDirectory: String
    var startedAt: String
    var completedAt: String?
    var tracks: [HeadlessManifestTrack]
}

private struct HeadlessManifestTrack: Codable {
    var index: Int
    var videoId: String?
    var title: String
    var status: String
    var path: String?
    var sha256: String?
    var error: String?
}

private struct HeadlessItem {
    let index: Int
    let videoId: String?
    let url: URL?
    let title: String
}

enum HeadlessCLI {
    static func run() -> Int {
        do {
            let options = try HeadlessOptions.parse(CommandLine.arguments)
            return try run(options)
        } catch HeadlessOptionError.help {
            print(usage)
            return 0
        } catch {
            emit(["event": "job_failed", "error": error.localizedDescription])
            fputs("\(error.localizedDescription)\n\(usage)", stderr)
            return 1
        }
    }

    private static func run(_ options: HeadlessOptions) throws -> Int {
        let tools = options.toolsPath ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try validateTools(tools)
        let input = options.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = options.includePlaylist ? YouTubeURL.playlist(input) : nil
        let sourceURL = try playlist ?? YouTubeURL.parse(input)
        let runner = Runner()
        let jobId = UUID().uuidString
        var folder = options.outputDirectory
        var playlistTitle: String?
        var items: [HeadlessItem]

        emit(["event": "job_started", "jobId": jobId, "sourceURL": sourceURL.absoluteString, "audioFormat": options.audioFormat.rawValue, "outputDirectory": folder.path])

        if let playlist {
            let args = Arguments.common(tools: tools).filter { $0 != "--no-playlist" } + ["--yes-playlist", "--flat-playlist", "--dump-single-json", "--skip-download", "--", playlist.absoluteString]
            let listing = try runner.run(tools.appendingPathComponent("yt-dlp"), args)
            guard let json = listing.split(separator: "\n").first(where: { $0.hasPrefix("{") }) else { throw DownloadError.message("Could not read the playlist.") }
            let info = try JSONDecoder().decode(PlaylistInfo.self, from: Data(json.utf8))
            guard !info.entries.isEmpty else { throw DownloadError.message("The playlist is empty or is not publicly accessible.") }
            playlistTitle = info.title
            items = info.entries.enumerated().map { offset, entry in
                let id = entry?.id
                return HeadlessItem(index: offset + 1, videoId: id, url: id.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }, title: entry?.title ?? "Unavailable")
            }
            folder = folder.appendingPathComponent("\(Arguments.filename(info.title))-\(String(UUID().uuidString.prefix(8)))", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            emit(["event": "playlist_loaded", "jobId": jobId, "title": info.title, "total": items.count, "outputDirectory": folder.path])
        } else {
            items = [HeadlessItem(index: 1, videoId: nil, url: sourceURL, title: "")]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let manifestURL = options.manifestPath ?? folder.appendingPathComponent("manifest.json")
        var manifest = HeadlessManifest(jobId: jobId, sourceURL: sourceURL.absoluteString, playlistTitle: playlistTitle, audioFormat: options.audioFormat.rawValue, outputDirectory: folder.path, startedAt: ISO8601DateFormatter().string(from: Date()), completedAt: nil, tracks: items.map { HeadlessManifestTrack(index: $0.index, videoId: $0.videoId, title: $0.title, status: "pending", path: nil, sha256: nil, error: nil) })
        try writeManifest(manifest, to: manifestURL)

        var successes = 0
        var failures = 0
        for item in items {
            emit(["event": "track_started", "jobId": jobId, "index": item.index, "title": item.title.isEmpty ? input : item.title])
            do {
                guard let itemURL = item.url else { throw DownloadError.message("This video was removed or is unavailable.") }
                let media = try probe(itemURL, tools: tools, runner: runner)
                try media.validate()
                let result = try download(item: item, media: media, requestURL: itemURL, folder: folder, tools: tools, format: options.audioFormat, maxRetries: options.maxRetries, includeIndexPrefix: playlist != nil)
                let hash = try sha256(result.path)
                manifest.tracks[item.index - 1].title = media.title
                manifest.tracks[item.index - 1].status = "completed"
                manifest.tracks[item.index - 1].path = result.path.path
                manifest.tracks[item.index - 1].sha256 = hash
                try writeManifest(manifest, to: manifestURL)
                successes += 1
                emit(["event": "track_completed", "jobId": jobId, "index": item.index, "title": media.title, "path": result.path.path, "sha256": hash])
            } catch {
                failures += 1
                manifest.tracks[item.index - 1].status = "failed"
                manifest.tracks[item.index - 1].error = error.localizedDescription
                try? writeManifest(manifest, to: manifestURL)
                emit(["event": "track_failed", "jobId": jobId, "index": item.index, "title": item.title, "error": error.localizedDescription])
            }
        }

        manifest.completedAt = ISO8601DateFormatter().string(from: Date())
        try writeManifest(manifest, to: manifestURL)
        emit(["event": "job_completed", "jobId": jobId, "successes": successes, "failures": failures, "manifestPath": manifestURL.path, "outputDirectory": folder.path])
        return failures == 0 ? 0 : 2
    }

    private static func probe(_ url: URL, tools: URL, runner: Runner) throws -> MediaInfo {
        let output = try runner.run(tools.appendingPathComponent("yt-dlp"), Arguments.common(tools: tools) + ["--dump-single-json", "--skip-download", "--", url.absoluteString])
        guard let json = output.split(separator: "\n").first(where: { $0.hasPrefix("{") }) else { throw DownloadError.message("Could not read video information.") }
        return try JSONDecoder().decode(MediaInfo.self, from: Data(json.utf8))
    }

    private static func download(item: HeadlessItem, media: MediaInfo, requestURL: URL, folder: URL, tools: URL, format: AudioFormat, maxRetries: Int, includeIndexPrefix: Bool) throws -> (path: URL, title: String) {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let work = folder.appendingPathComponent(".headless-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: work) }
                let request = DownloadRequest(url: requestURL, mode: .audioOnly, audioFormat: format, videoQuality: .best, outputDirectory: folder)
                var lastBucket = -1
                let output = try Runner().run(tools.appendingPathComponent("yt-dlp"), Arguments.download(request, tools: tools, work: work)) { line in
                    guard line.hasPrefix("PROGRESS:") else { return }
                    guard let data = String(line.dropFirst(9)).data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let downloaded = object["downloaded_bytes"] as? Double, let total = (object["total_bytes"] as? Double) ?? (object["total_bytes_estimate"] as? Double), total > 0 else { return }
                    let bucket = Int((downloaded / total) * 20)
                    if bucket != lastBucket { lastBucket = bucket; emit(["event": "track_progress", "index": item.index, "title": media.title, "percent": min(downloaded / total, 1)]) }
                }
                guard let finalLine = output.split(separator: "\n").last(where: { $0.hasPrefix("FINAL:") }) else { throw DownloadError.message("The download tool did not report an output file.") }
                let source = URL(fileURLWithPath: String(finalLine.dropFirst(6)))
                guard source.deletingLastPathComponent().standardizedFileURL == work.standardizedFileURL, FileManager.default.fileExists(atPath: source.path) else { throw DownloadError.message("The downloaded file could not be found.") }
                let inspection = try Runner().run(tools.appendingPathComponent("ffprobe"), ["-v", "quiet", "-show_streams", "-of", "json", source.path])
                guard let object = try JSONSerialization.jsonObject(with: Data(inspection.utf8)) as? [String: Any], let streams = object["streams"] as? [[String: Any]], streams.contains(where: { $0["codec_type"] as? String == "audio" }) else { throw DownloadError.message("Output validation failed.") }
                let prefix = includeIndexPrefix ? String(format: "%04d - ", item.index) : ""
                var target = folder.appendingPathComponent(prefix + Arguments.filename(media.title) + "." + format.rawValue.lowercased())
                var suffix = 2
                while FileManager.default.fileExists(atPath: target.path) { target = folder.appendingPathComponent(prefix + Arguments.filename(media.title) + " (\(suffix))." + format.rawValue.lowercased()); suffix += 1 }
                try FileManager.default.moveItem(at: source, to: target)
                return (target, media.title)
            } catch { lastError = error; if attempt < maxRetries { emit(["event": "track_retry", "index": item.index, "title": media.title, "attempt": attempt + 2]) } }
        }
        throw lastError ?? DownloadError.message("Download failed.")
    }

    private static func sha256(_ path: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: path))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func writeManifest(_ manifest: HeadlessManifest, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try? fm.removeItem(at: url)
        try fm.moveItem(at: temporary, to: url)
    }

    private static func validateTools(_ tools: URL) throws {
        for name in ["yt-dlp", "ffmpeg", "ffprobe", "deno", "process-launcher"] {
            guard FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent(name).path) else { throw DownloadError.message("Missing executable in tools directory: \(name).") }
        }
    }

    private static func emit(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
    }

    private static let usage = """
    Usage:
      Downloader.app/Contents/MacOS/Downloader --headless --url <youtube-url> --output <folder> [options]

    Options:
      --audio-format m4a|mp3|opus   Default: m4a
      --no-playlist                 Download only the supplied video
      --manifest <path>             JSON manifest path (default: output folder/manifest.json)
      --tools <folder>              Override bundled helper directory
      --max-retries <0...10>        Default: 2
    """
}
