// swift-tools-version:5.9
import PackageDescription

// FoundationModels only exists in the macOS 26 SDK (Swift 6.2 and later). It is linked weakly so the app still launches on older systems,
// where the code that uses it is skipped by availability checks.
#if compiler(>=6.2)
let appLinkerSettings: [LinkerSetting] = [.linkedLibrary("sqlite3"), .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])]
#else
let appLinkerSettings: [LinkerSetting] = [.linkedLibrary("sqlite3")]
#endif

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
            linkerSettings: appLinkerSettings
        ),
        .testTarget(name: "TimeScreenTests", dependencies: ["TimeScreen"], path: "Tests/TimeScreenTests"),
    ]
)
