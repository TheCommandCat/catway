// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Catway",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Catway", targets: ["Catway"]),
    ],
    targets: [
        .executableTarget(name: "Catway"),
        .testTarget(name: "CatwayTests", dependencies: ["Catway"]),
    ]
)
