import SwiftUI
import LumiereKit

/// The two tile controls in the breadcrumb: shape and size.
///
/// Split from FolderBrowserView.swift for the project's 300-line rule. Not private
/// here for the same reason — the breadcrumb that draws them is in that file, and
/// Swift scopes `private` to the file.
extension FolderBrowserView {

    /// Icons, list or columns — Finder's three, in Finder's order.
    ///
    /// A segmented control rather than a menu: there are three of them, they are
    /// mutually exclusive, and which one is active is worth being able to see
    /// without opening anything.
    var viewModeControl: some View {
        Picker("", selection: Binding(
            get: { viewMode },
            set: { viewModeRaw = FolderViewMode.setting($0, for: libraryId, in: viewModeRaw) }
        )) {
            ForEach(FolderViewMode.allCases) { mode in
                Image(systemName: mode.symbol).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 108)
        .labelledHelp("How this library is laid out")
    }

    /// Square or landscape *folder* tiles, remembered per library.
    ///
    /// It used to set the shape of everything here. Files no longer follow it — a
    /// video is always a 16:9 card — so what is left is the genuine question: whether
    /// a folder reads as a Finder-style square icon or as a wide plate.
    var shapeControl: some View {
        Button {
            var libraries = Set(tileShapeRaw.split(separator: ",").map(String.init))
            if isLandscape { libraries.remove(libraryId) } else { libraries.insert(libraryId) }
            tileShapeRaw = libraries.sorted().joined(separator: ",")
        } label: {
            Image(systemName: isLandscape ? "rectangle" : "square")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .labelledHelp(isLandscape
              ? "Wide folder tiles — switch to square icons"
              : "Square folder icons — switch to wide tiles")
    }

    /// Same control and range as LibraryGridView's — one shared feel for every grid.
    var tileSizeControl: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textMuted)
            // Committed on release, like the library grid's — and this is the
            // half that "same control and range" missed. The width feeds the
            // image request key, so a continuous binding re-requests and
            // re-decodes every visible tile at each of the sixteen steps on the
            // way from 100 to 260.
            Slider(
                value: $draftTileWidth, in: 100...260, step: 10,
                onEditingChanged: { editing in
                    if !editing { tileWidth = draftTileWidth }
                }
            )
            .frame(width: 90)
            .onAppear { draftTileWidth = tileWidth }
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textMuted)
        }
        .labelledHelp("Tile size")
    }
}
