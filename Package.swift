// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenLens",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        // Main app (local-file-first MVP)
        .executableTarget(
            name: "TokenLensApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/TokenLensApp"
        ),

        // Tests
        .testTarget(
            name: "TokenLensTests",
            dependencies: ["TokenLensApp"],
            path: "Tests/TokenLensTests"
        ),
    ]
)
