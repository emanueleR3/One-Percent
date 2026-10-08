// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OnePercent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OnePercent", targets: ["OnePercent"])
    ],
    targets: [
        .executableTarget(
            name: "OnePercent",
            path: "Sources/OnePercent"
        ),
        .testTarget(
            name: "OnePercentTests",
            dependencies: ["OnePercent"],
            path: "Tests/OnePercentTests"
        )
    ]
)
