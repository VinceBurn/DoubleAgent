// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "toDoubleAgent",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .executable(name: "toDoubleAgent", targets: ["toDoubleAgent"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "toDoubleAgent",
            dependencies: []
        ),
        .testTarget(
            name: "toDoubleAgentTests",
            dependencies: ["toDoubleAgent"]
        ),
    ]
)
