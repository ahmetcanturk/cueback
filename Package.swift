// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cueback",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "cueback", path: "Sources/cueback")
    ]
)
