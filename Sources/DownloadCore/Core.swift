import Foundation

public enum DownloadMode: String, CaseIterable { case audioOnly = "Audio only", videoAndAudio = "Video + Audio" }
public enum AudioFormat: String, CaseIterable { case m4a = "M4A", mp3 = "MP3", opus = "Opus" }
public enum VideoQuality: Int, CaseIterable {
    case best = 0, p2160 = 2160, p1440 = 1440, p1080 = 1080, p720 = 720, p480 = 480, p360 = 360
    public var label: String { self == .best ? "Best available (≤ 4K)" : "\(rawValue)p" }
    public var ceiling: Int { self == .best ? 2160 : rawValue }
}
public enum DownloadState { case idle, probing, downloading, merging, completed(URL), failed(String), cancelled }
public struct DownloadRequest {
    public let url: URL
    public let mode: DownloadMode
    public let audioFormat: AudioFormat
    public let videoQuality: VideoQuality
    public let outputDirectory: URL
    public init(url: URL, mode: DownloadMode, audioFormat: AudioFormat, videoQuality: VideoQuality, outputDirectory: URL) {
        self.url = url; self.mode = mode; self.audioFormat = audioFormat; self.videoQuality = videoQuality; self.outputDirectory = outputDirectory
    }
}
public enum DownloadError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
public enum YouTubeURL {
    public static func playlist(_ input: String) -> URL? {
        guard let c = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(c.scheme?.lowercased() ?? ""), c.user == nil, c.password == nil, c.port == nil,
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"].contains(c.host?.lowercased() ?? ""),
              let id = c.queryItems?.first(where: { $0.name == "list" })?.value,
              id.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.youtube.com/playlist?list=\(id)")
    }
    public static func parse(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: text), ["https", "http"].contains(c.scheme?.lowercased() ?? ""), c.user == nil, c.password == nil, c.port == nil else { throw DownloadError.message("Paste a complete YouTube video URL.") }
        let host = c.host?.lowercased() ?? ""
        let parts = c.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be", parts.count == 1 { id = parts[0] }
        else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if c.path == "/watch" { id = c.queryItems?.first(where: { $0.name == "v" })?.value }
            else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) { id = parts[1] }
        }
        guard let videoID = id, videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { throw DownloadError.message("Paste a single video URL, or enable the full playlist option.") }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }
}
public struct PlaylistInfo: Decodable {
    public struct Entry: Decodable { public let id: String?; public let title: String? }
    public let title: String
    public let entries: [Entry?]
}
public struct MediaInfo: Decodable {
    public struct Format: Decodable { public let height: Int?; public let vcodec: String? }
    public let title: String
    public let formats: [Format]
    public let age_limit: Int?
    public let is_live: Bool?
    public let availability: String?
    public func supports(_ quality: VideoQuality) -> Bool {
        quality == .best || formats.contains { $0.height == quality.rawValue && $0.vcodec != "none" }
    }
    public func validate() throws {
        if (age_limit ?? 0) >= 18 || is_live == true || ["private", "premium_only", "subscriber_only", "needs_auth"].contains(availability ?? "") {
            throw DownloadError.message("This version supports public, non-live videos that do not require sign-in.")
        }
    }
}
public enum Arguments {
    public static func common(tools: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-colors", "--no-cache-dir", "--socket-timeout", "20", "--retries", "2", "--ffmpeg-location", tools.path, "--js-runtimes", "deno:\(tools.appendingPathComponent("deno").path)"]
    }
    public static func download(_ r: DownloadRequest, tools: URL, work: URL) -> [String] {
        var args = common(tools: tools) + ["--newline", "--no-simulate", "--progress", "--progress-template", "download:PROGRESS:%(progress)j", "--print", "after_move:FINAL:%(filepath)s", "--paths", work.path, "-o", "media.%(ext)s"]
        if r.mode == .audioOnly {
            let preferred = r.audioFormat == .m4a ? "ba[ext=m4a]/ba" : r.audioFormat == .opus ? "ba[acodec=opus]/ba" : "ba"
            args += ["-f", preferred, "-x", "--audio-format", r.audioFormat.rawValue.lowercased(), "--audio-quality", "0"]
        } else {
            args += ["-f", "bv[height<=\(r.videoQuality.ceiling)]+ba/b[height<=\(r.videoQuality.ceiling)]", "--merge-output-format", "mkv", "--remux-video", "mkv"]
        }
        return args + ["--", r.url.absoluteString]
    }
    public static func filename(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|:").union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "_").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var result = ""
        for ch in cleaned { if (result + String(ch)).utf8.count > 160 { break }; result.append(ch) }
        return result.isEmpty ? "YouTube Download" : result
    }
}
