// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KodizKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "KodizBridgeProtocol", targets: ["KodizBridgeProtocol"]),
        .library(name: "KodizEngine", targets: ["KodizEngine"]),
        .library(name: "KodizStore", targets: ["KodizStore"]),
        .library(name: "KodizMedia", targets: ["KodizMedia"]),
        .library(name: "KodizSystem", targets: ["KodizSystem"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3")
    ],
    targets: [
        .target(
            name: "KodizBridgeProtocol",
            dependencies: []
        ),
        .testTarget(
            name: "KodizBridgeProtocolTests",
            dependencies: ["KodizBridgeProtocol"]
        ),
        .target(
            name: "KodizEngine",
            dependencies: []
        ),
        .testTarget(
            name: "KodizEngineTests",
            dependencies: ["KodizEngine"]
        ),
        .target(
            name: "KodizStore",
            dependencies: [
                "KodizEngine",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "KodizStoreTests",
            dependencies: ["KodizStore"]
        ),
        .target(
            name: "KodizMedia",
            dependencies: [
                "KodizEngine",
                "KodizBridgeProtocol"
            ]
        ),
        .testTarget(
            name: "KodizMediaTests",
            dependencies: [
                "KodizMedia",
                "KodizBridgeProtocol"
            ]
        ),
        .target(
            name: "KodizSystem",
            dependencies: [
                "KodizBridgeProtocol"
            ]
        )
    ]
)
