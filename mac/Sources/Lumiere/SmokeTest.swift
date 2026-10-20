import Foundation
import LumierePlayer

/// Run with `--smoke-test`, the app proves it can start and exits before any
/// window opens: by the time this code runs, dyld has loaded every linked
/// library, and creating an mpv core loads libmpv's own. A bundle missing one
/// — libbrotlicommon, on 2026-10-20 — never reaches here, and the gate in
/// Scripts/verify-bundle.sh refuses it.
enum SmokeTest {
    static func runIfAsked() {
        guard CommandLine.arguments.contains("--smoke-test") else { return }
        guard let version = MPVRuntime.probe() else {
            FileHandle.standardError.write(Data("smoke test failed: mpv core could not be created\n".utf8))
            exit(2)
        }
        print("smoke test passed: mpv \(version)")
        exit(0)
    }
}
