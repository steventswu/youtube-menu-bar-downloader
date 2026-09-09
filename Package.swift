// swift-tools-version: 5.8
import PackageDescription
let package = Package(name: "Downloader", platforms: [.macOS(.v13)], products: [.executable(name: "Downloader", targets: ["Downloader"])], targets: [.target(name: "DownloadCore"), .executableTarget(name: "Downloader", dependencies: ["DownloadCore"]), .testTarget(name: "DownloadCoreTests", dependencies: ["DownloadCore"])])
