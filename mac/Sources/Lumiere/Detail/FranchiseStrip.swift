import SwiftUI
import LumiereKit

/// The whole franchise, in release order, with what you have seen marked.
///
/// The one structural thing a large anime library was missing. *Ghost in the
/// Shell* is a series, four films and an OVA line filed across two libraries;
/// until now nothing on any of their pages said they were one thing, so the
/// order lived in the viewer's head.
///
/// Not a shelf of posters. A shelf says "here is more"; this says "here is the
/// sequence, and here is where you are in it" — so it is a list, ordered, with
/// the current title marked and each part's year beside it. Reading down it
/// answers the only question a franchise page has.
struct FranchiseStrip: View {
    let franchise: LibraryRepository.Franchise
    let serverURL: URL
    let pipeline: ImagePipeline

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(franchise.name)
                    .font(Theme.Font.shelfHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("\(franchise.parts.count) parts, in release order")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }

            VStack(spacing: 0) {
                ForEach(Array(franchise.parts.enumerated()), id: \.element.id) { index, part in
                    row(part)
                    if index < franchise.parts.count - 1 {
                        Divider().padding(.leading, 30)
                    }
                }
            }
        }
        .detailMargin()
    }

    @ViewBuilder
    private func row(_ part: LibraryRepository.FranchisePart) -> some View {
        NavigationLink(value: DetailRoute.forEntry(part.entry)) {
            HStack(spacing: Theme.Space.md) {
                // Seen, started, or not begun — the three states that matter
                // when you are deciding where to pick a franchise back up.
                Image(systemName: marker(part.entry))
                    .font(.system(size: 12))
                    .foregroundStyle(part.entry.isPlayed
                                     ? Theme.Palette.accent : Theme.Palette.textMuted)
                    .frame(width: 18)

                Text(part.entry.item.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(part.isCurrent
                                     ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .fontWeight(part.isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                if part.isCurrent {
                    Text("You are here")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.accent)
                }

                Spacer(minLength: Theme.Space.md)

                Text(detail(part.entry))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .monospacedDigit()
            }
            .padding(.vertical, Theme.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(part.isCurrent)
    }

    private func marker(_ entry: LibraryEntry) -> String {
        if entry.isPlayed { return "checkmark.circle.fill" }
        if entry.resumeStart > 0 { return "circle.lefthalf.filled" }
        return "circle"
    }

    /// The year and what kind of thing it is — the two facts that make a release
    /// order legible as one.
    private func detail(_ entry: LibraryEntry) -> String {
        var parts: [String] = []
        if let year = entry.item.productionYear { parts.append(String(year)) }
        switch entry.item.itemType {
        case .series:
            if let seasons = entry.item.childCount, seasons > 0 {
                parts.append(seasons == 1 ? "series" : "\(seasons) seasons")
            } else {
                parts.append("series")
            }
        case .movie:
            parts.append("film")
        default:
            break
        }
        return parts.joined(separator: " · ")
    }
}
