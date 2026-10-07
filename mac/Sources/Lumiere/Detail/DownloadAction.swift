import SwiftUI
import LumiereKit

/// What the detail page's download button does, resolved from the current record.
///
/// A value rather than the manager itself: the button needs an icon, a tooltip and
/// one closure, and handing a view an actor would mean awaiting inside a body.
/// The download button's state and what pressing it does.
///
/// `isComplete` doubles as "pressing this deletes the file", which is why the
/// caller confirms first: the icon flips to a checkmark and one click on the same
/// spot threw away a finished download with no warning.
struct DownloadAction {
    let record: DownloadRecord?
    let act: () async -> Void

    var isComplete: Bool { record?.isPlayableOffline == true }

    var icon: String {
        guard let record else { return "arrow.down.circle" }
        switch record.state {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle.dotted"
        case .failed: return "exclamationmark.arrow.circlepath"
        case .complete:
            // The row can outlive the file. Claiming "downloaded" over something
            // deleted is worse than offering the download again.
            return record.isPlayableOffline ? "checkmark.circle.fill" : "arrow.down.circle"
        }
    }

    var help: String {
        guard let record else { return "Download for offline" }
        switch record.state {
        case .queued: return "Queued"
        case .downloading:
            if let fraction = record.fraction {
                return "Downloading \(Int(fraction * 100))%"
            }
            return "Downloading \(record.receivedBytes / 1_000_000) MB"
        case .failed: return record.errorMessage ?? "Download failed — click to retry"
        case .complete:
            return record.isPlayableOffline ? "Downloaded — click to remove" : "Download for offline"
        }
    }
}
