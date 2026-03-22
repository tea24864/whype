// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Whype",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Whype",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Whype",
            resources: [
                .process("Info.plist"),
            ]
        ),
    ]
)
