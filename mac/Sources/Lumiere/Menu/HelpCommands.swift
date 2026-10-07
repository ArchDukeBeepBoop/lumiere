import SwiftUI
import AppKit

/// The Help menu: where Lumiere keeps what it writes, one click away.
///
/// There is no manual to open, so the default "Lumiere Help" item only ever
/// said so. What someone looking in Help actually wants from a media client is
/// the log when something went wrong and the screenshots they took.
struct HelpCommands: View {
    var body: some View {
        Button("Keyboard Shortcuts") { ShortcutsWindow.show() }
            .keyboardShortcut("/", modifiers: .command)
        Divider()
        Button("Show Log in Finder") {
            let log = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Lumiere/lumiere.log")
            NSWorkspace.shared.activateFileViewerSelecting([log])
        }
        Button("Show Screenshots in Finder") {
            guard let pictures = FileManager.default
                .urls(for: .picturesDirectory, in: .userDomainMask).first else { return }
            let folder = pictures.appendingPathComponent("Lumiere", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }
}
