import SwiftUI

/// The one place an empty view is drawn.
///
/// Each screen used to roll its own centred `Text`, which meant an empty library
/// and an unreachable server rendered as the same flat sentence — and the second
/// one is a problem the user can act on. `reason` exists to keep those apart.
struct EmptyStateView: View {

    enum Reason {
        /// Genuinely nothing to show: no favourites yet, a filter that matches
        /// nothing, a search with no hits.
        case empty(icon: String, title: String, detail: String?)
        /// Nothing to show *because* the server could not be reached and nothing
        /// has been cached yet. Offers the retry, since waiting will not help.
        case offline(serverName: String, retry: () -> Void)
    }

    let reason: Reason

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.Palette.textMuted)

            Text(title)
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)

            if let detail {
                Text(detail)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if case .offline(_, let retry) = reason {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xl)
    }

    private var icon: String {
        switch reason {
        case .empty(let icon, _, _): return icon
        case .offline: return "bolt.horizontal.circle"
        }
    }

    private var title: String {
        switch reason {
        case .empty(_, let title, _): return title
        case .offline(let serverName, _): return "Can't reach \(serverName)"
        }
    }

    private var detail: String? {
        switch reason {
        case .empty(_, _, let detail): return detail
        case .offline:
            return "Nothing has been cached from this server yet, so there is "
                 + "nothing to show offline."
        }
    }
}
