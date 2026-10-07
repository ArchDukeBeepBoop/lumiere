import SwiftUI
import LumiereKit

/// Every merged series in the library, with what a repair would do to each.
///
/// Expandable rather than a flat list of episodes: the sweep found twenty series
/// and around six hundred episodes, and a wall of six hundred rows is not something
/// anyone reads before pressing a button. The summary is what you decide on; the
/// detail is there for the one you are unsure about.
struct MergedSeriesSheet: View {
    let repository: LibraryRepository
    let client: JellyfinClient
    let onDone: (Bool) -> Void

    @State private var model: MergedSeriesModel?
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header

            if let model {
                if model.isScanning {
                    ProgressView("Scanning every series…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.found.isEmpty {
                    empty
                } else {
                    summary(model)
                    list(model)
                    RepairThumbnailToggle(
                        isOn: Binding(
                            get: { model.refreshesThumbnails },
                            set: { model.refreshesThumbnails = $0 }
                        ),
                        isDisabled: model.isApplying
                    )
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
        .frame(width: 720, height: 640)
        .background(Theme.Palette.canvas)
        .task {
            let model = MergedSeriesModel(repository: repository, client: client)
            self.model = model
            await model.scan()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Merged Series")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button("Close") { onDone(!(model?.completed.isEmpty ?? true)) }
            }
            Text("Series where the scraper filed several shows as one, so different "
               + "episodes claim the same season and number.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Palette.accent)
            Text("No merged series left.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Every series whose filenames carry a 1x04-style marker agrees with "
               + "its metadata. Shows numbered straight through — One Piece, "
               + "Detective Conan — have no marker to read, so they are never "
               + "touched either way.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(_ model: MergedSeriesModel) -> some View {
        HStack {
            Text("\(model.found.count) series, "
               + "\(model.found.reduce(0) { $0 + $1.changes.count }) episodes")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Button("Select All") { model.selectAll() }
                .buttonStyle(.plain)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.accent)
                .disabled(model.isApplying)
        }
    }

    private func list(_ model: MergedSeriesModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.found) { series in
                    MergedSeriesRow(
                        series: series,
                        isSelected: model.selected.contains(series.id),
                        isDone: model.completed.contains(series.id),
                        isExpanded: expanded.contains(series.id),
                        onToggle: { model.toggle(series.id) },
                        onExpand: {
                            if expanded.contains(series.id) {
                                expanded.remove(series.id)
                            } else {
                                expanded.insert(series.id)
                            }
                        }
                    )
                    .disabled(model.isApplying)
                    Divider().opacity(0.4)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func footer(_ model: MergedSeriesModel) -> some View {
        HStack {
            if model.isApplying {
                ProgressView().controlSize(.small)
                Text(model.progress ?? "Applying…")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Repair \(model.selectedEpisodeCount) Episodes") {
                Task { _ = await model.apply() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)
            .disabled(model.selectedEpisodeCount == 0 || model.isApplying)
        }
    }
}

/// The thumbnail switch, shared with the single-series sheet so the two cannot
/// come to mean different things.
struct RepairThumbnailToggle: View {
    @Binding var isOn: Bool
    var isDisabled: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Replace thumbnails with a frame from each file").font(Theme.Font.body)
                Text("Every renumbered episode was showing another episode's still — "
                   + "the one the scraper matched them all to. This takes a frame a "
                   + "fifth of the way into each file instead, from the trickplay "
                   + "images the server already generated. Needs Trickplay enabled "
                   + "on the server's library; where it is missing, the numbering is "
                   + "still repaired and the thumbnails are left alone.\n\n"
                   + "Each episode that gets one is frozen, so the next scrape cannot "
                   + "put the duplicate back. The server has no lock for images alone, "
                   + "so those episodes also stop receiving new synopses and air dates.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.Palette.accent)
        .disabled(isDisabled)
    }
}
