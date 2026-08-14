// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PoltioSDK",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "PoltioSDK",
            targets: ["PoltioSDK"]
        ),
    ],
    targets: [
        .target(
            name: "PoltioSDK",
            path: "Sources/PoltioSDK",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "PoltioSDKTests",
            dependencies: ["PoltioSDK"],
            path: "Tests/PoltioSDKTests"
        ),
    ]
)
