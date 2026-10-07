import SwiftUI
import LumiereKit

/// The card's actions that reach the server. Split for the 300-line rule.
extension LibraryHealthCard {

    /// Moves the file, rescans so the library follows it, and offers Undo.
    func moveMisfiled(_ sample: LibraryHealthIssue.Sample) async {
        guard let client = app.client else { return }
        do {
            let folder = try await client.moveMisfiled(itemId: sample.id)
            try? await client.refreshServerLibrary()
            let place = URL(fileURLWithPath: folder).lastPathComponent
            app.report("Moved into \(place). The library follows it at the next scan.") {
                try? await client.undoMisfiledMove()
                try? await client.refreshServerLibrary()
            }
            await load()
        } catch {
            status = "Not moved: \(error.localizedDescription)"
        }
    }

    func moveAllMisfiled(_ samples: [LibraryHealthIssue.Sample]) async {
        guard let client = app.client else { return }
        do {
            let moved = try await client.moveMisfiled(itemIds: samples.map(\.id))
            try? await client.refreshServerLibrary()
            app.report("Moved \(moved) episodes into their seasons.") {
                try? await client.undoMisfiledMove()
                try? await client.refreshServerLibrary()
            }
            await load()
        } catch {
            status = "Nothing moved: \(error.localizedDescription)"
        }
    }

    func takeFrames() async {
        do {
            try await app.client?.takeMissingFrames()
            status = "Taking frames on the server, a few seconds each. Check again shortly."
        } catch {
            status = "The server did not start it: \(error.localizedDescription)"
        }
    }

    func run(scan: Bool) async {
        guard let client = app.client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if scan { try await client.refreshServerLibrary() } else { try await client.runServerMetadata() }
            status = scan
                ? "Scanning on the server. Check again when it finishes."
                : "Naming on the server. Check again in a few minutes."
        } catch {
            status = "The server did not start it: \(error.localizedDescription)"
        }
    }
}
