// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trace",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Trace", targets: ["Trace"]),
        .library(name: "TraceCore", targets: ["TraceCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Models, storage, tagging and aggregation. No UI, fully testable.
        .target(
            name: "TraceCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // The macOS app: capture, SwiftUI views, menu bar.
        .executableTarget(
            name: "Trace",
            dependencies: ["TraceCore"]
        ),
        .testTarget(
            name: "TraceCoreTests",
            dependencies: ["TraceCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
