import Foundation
import LumiereKit

/// The banner after a Move to Trash, with the way back.
@MainActor
extension AppModel {

    /// Says what went to the Trash and offers Undo: the server puts the files
    /// back and their watch history with them, then a scan brings the items
    /// back into the library. Ten minutes, after which the Trash itself is
    /// the way back.
    func reportTrashed(_ name: String) {
        report("\(name) moved to the Trash.") { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                let back = try await client.untrashLast()
                try? await client.refreshServerLibrary()
                self.report(back > 0
                    ? "\(name) is back. It reappears when the scan reaches it."
                    : "Nothing could be put back — look in the Trash.")
            } catch {
                self.report("Too late to undo here — \(name) is still in the Trash.")
            }
        }
    }
}
