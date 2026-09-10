import XCTest
@testable import DownloadCore
final class CoreTests: XCTestCase {
    func testURLNormalizationAndRejection() throws {
        XCTAssertEqual(try YouTubeURL.parse(" https://youtu.be/BaW_jenozKc?list=123 ").absoluteString, "https://www.youtube.com/watch?v=BaW_jenozKc")
        for url in ["", "https://youtube.com.evil.com/watch?v=BaW_jenozKc", "file:///etc/passwd", "https://youtube.com/playlist?list=123", "https://user@youtube.com/watch?v=BaW_jenozKc", "https://youtu.be/$(touch)"] { XCTAssertThrowsError(try YouTubeURL.parse(url)) }
        XCTAssertNoThrow(try YouTubeURL.parse("https://www.youtube.com/shorts/BaW_jenozKc"))
    }
    func testAvailableQualityAndRestrictions() throws {
        let data = Data(#"{"title":"test","formats":[{"height":1080,"vcodec":"avc1"},{"height":2160,"vcodec":"none"}],"age_limit":0}"#.utf8)
        let info = try JSONDecoder().decode(MediaInfo.self, from: data)
        XCTAssertTrue(info.supports(.p1080)); XCTAssertFalse(info.supports(.p2160)); XCTAssertTrue(info.supports(.best))
        let restricted = try JSONDecoder().decode(MediaInfo.self, from: Data(#"{"title":"test","formats":[],"age_limit":18}"#.utf8))
        XCTAssertThrowsError(try restricted.validate())
    }
    func testArgumentsAnd4KCap() throws {
        let url = try YouTubeURL.parse("https://youtu.be/BaW_jenozKc")
        let dir = URL(fileURLWithPath: "/tmp/folder with spaces")
        for format in AudioFormat.allCases {
            let args = Arguments.download(.init(url: url, mode: .audioOnly, audioFormat: format, videoQuality: .best, outputDirectory: dir), tools: dir, work: dir)
            XCTAssertTrue(args.contains(format.rawValue.lowercased())); XCTAssertTrue(args.contains("--no-playlist")); XCTAssertEqual(args.last, url.absoluteString)
        }
        let args = Arguments.download(.init(url: url, mode: .videoAndAudio, audioFormat: .m4a, videoQuality: .best, outputDirectory: dir), tools: dir, work: dir)
        XCTAssertTrue(args.contains("bv[height<=2160]+ba/b[height<=2160]"))
    }
    func testFilenameSafetyAndUTF8Limit() {
        XCTAssertEqual(Arguments.filename("../a:b/c\n"), "_a_b_c_")
        XCTAssertLessThanOrEqual(Arguments.filename(String(repeating: "é", count: 200)).utf8.count, 160)
        XCTAssertEqual(Arguments.filename("..."), "YouTube Download")
    }

    func testHeadlessOptionsParsePlaylistAndAudioSettings() throws {
        let options = try HeadlessOptions.parse(["Downloader", "--headless", "--url", "https://www.youtube.com/watch?v=BaW_jenozKc&list=PL123", "--output", "/tmp/headless", "--audio-format", "mp3", "--manifest", "/tmp/manifest.json", "--max-retries", "4"])
        XCTAssertEqual(options.input, "https://www.youtube.com/watch?v=BaW_jenozKc&list=PL123")
        XCTAssertEqual(options.audioFormat, .mp3)
        XCTAssertTrue(options.includePlaylist)
        XCTAssertEqual(options.maxRetries, 4)
        XCTAssertEqual(options.manifestPath?.path, "/tmp/manifest.json")
    }

    func testHeadlessOptionsCanDisablePlaylist() throws {
        let options = try HeadlessOptions.parse(["--headless", "https://youtu.be/BaW_jenozKc", "--output", "/tmp/headless", "--no-playlist"])
        XCTAssertFalse(options.includePlaylist)
        XCTAssertEqual(options.audioFormat, .m4a)
    }
}
