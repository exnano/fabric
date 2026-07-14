// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExnanoFabric",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "FabricCore", targets: ["FabricCore"]),
    ],
    targets: [
        .target(
            name: "FabricCore",
            path: "Sources/FabricCore"
        ),
    ]
)
