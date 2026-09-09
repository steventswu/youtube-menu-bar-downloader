import Foundation

@main struct Smoke {
    static func main() throws {
        let good = try YouTubeURL.parse(" https://youtu.be/BaW_jenozKc?list=123 ")
        precondition(good.absoluteString == "https://www.youtube.com/watch?v=BaW_jenozKc")
        precondition(YouTubeURL.playlist("https://www.youtube.com/watch?v=BaW_jenozKc&list=PL_test123&index=5")?.absoluteString == "https://www.youtube.com/playlist?list=PL_test123")
        precondition(YouTubeURL.playlist("https://music.youtube.com/playlist?list=PL_test123") != nil)
        precondition(YouTubeURL.playlist("https://youtube.com.evil.test/playlist?list=PL_test123") == nil)
        precondition(YouTubeURL.playlist("https://youtube.com/playlist?list=bad%26input") == nil)
        let playlist = try JSONDecoder().decode(PlaylistInfo.self, from: Data(#"{"title":"Playlist","entries":[{"id":"BaW_jenozKc","title":"one"},null,{"title":"Deleted video"},{"id":"BaW_jenozKc"}]}"#.utf8))
        precondition(playlist.entries.count == 4 && playlist.entries[1] == nil && playlist.entries[2]?.id == nil)
        for s in ["", "https://youtube.com.evil.com/watch?v=BaW_jenozKc", "file:///etc/passwd", "https://youtube.com/playlist?list=1", "https://user@youtube.com/watch?v=BaW_jenozKc"] {
            precondition((try? YouTubeURL.parse(s)) == nil)
        }
        let media = try JSONDecoder().decode(MediaInfo.self, from: Data(#"{"title":"test","formats":[{"height":1080,"vcodec":"avc1"}]}"#.utf8))
        precondition(media.supports(.p1080) && !media.supports(.p2160))
        precondition(Arguments.filename("../a:b/c\n") == "_a_b_c_")
        precondition(Arguments.filename(String(repeating: "é", count: 200)).utf8.count <= 160)
        let helpers = URL(fileURLWithPath: CommandLine.arguments[1])
        let runner = Runner()
        let version = try runner.run(helpers.appendingPathComponent("yt-dlp"), ["--version"])
        precondition(!version.isEmpty)
        for format in AudioFormat.allCases {
            let args = Arguments.download(.init(url: good, mode: .audioOnly, audioFormat: format, videoQuality: .best, outputDirectory: helpers), tools: helpers, work: helpers)
            precondition(args.contains(format.rawValue.lowercased()) && args.contains("--no-playlist"))
        }
        let cancel = Runner()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancel.cancel() }
        do { _ = try cancel.run(helpers.appendingPathComponent("deno"), ["eval", "setTimeout(() => {}, 10000)"]); fatalError("Cancellation failed") } catch is CancellationError { }
        print("PASS: URL validation, quality availability, filenames, audio arguments, bundled process execution, cancellation")
    }
}
