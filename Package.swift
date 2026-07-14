// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExnanoFabric",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "FabricCore", targets: ["FabricCore"]),
        .executable(name: "Fabric", targets: ["Fabric"]),
    ],
    targets: [
        .target(
            name: "FabricCore",
            path: "Sources/FabricCore"
        ),
        .executableTarget(
            name: "Fabric",
            dependencies: ["FabricCore"],
            path: "Sources/FabricApp"
        ),
    ]
)
