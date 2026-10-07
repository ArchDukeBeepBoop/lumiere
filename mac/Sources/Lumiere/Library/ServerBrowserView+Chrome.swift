import SwiftUI
import LumiereKit

/// The breadcrumb and the controls that sit in it: the batch toggle, the playlist
/// edit switch, and the delete button that only appears while editing.
///
/// Split from ServerBrowserView.swift for the project's 300-line limit — the batch
/// control was what pushed it over.
extension ServerBrowserView {
    var breadcrumb: some View {
        HStack(spacing: Theme.Space.xs) {
            Button(title) { path = [] }
                .buttonStyle(.plain)
                .foregroundStyle(path.isEmpty ? Theme.Palette.textPrimary : Theme.Palette.accent)

            ForEach(Array(path.enumerated()), id: \.offset) { index, level in
                Image(systemName: "chevron.right")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                Button(level.name) { path = Array(path.prefix(index + 1)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        index == path.count - 1 ? Theme.Palette.textPrimary : Theme.Palette.accent
                    )
            }
            Spacer()
            if !entries.isEmpty {
                // Says how far in you are while there is more to come. A flat count
                // of what happened to be loaded is what made a truncated listing
                // look complete.
                Text(entries.count < total
                     ? "\(entries.count) of \(total) items"
                     : "\(entries.count) items")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            // Only inside a playlist, and only when its rows carry entry ids —
            // without those there is nothing removal could name, and an Edit button
            // that cannot edit is a broken promise.
            // Tracks and playlist rows only: selecting artists or albums to add to
            // a playlist would add containers, which Jellyfin expands unpredictably.
            if offersMusicActions, !entries.isEmpty {
                Button { selection.isActive ? selection.end() : selection.begin() } label: {
                    Image(systemName: selection.isActive
                          ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection.isActive
                                 ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .labelledHelp("Select several and act on all of them")
            }

            if isPlaylist, !playlistEntryIds.isEmpty {
                Button(isEditingPlaylist ? "Done" : "Edit") {
                    withAnimation(Theme.Motion.hover) { isEditingPlaylist.toggle() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.accent)

                // Only while editing: a delete button sitting permanently beside a
                // playlist you are only listening to is one misclick from gone.
                if isEditingPlaylist, let current = path.last {
                    Button("Delete Playlist") {
                        deleteTarget = PlaylistTarget(id: current.id, name: current.name)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.danger)
                }
            }
        }
        .font(Theme.Font.body)
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
    }
}
