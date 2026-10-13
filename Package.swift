// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeScreen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TimeScreen", targets: ["TimeScreen"]),
    ],
    targets: [
        .executableTarget(
            name: "TimeScreen",
            path: "Sources/TimeScreen",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "TimeScreenTests", dependencies: ["TimeScreen"], path: "Tests/TimeScreenTests"),
    ]
)
