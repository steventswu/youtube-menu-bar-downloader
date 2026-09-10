# YouTube Menu Bar Downloader

A small native macOS menu bar app for downloading public YouTube videos, audio, and playlists to your Mac.

## Features

- Native SwiftUI menu bar interface
- Audio-only downloads in M4A, MP3, or Opus
- MP4 video with audio at up to 4K
- Public YouTube playlist downloads with ordered filenames
- Per-item and playlist progress
- Cancel, retry, completion notifications, and Reveal in Finder
- No accounts, cookies, cloud service, or uploaded URLs
- Self-contained release build with yt-dlp, FFmpeg, ffprobe, and Deno

## Requirements

- macOS 13 Ventura or newer
- Apple Silicon Mac for the downloadable release
- An internet connection

## Install

1. Open the [latest release](https://github.com/steventswu/youtube-menu-bar-downloader/releases/latest).
2. Download `YouTube-Menu-Bar-Downloader-macOS-arm64.zip`.
3. Unzip it and move `Downloader.app` to your Applications folder.
4. Control-click `Downloader.app`, choose **Open**, and confirm **Open** on first launch. The release is ad-hoc signed but is not notarized with an Apple Developer ID.
5. Look for the download icon in the macOS menu bar.

## Use

1. Click the download icon in the menu bar.
2. Paste a public YouTube video or playlist URL.
3. Select **Audio only** or **Video + Audio**.
4. Choose the audio format or maximum video quality.
5. Choose a download folder if needed, then click **Download**.

Audio-only defaults to M4A. MP3 provides broad compatibility; Opus usually provides better quality at a smaller size. Video output is MP4. Resolutions include Best available, 2160p, 1440p, 1080p, 720p, 480p, and 360p. Best available is capped at 2160p.

For a single video in Video mode, click **Load quality** to enable only resolutions offered by that video. Playlist quality is a per-item ceiling: a 720p item still downloads at 720p when the playlist is set to 1080p.

## Headless mode

The packaged app also supports automation without opening the menu-bar UI:

```sh
dist/Downloader.app/Contents/MacOS/Downloader \
  --headless \
  --url 'https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID' \
  --output "$PWD/artifacts/job-name"
```

Headless mode downloads audio in playlist order, emits JSONL events to stdout, and writes a `manifest.json` containing each track's status, output path, SHA-256, and failure details. Options include `--audio-format m4a|mp3|opus`, `--no-playlist`, `--manifest`, `--tools`, and `--max-retries 0...10`. A non-zero exit code indicates a fatal error or a playlist with failed items.

## YouTube → Yoto Playlist Studio

This repository also contains a shareable Codex plugin for importing downloaded
playlist audio into Yoto cards:

- [Plugin README](plugins/youtube-to-yoto/README.md)
- [Plugin directory](plugins/youtube-to-yoto)

The plugin is an orchestration layer. It requires a separately built
`Downloader.app` and the local `YotoMCP` server. It does not contain OAuth
tokens, Yoto Card IDs, user icons, audio, or task artifacts.

## Playlists

Paste a `/playlist?list=...` URL or a video URL containing `list=`. The app creates a separate folder, downloads entries in playlist order, and prefixes filenames with a four-digit sequence number. Duplicate entries retain their positions.

Unavailable, private, removed, and failed entries are skipped. The app continues with the remaining entries and writes details to `download-failures.txt`. Cancelling keeps completed files and removes the current item's temporary files. Each run creates a new playlist folder; cross-run resume is not currently supported.

If a video URL includes a playlist but you only want that video, turn off **Download the entire playlist**.

## Limitations

- Public, non-live videos and public playlists only
- No browser cookies, sign-in, age-restricted content, private playlists, or subtitles
- YouTube may change its site and temporarily require a newer yt-dlp release
- VP9 and AV1 video is converted to HEVC for MP4 compatibility, which takes time and re-encodes video
- The downloadable build is Apple Silicon only and is not notarized

Download only content you are authorized to save, and follow the applicable terms and laws.

## Build from source

The build machine needs Swift 5.8 or newer, Python 3, Xcode Command Line Tools, and Homebrew installations of `ffmpeg`, `ffprobe`, and `deno`.

```sh
brew install ffmpeg deno
swift test
python3 scripts/package.py
open dist/Downloader.app
```

The packaging script downloads the official universal macOS yt-dlp release, verifies its SHA-256 checksum, copies the local FFmpeg and Deno dependencies into the app, applies ad-hoc signatures, and verifies the final bundle. It builds for the current Mac architecture.

If Swift Package Manager cannot locate the platform path when only Command Line Tools are installed, use the direct smoke-test workflow:

```sh
sh scripts/build.sh
swiftc Sources/DownloadCore/*.swift scripts/smoke.swift -o .build/local/smoke
.build/local/smoke "$PWD/dist/Downloader.app/Contents/Helpers"
sh scripts/test-media.sh
```

## Project structure

- `Sources/DownloadCore`: URL validation, argument generation, and child-process control
- `Sources/Downloader`: SwiftUI interface, headless CLI mode, and download workflow
- `Tests/DownloadCoreTests`: unit tests
- `scripts/package.py`: self-contained app packaging
- `scripts/test-media.sh`: local audio and 4K media conversion checks

Downloads are completed in a temporary directory inside the selected destination, checked with ffprobe, and moved to their final filename only after validation. Existing files are never overwritten.

## License

The application source is available under the MIT License. Release bundles contain separately licensed third-party software, including a GPL build of FFmpeg. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
