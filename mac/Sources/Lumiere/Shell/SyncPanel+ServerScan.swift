import SwiftUI
import LumiereKit

/// The panel's one action: scan the disk, wait, then bring it across.
///
/// Both halves are needed and neither is enough. The server walks the media
/// roots — which is the only way a file copied in five minutes ago is ever
/// found — and the client then reads what the server catalogued. Pressing one
/// and not the other is the shape this had for months, and it is why "I added a
/// show and it is not there" kept being true while every part reported success.
///
/// Split from SyncPanel.swift for the project's 300-line limit.
extension SyncPanel {

    /// One press: ask the server to scan, wait for it, then sync.
    ///
    /// It used to be one press and a wait of unknown length, followed by a
    /// second press. That is two steps only because the server's scan is
    /// asynchronous — which is the server's business, not something a person
    /// should have to sequence by hand. So this does the sequencing: it notes
    /// where the server was, asks, waits for the scan to end, and then runs the
    /// sync that brings the results over.
    ///
    /// Every step degrades rather than fails. A server with no status endpoint —
    /// a real Jellyfin — throws on the first poll and this falls back to the old
    /// message and syncs anyway, which is no worse than before and often right,
    /// since Jellyfin scans quickly on a small change.
    func scanServer() async {
        guard let client = app.client else { return }
        isScanningServer = true
        defer { isScanningServer = false }

        // Read before asking. A poll immediately afterwards can see the scan as
        // not-running because it has not begun, and "finished" would then be a
        // timestamp from an hour ago; the comparison against this is what tells
        // the two apart.
        let before = try? await client.serverScanStatus()

        do {
            try await client.refreshServerLibrary()
        } catch {
            serverScanMessage = "Couldn't start it: \(error.localizedDescription). "
                              + "This needs an account with server management rights."
            return
        }

        serverScanMessage = "Scanning the server…"
        let finished = await waitForScan(client: client, before: before)
        if finished {
            serverScanMessage = "Server scan finished. Syncing what it found…"
        } else {
            // Either the server does not report status, or it is taking longer
            // than anyone should watch a panel for. Syncing anyway is right in
            // both cases: whatever it has catalogued so far comes over now, and
            // the rest arrives on the next pass.
            serverScanMessage = "The server is still scanning. Syncing what it has "
                              + "so far; anything else appears on the next sync."
        }
        app.startSelectedSync(depth: app.syncSelection.depth)
    }

    /// How long to wait on a server scan before syncing anyway.
    ///
    /// Four minutes. A full import of a 50,000-item library is about a minute on
    /// this hardware, so this is generous — and it is bounded because a panel
    /// that waits forever is indistinguishable from one that has hung.
    private static let scanWaitLimit = Duration.seconds(240)

    /// Polls until the scan that was just asked for has ended.
    ///
    /// Returns false where the server cannot say — no status endpoint, or the
    /// wait ran out. Second-by-second, because this is a person watching a
    /// panel: anything slower reads as nothing happening, and the request is one
    /// small JSON body against a server on this machine.
    private func waitForScan(
        client: JellyfinClient, before: ServerScanStatus?
    ) async -> Bool {
        let deadline = ContinuousClock.now + Self.scanWaitLimit
        var sawItRun = false

        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
            guard let status = try? await client.serverScanStatus() else { return false }

            if status.Running { sawItRun = true }
            // The rule itself is in `ServerScanWait`, where it can be tested
            // without a server — it is the part of this that is easy to get
            // subtly wrong and impossible to notice.
            if ServerScanWait.isFinished(
                status: status, before: before, sawItRun: sawItRun
            ) {
                return true
            }
        }
        return false
    }
}
