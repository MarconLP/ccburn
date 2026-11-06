// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCBurnBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CCBurnBar", path: "Sources/CCBurnBar")
    ]
)
