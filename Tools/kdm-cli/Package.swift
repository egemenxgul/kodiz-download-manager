// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kdm-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/KodizKit")
    ],
    targets: [
        .executableTarget(
            name: "kdm-cli",
            dependencies: [
                .product(name: "KodizEngine", package: "KodizKit"),
                .product(name: "KodizSystem", package: "KodizKit")
            ],
            path: "Sources"
        )
    ]
)
