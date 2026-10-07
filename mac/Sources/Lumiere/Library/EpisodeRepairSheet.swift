import SwiftUI
import LumiereKit

/// Shows what rebuilding a series' episodes from its filenames would change, and
/// applies it only once you have looked.
///
/// Preview-then-apply rather than a single command, because this rewrites names and
/// numbers across a whole series on the server, where every other Jellyfin client
/// will see it. A command that did that from a menu item with no visible
/// consequences would be one misclick away from being a disaster.
struct EpisodeRepairSheet: View {
    let seriesId: String
    let seriesName: String
    let client: JellyfinClient
    let repository: LibraryRepository
    let onDone: (Bool) -> Void

    @State private var model: EpisodeRepairModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header

            if let model {
                if model.isLoading {
                    ProgressView("Reading filenames…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    summary(model)
                    list(model)
                    options(model)
                }

                if let message = model.message {
                    Text(message)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                footer(model)
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 660, height: 620)
        .background(Theme.Palette.canvas)
        .task {
            let model = EpisodeRepairModel(
                seriesId: seriesId, client: client, repository: repository
            )
            self.model = model
            await model.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Fix Episodes from Filenames")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button("Cancel") { onDone(false) }
                .keyboardShortcut(.cancelAction)
            }
            Text(seriesName)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    @ViewBuilder
    private func summary(_ model: EpisodeRepairModel) -> some View {
        let changed = model.changedRows.count
        Text(
            changed == 0
                ? "\(model.rows.count) episodes read, and all of them already match "
                + "their filenames. Nothing to change."
                : "\(changed) of \(model.rows.count) episodes do not match their "
                + "filenames. Each folder becomes its own season, in release order, "
                + "so files that all claim to be episode 1 stop colliding."
        )
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

        ForEach(model.skipped) { skip in
            Label("\(skip.filename) — \(skip.reason)", systemImage: "exclamationmark.triangle")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func list(_ model: EpisodeRepairModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.rows) { row in
                    EpisodeRepairRow(row: row)
                    Divider().opacity(0.4)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func options(_ model: EpisodeRepairModel) -> some View {
        RepairThumbnailToggle(
            isOn: Binding(
                get: { model.refreshesThumbnails },
                set: { model.refreshesThumbnails = $0 }
            ),
            isDisabled: model.isApplying
        )
    }

    private func footer(_ model: EpisodeRepairModel) -> some View {
        HStack {
            if model.isApplying {
                ProgressView()
                    .controlSize(.small)
                Text("\(model.applied) of \(model.changedRows.count) applied…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Button("Apply to \(model.changedRows.count) Episodes") {
                Task {
                    let changed = await model.apply()
                    // Stays open on failure so the message can be read; the model
                    // only reports success when something actually landed.
                    if changed, model.message == nil { onDone(true) }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)
            .disabled(model.changedRows.isEmpty || model.isApplying)
        }
    }
}

/// One before-and-after line.
private struct EpisodeRepairRow: View {
    let row: EpisodeRepairModel.Row

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Text(row.changes ? row.proposedNumbering : row.currentNumbering)
                .font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(row.changes ? Theme.Palette.accent : Theme.Palette.textSecondary)
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.changes ? row.proposal.title : row.currentName)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)

                if row.changes {
                    // The old value, kept in view: the point of a preview is seeing
                    // what is being replaced, not only what is arriving.
                    Text("was \(row.currentNumbering) · \(row.currentName)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Text(row.filename)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)

            if !row.changes {
                Image(systemName: "checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }
}
