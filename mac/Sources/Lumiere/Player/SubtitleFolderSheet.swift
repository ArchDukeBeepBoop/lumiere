import SwiftUI
import LumiereKit

/// The review step: each episode with the subtitle matched to it, any one
/// changeable, before anything is saved.
struct SubtitleFolderSheet: View {
    let episodes: [LibraryEntry]
    let files: [URL]
    let onApply: ([String: URL]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: [String: URL] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Add Subtitles").font(Theme.Font.sectionHeader)
            Text("\(choice.count) of \(episodes.count) matched by episode number or name. Change any that are wrong.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(episodes) { episode in
                        HStack(spacing: Theme.Space.md) {
                            Text(episode.item.name)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { choice[episode.id] },
                                set: { choice[episode.id] = $0 }
                            )) {
                                Text("None").tag(URL?.none)
                                ForEach(files, id: \.self) { file in
                                    Text(file.lastPathComponent).tag(URL?.some(file))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 260)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 360)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Subtitles") {
                    onApply(choice)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(choice.isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 620)
        .glassSheet()
        .onAppear {
            choice = SubtitleMatcher.match(
                videos: episodes.map { (id: $0.id, name: PlayerModel.filename(of: $0)) },
                subtitles: files
            )
        }
    }
}
