import SwiftUI
import LumiereKit

extension Notification.Name {
    /// Opens a title's page from anywhere. The object is its id.
    static let openDetail = Notification.Name("lumiere.openDetail")
    /// ⌘[: back a page, or out of a Settings page. See `ShellView`.
    static let goBack = Notification.Name("lumiere.goBack")
    static let settingsBack = Notification.Name("lumiere.settingsBack")
}

/// Shuffle's pick, as a suggestion: the title, what it is, a line of what it
/// is about, and three choices.
struct ShufflePick: View {
    let entry: LibraryEntry
    let onPlay: () -> Void
    let onAnother: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(entry.item.seriesName ?? entry.item.name)
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(2)
            Text(meta)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
            if let overview = entry.item.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Play", action: onPlay).keyboardShortcut(.defaultAction)
                Button("Another", action: onAnother)
                Spacer()
                Button("Open", action: onOpen)
            }
            .padding(.top, Theme.Space.xs)
        }
        .padding(Theme.Space.lg)
        .frame(width: 340)
    }

    private var meta: String {
        var parts: [String] = []
        if entry.item.itemType == .episode {
            if let code = entry.item.episodeCode() { parts.append(code) }
            parts.append(entry.item.name)
        } else if let year = entry.item.productionYear {
            parts.append(String(year))
        }
        return parts.joined(separator: " · ")
    }
}
