import SwiftUI
import LumiereKit

/// Says which of three states the connection is in.
///
/// Deliberately a banner and not an alert. The cache is a complete local copy of
/// the library, so an unreachable server is not a dead end — everything already
/// synced still browses and any local file still plays. A modal would block work
/// that does not need blocking. What was there before was worse than either: the
/// failure set a string nothing rendered, so a downed server was indistinguishable
/// from a server with nothing new.
///
/// It grew a `phase` when offline mode became automatic. A banner that only ever
/// says "can't reach it" leaves two real questions unanswered — is anything being
/// done about it, and did it ever come back — and the second one mattered most:
/// recovery used to be silent, so the banner simply vanished and the re-sync it
/// started was invisible.
struct ConnectionBanner: View {

    enum Phase: Equatable {
        /// Unreachable, with a probe due at the given time. Nil means no probe is
        /// scheduled — a failure that retrying cannot fix, like a rejected token.
        case offline(message: String, nextAttempt: Date?)
        /// A probe is in flight right now.
        case checking(message: String)
        /// The server answered. Shown briefly, then dropped by the shell.
        case reconnected
    }

    let phase: Phase
    let serverName: String
    /// How many downloaded titles still play. Zero hides the line rather than
    /// claiming "0 downloads are available", which is not news anyone needs.
    var playableOffline: Int = 0
    let onRetry: () -> Void

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: Theme.Space.md)

            if case .reconnected = phase {
                // Nothing to retry — the sync it started is already running, and the
                // sync panel is where that reports itself.
                EmptyView()
            } else {
                Button {
                    isRetrying = true
                    onRetry()
                } label: {
                    if isRetrying || isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRetrying || isChecking)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .liquidGlass(Rectangle(), .thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 1)
        }
        // A new message means a fresh failure, so the spinner has to reset or
        // Retry would stay stuck after the second attempt also fails. Keyed on the
        // whole phase now: a probe that ran and failed while Retry was spinning is
        // the same event as far as the button is concerned.
        .onChange(of: phase) { isRetrying = false }
    }

    private var isChecking: Bool {
        if case .checking = phase { return true }
        return false
    }

    private var icon: String {
        if case .reconnected = phase { return "bolt.horizontal.circle.fill" }
        return "bolt.horizontal.circle"
    }

    private var iconTint: Color {
        if case .reconnected = phase { return Theme.Palette.accent }
        return Theme.Palette.unwatched
    }

    private var title: String {
        switch phase {
        case .reconnected: return "Back online"
        case .checking: return "Checking \(serverName)…"
        case .offline: return "Offline — can't reach \(serverName)"
        }
    }

    /// The underlying error is worth showing — "connection refused" and
    /// "unauthorised" call for completely different actions — but it is secondary
    /// to the fact that the cached library still works, and to what happens next.
    private var detail: String {
        switch phase {
        case .reconnected:
            return "Reconnected to \(serverName). Catching your library up."
        case .checking(let message):
            return "Showing your cached library. \(message)"
        case .offline(let message, let nextAttempt):
            var parts = ["Browsing your cached library. \(message)"]
            if playableOffline > 0 {
                parts.append(
                    playableOffline == 1
                        ? "1 download still plays."
                        : "\(playableOffline) downloads still play."
                )
            }
            if let nextAttempt {
                parts.append("Trying again \(Self.relative.localizedString(for: nextAttempt, relativeTo: .now)).")
            }
            return parts.joined(separator: " ")
        }
    }

    /// One formatter, not one per redraw. The banner's detail line is rebuilt on
    /// every state change and a `RelativeDateTimeFormatter` is not cheap to make.
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
