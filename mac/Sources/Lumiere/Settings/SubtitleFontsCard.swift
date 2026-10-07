import SwiftUI
import AppKit
import LumiereKit

/// Adding, choosing and removing subtitle fonts.
///
/// Its own view rather than another block inside the Playback pane, because it is
/// the one card there that owns state — the list has to reload after an import and
/// after a delete, and threading that through the pane would widen four more
/// properties for no gain.
struct SubtitleFontsCard: View {
    @AppStorage("subtitleFontFamily") private var family = ""

    @State private var files: [URL] = []
    @State private var message: String?

    /// The three the presets name. Listed even before anything is imported, so the
    /// picker is never a control with one option in it.
    private var bundledFamilies: [String] {
        SubtitleStyle.all.map(\.fontFamily)
    }

    private var families: [String] {
        SubtitleFonts.availableFamilies(bundled: bundledFamilies).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var body: some View {
        SettingsCard(
            title: "Subtitle Fonts",
            icon: "textformat",
            subtitle: "Fonts added here are used by the renderer",
            accessory: {
                Button("Add Font…") { importFonts() }
                    .font(Theme.Font.caption)
            },
            content: { content }
        )
        .task { reload() }
    }

    @ViewBuilder
    private var content: some View {
        Picker("Font", selection: $family) {
            // The empty tag rather than a named default: a style already carries a
            // face, and "whatever the style says" is a real answer that must not be
            // confused with a font that happens to be called Default.
            Text("Use the style's own font").tag("")
            Divider()
            ForEach(families, id: \.self) { Text($0).tag($0) }
        }
        SettingsNote("Overrides the face named by the style above, and nothing else about "
              + "it — the outline, size and position stay as the style sets them. As "
              + "with the style, an ASS or SSA script keeps its own typesetting.")

        if files.isEmpty {
            SettingsNote("No fonts added yet. Lumiere ships three, and any TrueType "
                       + "or OpenType file you add here joins them.")
        } else {
            ForEach(files, id: \.self) { file in
                fontRow(file)
            }
        }

        SettingsNote("Fonts are copied into Lumiere rather than referenced, so "
                   + "tidying up your Downloads folder later cannot quietly change "
                   + "how subtitles look. A change applies to the next file you "
                   + "play.")

        if let message {
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fontRow(_ file: URL) -> some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(SubtitleFonts.familyNames(in: file).first ?? file.lastPathComponent)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                // The filename under the family, because the two routinely
                // disagree and the file is what you would go looking for on disk.
                Text(file.lastPathComponent)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                try? SubtitleFonts.remove(file)
                reload()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.danger)
            }
            .buttonStyle(.plain)
            .labelledHelp("Remove this font. Nothing outside Lumiere is touched.")
        }
    }

    /// A plain open panel rather than a font picker.
    ///
    /// `NSFontPanel` lists what macOS has installed, which is precisely the set
    /// that already works — the point here is a font file that is *not* installed,
    /// sitting beside a fansub release, which only a file chooser can reach.
    private func importFonts() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        panel.message = "Choose TrueType or OpenType font files."
        guard panel.runModal() == .OK else { return }

        var failures: [String] = []
        for url in panel.urls {
            do {
                try SubtitleFonts.install(from: url)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        message = failures.first
        reload()
    }

    private func reload() {
        SubtitleFonts.seed()
        files = SubtitleFonts.installed()
        // A family that no longer exists would silently fall back to the default
        // face, which looks like the setting stopped working. Cleared instead, so
        // the picker says what is actually happening.
        if !family.isEmpty, !families.contains(family) { family = "" }
    }
}
