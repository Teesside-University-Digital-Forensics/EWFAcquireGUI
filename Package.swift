// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EWFAcquireGUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EWFAcquireGUI",
            path: "Sources/EWFAcquireGUI"
        )
    ]
)
