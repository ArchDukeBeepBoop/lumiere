import SwiftUI
import LumiereKit

extension SyncPanel {

    /// The options that used to be the screen.
    ///
    /// Depth and which libraries, folded behind one word. They are decisions
    /// made once and then left alone for months, and a panel that opens on them
    /// asks a question nobody came to answer — but they are still here, and one
    /// click away, because "which libraries" is exactly what you want when
    /// something is missing.
    @ViewBuilder
    var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                depthCard
                librariesCard
                if !app.lastPartialLibraries.isEmpty {
                    SettingsCard(title: "Incomplete", icon: "exclamationmark.triangle") {
                        SettingsNote(
                            "\(app.lastPartialLibraries.joined(separator: ", ")) missed at "
                          + "least one page, so some titles may be missing. Nothing was "
                          + "removed — the deletion pass is skipped whenever a page "
                          + "fails, so a timeout can never delete a title or its watch "
                          + "history. Scanning again usually clears it."
                        )
                    }
                }
            }
        }
    }

    /// Watches the server's own scan while this panel is open.
    ///
    /// Only while it is open. The scan runs on the server whether anyone is
    /// looking or not, and polling it from a closed panel would be a request a
    /// second for a number nobody is reading.
    ///
    /// A server that cannot answer — a real Jellyfin — leaves `scan` nil, and
    /// every part of the panel that reads it falls back to the client's own sync
    /// state. That is the whole degradation story: no feature detection, no
    /// error, just a panel that says less.
    func pollScan() async {
        guard let client = app.client else { return }
        while !Task.isCancelled {
            var status: ServerScanStatus?
            do {
                status = try await client.serverScanStatus()
            } catch {
                // Two different failures were collapsing into one silent nil.
                //
                // "This server has no such endpoint" is the degradation this
                // panel is built for, and stays quiet. A server that stopped
                // answering, or stopped accepting the token, is not that — and
                // reporting it as "the panel simply says less" is how a scan
                // that died halfway looks identical to one that never started.
                if case JellyfinError.httpError(let code, _) = error,
                   code == 404 || code == 501 {
                    status = nil
                } else {
                    _ = app.noteRequestFailure(error)
                }
            }
            scan = status
            // Faster while something is happening, slower while nothing is: a
            // panel left open on an idle server should not ask once a second
            // for ever.
            try? await Task.sleep(for: .seconds(status?.Running == true ? 1 : 5))
        }
    }
}
