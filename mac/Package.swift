// swift-tools-version: 6.0
import PackageDescription

// Lumiere is built with SwiftPM rather than Xcode: this machine has Command Line
// Tools only. `Scripts/bundle.sh` assembles the executable into a real .app.
//
// libmpv comes from Homebrew (`brew install mpv`). Its headers and dylib are not
// discoverable without pkg-config, which is absent here, so CMPV points at the
// Homebrew prefix explicitly. Scripts/bundle.sh relocates the dylibs at package time.
let mpvPrefix = "/usr/local/opt/mpv"

let package = Package(
    name: "Lumiere",
    // macOS 15, because that is what the app already required.
    //
    // Homebrew rebuilt mpv against 15.0 and the linker warned that we were claiming
    // 14 — which the build gate rightly treats as a failure. Raising it is not a
    // concession to that warning: several dylibs already vendored into the bundle
    // (libcrypto, liblzma, libpcre2, libmujs) carry `minos 15.0` too, so a copy of
    // this app has not been launchable on macOS 14 for some time. The manifest was
    // promising something the artifact could not deliver.
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lumiere", targets: ["Lumiere"]),
        .executable(name: "LumiereTests", targets: ["LumiereTests"]),
        .library(name: "LumiereKit", targets: ["LumiereKit"]),
        .library(name: "LumierePlayer", targets: ["LumierePlayer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .systemLibrary(name: "CMPV", path: "Sources/CMPV"),

        .target(
            name: "LumiereKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/LumiereKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .target(
            name: "LumierePlayer",
            dependencies: ["LumiereKit", "CMPV"],
            path: "Sources/LumierePlayer",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .unsafeFlags(["-L\(mpvPrefix)/lib", "-lmpv"])
            ]
        ),

        .executableTarget(
            name: "Lumiere",
            dependencies: ["LumiereKit", "LumierePlayer"],
            path: "Sources/Lumiere",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // XCTest and swift-testing both live inside Xcode, which this machine does
        // not have, so `swift test` is unavailable. The suite is an executable
        // instead: `swift run LumiereTests`. See Sources/TestKit.
        .target(
            name: "TestKit",
            path: "Sources/TestKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        .executableTarget(
            name: "LumiereTests",
            dependencies: ["TestKit", "LumiereKit"],
            path: "Tests/LumiereTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
