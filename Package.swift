// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KuroVitals",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "HelperProtocol"),
        .target(name: "SMCKit"),
        .target(name: "SystemStats"),
        .target(name: "SensorReader", dependencies: ["SMCKit", "SystemStats"]),
        .target(name: "FanControl", dependencies: ["SMCKit", "HelperProtocol"]),
        .executableTarget(
            name: "kurovitals-helper",
            dependencies: ["SMCKit", "HelperProtocol"]),
        .executableTarget(
            name: "KuroVitals",
            dependencies: ["SMCKit", "SystemStats", "SensorReader", "FanControl", "HelperProtocol"]),
        .executableTarget(name: "smc-dump", dependencies: ["SMCKit"]),
        .target(
            name: "Translate",
            path: "Sources/Translate",
            linkerSettings: [
                .unsafeFlags(["-Lcrates/target/release", "-lktranslate_ffi"]),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(name: "SMCKitTests", dependencies: ["SMCKit"]),
        .testTarget(name: "SystemStatsTests", dependencies: ["SystemStats"]),
        .testTarget(name: "SensorReaderTests", dependencies: ["SensorReader"]),
        .testTarget(name: "FanControlTests", dependencies: ["FanControl"]),
        .testTarget(name: "TranslateTests", dependencies: ["Translate"]),
    ]
)
