// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuietExistence",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "QuietExistence", path: "Sources/QuietExistence")
    ]
)
