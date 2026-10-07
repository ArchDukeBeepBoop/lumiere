import SwiftUI
import LumiereKit

/// The background details, in one block at the foot of the page.
///
/// These used to be scattered: the year, the age rating and the resolution were
/// crammed onto the hero's classification line, the runtime appeared twice, the
/// studios appeared nowhere at all, and the only place to learn which languages a
/// file carried was to expand a panel called "Media info" and read a list of
/// codecs. None of that is *identity* — it is the set of facts you check once,
/// while deciding whether to press Play — and the TV app puts exactly that set in
/// an About block below the artwork. This is that block.
///
/// It deliberately has no genre row. The hero's classification line reads "TV Show
/// · Thriller · Drama", which is where the eye already looks for them; a second
/// listing here would be duplication rather than structure.
///
/// The stream-by-stream detail is not duplicated either. This block summarises —
/// "English (Dolby Digital 5.1), Japanese (AAC 2.0)" — and `TechnicalPanel`, still
/// collapsed by default, sits underneath it holding the per-track specifics. The
/// two are the same material at two magnifications, which is why the panel is
/// nested here rather than floating a section away from it.
struct DetailAbout: View {
    let model: DetailModel
    let source: MediaSource?
    let capabilities: SystemCapabilities
    /// Which libraries are plain folders. See `FolderTitle`.
    ///
    /// Not read from the environment: this type's rows are built in
    /// DetailAbout+Rows.swift as strings, and an `@Environment` property there would
    /// be a second place for the same answer to come from.
    var folderLibraryIds: Set<String> = []

    var body: some View {
        // Nothing to say and nothing to expand means no section at all — an
        // "About" heading over an empty box is worse than the absence.
        if !rows.isEmpty || source != nil {
            DetailSection(title: "About") {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    if !rows.isEmpty { table }
                    if let source {
                        TechnicalPanel(source: source, capabilities: capabilities)
                    }
                }
                .frame(maxWidth: DetailMetrics.aboutMeasure, alignment: .leading)
            }
        }
    }

    /// Hairlines between the rows rather than around the block. A bordered card
    /// would make this read as a panel — a thing to interact with — where it is a
    /// list of facts, and the TV app's own is ruled the same way.
    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Palette.border)
                        .frame(height: 1)
                }
                aboutRow(row.label, row.value)
            }
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xl) {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: DetailMetrics.aboutLabelWidth, alignment: .leading)
            Text(value)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                // Wraps rather than truncates. A cast of studios or a dozen
                // subtitle languages is long, and a truncated fact is not a fact.
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.md)
    }
}
