// swift-tools-version: 6.2
//
// Bus Stop — a live map of every physical port on your Mac.
//
// BusStopCore holds the parsing and topology logic with no hardware access or
// UI, so its tests run on saved captures and demo data. IOKit lives in
// BusStopKit, and AppKit and SwiftUI in the app.

import PackageDescription

let package = Package(
    name: "BusStop",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BusStopCore", targets: ["BusStopCore"]),
        .library(name: "BusStopKit", targets: ["BusStopKit"]),
        .executable(name: "BusStopApp", targets: ["BusStopApp"]),
        .executable(name: "busstop", targets: ["BusStopCLI"]),
        .executable(name: "BusStopWidgets", targets: ["BusStopWidgets"]),
    ],
    targets: [
        .target(
            name: "BusStopCore",
            path: "Sources/BusStopCore"
        ),
        .target(
            name: "BusStopKit",
            dependencies: ["BusStopCore"],
            path: "Sources/BusStopKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "BusStopApp",
            dependencies: ["BusStopCore", "BusStopKit"],
            path: "Sources/BusStopApp",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "BusStopCLI",
            dependencies: ["BusStopCore", "BusStopKit"],
            path: "Sources/BusStopCLI"
        ),
        // The desktop widget extension. scripts/build-app.sh wraps it in
        // Contents/PlugIns/BusStopWidgets.appex.
        .executableTarget(
            name: "BusStopWidgets",
            dependencies: ["BusStopCore"],
            path: "Sources/BusStopWidgets",
            linkerSettings: [
                // An app extension starts in NSExtensionMain, as Xcode links it;
                // starting in the WidgetBundle's own main crashes at launch.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
                .linkedFramework("WidgetKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "BusStopCoreTests",
            dependencies: ["BusStopCore"],
            path: "Tests/BusStopCoreTests",
            resources: [.copy("Fixtures/AnkerPrimeTB5.json")]
        ),
        .testTarget(
            name: "BusStopKitTests",
            dependencies: ["BusStopKit", "BusStopCore"],
            path: "Tests/BusStopKitTests"
        ),
        .testTarget(
            name: "BusStopAppTests",
            dependencies: ["BusStopApp"],
            path: "Tests/BusStopAppTests"
        ),
        .testTarget(
            name: "BusStopCLITests",
            dependencies: ["BusStopCLI"],
            path: "Tests/BusStopCLITests"
        ),
    ]
)
