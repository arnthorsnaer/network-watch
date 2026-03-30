// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "NetworkWatch",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "NetworkWatch", path: "Sources/NetworkWatch")
    ]
)
