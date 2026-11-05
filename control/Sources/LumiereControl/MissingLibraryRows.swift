import AppKit
import SwiftUI

/// What the menu offers when the server refused to start because its library
/// is gone: restore a copy (the Backups rows below), or start again empty.
///
/// Start Fresh is the only way past the refusal, so it names what it costs. The
/// server once took that path by itself, silently, and every app read the empty
/// library it made as the real one.
struct MissingLibraryRows: View {
    @Bindable var server: ServerProcess

    var body: some View {
        MenuSection(text: "Library missing")
        MenuNote(text: "The server's database is gone, but this Mac had a library. "
            + "Choose a copy under Backups to put it back.", tint: .red)
        MenuRow(symbol: "sparkles", title: "Start Fresh…",
                subtitle: "An empty library, with nothing watched") { confirm() }
    }

    private func confirm() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Start with an empty library?"
        alert.informativeText = "Everything the server knew — what has been watched, where each "
            + "film was stopped, favourites, collections, sign-ins — starts again from nothing. "
            + "Restoring a backup keeps all of that. The backups themselves are not touched."
        alert.addButton(withTitle: "Start Fresh")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        server.note("started fresh at the person's request")
        server.start(fresh: true)
    }
}
