// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RealtimeNoteTaker",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RealtimeNoteTaker", targets: ["RealtimeNoteTaker"])
    ],
    targets: [
        .executableTarget(
            name: "RealtimeNoteTaker",
            path: "Sources/RealtimeNoteTaker"
        )
    ]
)
