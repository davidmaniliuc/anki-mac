// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AnkiKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AnkiKit", targets: ["AnkiKit"]),
    ],
    dependencies: [
        // Keep in step with the protoc-gen-swift that generated Sources/AnkiKit/Generated.
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.39.0"),
    ],
    targets: [
        // Built by scripts/build-backend.sh from bridge/ and the anki submodule.
        .binaryTarget(name: "CAnkiBridge", path: "Frameworks/AnkiBridge.xcframework"),
        .target(
            name: "AnkiKit",
            dependencies: [
                "CAnkiBridge",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreFoundation"),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
            ]
        ),
        .executableTarget(name: "ankikit-bench", dependencies: ["AnkiKit"]),
    ]
)
