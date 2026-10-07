import SwiftUI
import LumiereKit

/// The wizard's two read-only panels: the poster it is about to set, and the
/// titles the collection actually holds.
///
/// Split from CollectionAuthoringSheet.swift for the project's 300-line limit.
/// Both exist to make the decision checkable — a name and a year are easy to accept
/// without looking, and the contents list is the thing that reveals a scan grouped
/// the wrong eleven files.
extension CollectionAuthoringSheet {

    var artwork: some View {
        SettingsCard(title: "Poster", icon: "photo") {
            HStack(alignment: .top, spacing: Theme.Space.lg) {
                if let entry {
                    RemoteImage(
                        request: .poster(
                            for: entry, serverURL: serverURL, width: 110, scale: scale
                        ),
                        pipeline: pipeline
                    )
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .strokeBorder(Theme.Palette.border, lineWidth: 1)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Button("Search for Artwork…") { isChoosingArtwork = true }
                    SettingsNote(CollectionDraft.needsArtwork(entry)
                        ? "No poster yet. The search offers whatever your server's "
                        + "providers return for this name, and takes a file from this "
                        + "Mac when they return nothing — which for a franchise "
                        + "collection is common, since providers index titles rather "
                        + "than franchises."
                        : "A poster is set. Search again to replace it.")
                }
                Spacer(minLength: 0)
            }
        }
    }

    var contents: some View {
        SettingsCard(
            title: "Contents",
            icon: "square.stack",
            subtitle: "\(members.count) titles, grouped into rows by kind"
        ) {
            ForEach(members.prefix(12)) { member in
                HStack(spacing: Theme.Space.sm) {
                    Text(member.item.name)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(member.item.productionYear.map(String.init) ?? "—")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
            if members.count > 12 {
                SettingsNote("…and \(members.count - 12) more.")
            }
        }
    }

}
