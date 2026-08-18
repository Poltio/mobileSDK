// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExampleApp",
    platforms: [
        .macOS(.v14),
        .iOS(.v15),
    ],
    products: [
        .executable(name: "ExampleApp", targets: ["ExampleApp"]),
    ],
    targets: [
        .executableTarget(
            name: "ExampleApp",
            path: "ExampleApp"
        ),
    ]
)
