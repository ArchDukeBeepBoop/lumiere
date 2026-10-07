// swift-tools-version: 6.0
import PackageDescription

// A menu bar controller for Lumiere and its media server.
//
// Built with SwiftPM and assembled by Scripts/bundle.sh, the same way Lumiere is:
// this machine has Command Line Tools and no Xcode, so there is no xcodebuild to
// make an app bundle.
//
// It has no dependencies and does not link LumiereKit. The controller starts and
// stops two processes and asks the server how it is; sharing a database layer
// with the client to do that would couple three things that are better left able
// to move independently.
let package = Package(
    name: "LumiereControl",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "LumiereControl", targets: ["LumiereControl"]),
    ],
    targets: [
        .executableTarget(
            name: "LumiereControl",
            dependencies: ["ControlCore"],
            path: "Sources/LumiereControl",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The parts that touch the user's files, apart so they can be tested.
        .target(
            name: "ControlCore",
            path: "Sources/ControlCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // `swift run ControlTests` — no XCTest without Xcode.
        .executableTarget(
            name: "ControlTests",
            dependencies: ["ControlCore"],
            path: "Sources/ControlTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
