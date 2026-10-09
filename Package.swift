// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OnePercent",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "OnePercent", targets: ["OnePercent"]),
        .library(name: "OnePercentCore", targets: ["OnePercentCore"])
    ],
    targets: [
        // Models, store, calculators and language support: no windows, no AppKit. The Mac app and
        // the iPhone app both build on it.
        .target(
            name: "OnePercentCore",
            path: "Sources/OnePercentCore"
        ),
        .executableTarget(
            name: "OnePercent",
            dependencies: ["OnePercentCore"],
            path: "Sources/OnePercent"
        ),
        // Fakes shared by the test targets (in-memory persistence...).
        .target(
            name: "OnePercentTestSupport",
            dependencies: ["OnePercentCore"],
            path: "Tests/OnePercentTestSupport"
        ),
        .testTarget(
            name: "OnePercentCoreTests",
            dependencies: ["OnePercentCore", "OnePercentTestSupport"],
            path: "Tests/OnePercentCoreTests"
        ),
        .testTarget(
            name: "OnePercentTests",
            dependencies: ["OnePercent", "OnePercentCore", "OnePercentTestSupport"],
            path: "Tests/OnePercentTests"
        )
    ]
)
