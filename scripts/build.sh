#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/local
SDK="$(xcrun --show-sdk-path)"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" -emit-library -emit-module -module-name DownloadCore Sources/DownloadCore/*.swift -emit-module-path .build/local/DownloadCore.swiftmodule -o .build/local/libDownloadCore.dylib -Xlinker -install_name -Xlinker @executable_path/../Frameworks/libDownloadCore.dylib
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" -parse-as-library -I .build/local -L .build/local -lDownloadCore Sources/Downloader/*.swift -o .build/local/Downloader
