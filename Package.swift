// swift-tools-version: 6.2
//
// Bus Stop — a live map of every physical port on your Mac.
//
// The core library builds and tests on Linux as well as macOS, so contributors
// without a Mac can work on parsing and topology logic. Everything that touches
// IOKit, AppKit or SwiftUI is declared only on macOS.

import PackageDescription

var products: [Product] = [
    .library(name: "BusStopCore", targets: ["BusStopCore"]),
]

var targets: [Target] = [
    .target(
        name: "BusStopCore",
        path: "Sources/BusStopCore"
    ),
    .testTarget(
        name: "BusStopCoreTests",
        dependencies: ["BusStopCore"],
        path: "Tests/BusStopCoreTests"
    ),
]

#if os(macOS)
products += [
    .library(name: "BusStopKit", targets: ["BusStopKit"]),
    .executable(name: "BusStopApp", targets: ["BusStopApp"]),
    .executable(name: "busstop", targets: ["BusStopCLI"]),
]

targets += [
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
    .testTarget(
        name: "BusStopKitTests",
        dependencies: ["BusStopKit", "BusStopCore"],
        path: "Tests/BusStopKitTests"
    ),
]
#endif

let package = Package(
    name: "BusStop",
    platforms: [.macOS(.v26)],
    products: products,
    targets: targets
)
