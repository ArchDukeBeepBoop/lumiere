import Foundation
import Observation
import LumiereKit

/// Whether the library has picked up new damage since you last looked.
///
/// The Library Health card answers "what is wrong" only when opened, and a
/// new unreadable file or a hollow show is exactly the thing nobody goes
/// looking for. This checks after every sync and raises a dot on Settings
/// when any count has grown past what you last saw. Opening the card is the
/// acknowledgement.
@MainActor
@Observable
final class LibraryHealthWatch {

    static let shared = LibraryHealthWatch()

    /// Kinds whose count has grown since the card was last opened.
    private(set) var grown: Set<String> = []

    /// Set by `HomeTimings` when rebuilds have been slow; raises the dot too.
    var homeIsSlow = false

    var hasNews: Bool { !grown.isEmpty || homeIsSlow }

    private static let seenKey = "libraryHealthSeen"

    /// Compares the server's counts with the ones last acknowledged.
    func check(_ client: JellyfinClient?) async {
        guard let issues = try? await client?.libraryHealth() else { return }
        update(with: issues)
    }

    /// The same comparison, for counts already fetched.
    func update(with issues: [LibraryHealthIssue]) {
        let seen = UserDefaults.standard.dictionary(forKey: Self.seenKey) as? [String: Int]
        guard let seen else {
            // First run: today's counts are the baseline, not news.
            acknowledge(issues)
            return
        }
        grown = LibraryHealthIssue.grown(issues, since: seen)
    }

    /// Marks the counts on screen as seen.
    func acknowledge(_ issues: [LibraryHealthIssue]) {
        let counts = Dictionary(uniqueKeysWithValues: issues.map { ($0.kind, $0.count) })
        UserDefaults.standard.set(counts, forKey: Self.seenKey)
        grown = []
    }
}
