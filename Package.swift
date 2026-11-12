// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (no UI) so it can be unit-tested.
        .target(name: "IslandCore"),
        // The menu bar / floating island app.
        .executableTarget(name: "Island", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
