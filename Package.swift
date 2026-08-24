// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stasi",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Stasi",
            path: "Sources/Stasi",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StasiTests",
            dependencies: ["Stasi"],
            path: "Tests/StasiTests"
        ),
    ]
)
