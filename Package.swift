// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KuroTools",
    platforms: [.macOS(.v13)],
    products: [
        // Bundle `.saver` không dựng được bằng SwiftPM; `scripts/bundle-saver.sh`
        // lấy dylib này rồi tự gói. Product phải là `.dynamic` — một static
        // library thì không có gì để `dlopen`.
        .library(name: "KuroToolsWallpaper", type: .dynamic, targets: ["WallpaperSaver"]),
    ],
    targets: [
        .target(name: "HelperProtocol"),
        .target(name: "SMCKit"),
        .target(name: "SystemStats"),
        .target(name: "SensorReader", dependencies: ["SMCKit", "SystemStats"]),
        .target(name: "FanControl", dependencies: ["SMCKit", "HelperProtocol"]),
        .executableTarget(
            name: "kurovitals-helper",
            dependencies: ["SMCKit", "HelperProtocol"]),
        .executableTarget(name: "smc-dump", dependencies: ["SMCKit"]),
        .target(name: "Vitals",
                dependencies: ["SMCKit", "SystemStats", "SensorReader", "FanControl", "HelperProtocol"],
                path: "Sources/Vitals"),
        .target(
            name: "Wallpaper",
            path: "Sources/Wallpaper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        // KHÔNG phụ thuộc `Wallpaper`: kéo nó vào là nhét luôn code cửa sổ
        // desktop-level vào bundle screensaver. Chỗ duy nhất hai bên phải khớp
        // là đường dẫn, và `SaverVideoLocatorTests` giữ nó khớp.
        .target(
            name: "WallpaperSaver",
            path: "Sources/WallpaperSaver",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenSaver"),
            ]
        ),
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
                .linkedFramework("Carbon"),
            ]
        ),
        .target(name: "Settings", dependencies: ["Translate", "Vitals", "Wallpaper"], path: "Sources/Settings"),
        .executableTarget(name: "KuroTools", dependencies: ["Vitals", "Translate", "Settings", "Wallpaper"], path: "Sources/KuroTools"),
        // Chỉ test dùng — không product nào phụ thuộc, nên nó không bao giờ đi
        // vào KuroTools.app.
        .target(name: "TestSupport", path: "Tests/TestSupport"),
        .testTarget(name: "SMCKitTests", dependencies: ["SMCKit"]),
        .testTarget(name: "SystemStatsTests", dependencies: ["SystemStats"]),
        .testTarget(name: "SensorReaderTests", dependencies: ["SensorReader"]),
        .testTarget(name: "FanControlTests", dependencies: ["FanControl"]),
        .testTarget(name: "VitalsTests", dependencies: ["Vitals", "FanControl", "TestSupport"]),
        .testTarget(name: "TranslateTests", dependencies: ["Translate", "TestSupport"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings", "TestSupport"]),
        .testTarget(name: "WallpaperTests", dependencies: ["Wallpaper", "WallpaperSaver", "TestSupport"]),
        .testTarget(name: "KuroToolsTests", dependencies: ["KuroTools", "Wallpaper", "TestSupport"]),
    ]
)
