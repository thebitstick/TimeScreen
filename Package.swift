// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeScreen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TimeScreen", targets: ["TimeScreen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.9.6")),
    ],
    targets: [
        .executableTarget(
            name: "TimeScreen",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/TimeScreen",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "TimeScreenTests", dependencies: ["TimeScreen"], path: "Tests/TimeScreenTests"),
    ]
)
