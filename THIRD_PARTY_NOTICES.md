# Third-Party Notices

Release bundles include third-party command-line programs and dynamic libraries. They remain separate programs invoked by the MIT-licensed application and retain their own licenses.

## yt-dlp

- Project: https://github.com/yt-dlp/yt-dlp
- License: The Unlicense, with additional bundled components listed by the project
- Corresponding source: the release tag recorded in `Downloader.app/Contents/Resources/Dependencies.txt`

## FFmpeg and codec libraries

- Project: https://ffmpeg.org/
- Source: https://ffmpeg.org/download.html
- License information: https://ffmpeg.org/legal.html
- Release build: Homebrew FFmpeg configured under GPL version 3 or later
- Homebrew formula and build instructions: https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/f/ffmpeg.rb

The packaged FFmpeg build may include libx264, libx265, libvpx, libopus, libmp3lame, libdav1d, libvmaf, and SVT-AV1. Exact versions and copied library paths are recorded in the bundle's `Dependencies.txt`. Their corresponding source repositories and license information are available from the Homebrew formulae used to build the installed bottles: https://github.com/Homebrew/homebrew-core

Copies of the FFmpeg GPL and LGPL license texts, and available license files for Deno, x264, and x265, are included in `Downloader.app/Contents/Resources/Licenses` by the packaging script.

## Deno

- Project and source: https://github.com/denoland/deno
- License: MIT

## Apple system frameworks

The app links to frameworks supplied with macOS. Those frameworks are governed by Apple's applicable license terms.
