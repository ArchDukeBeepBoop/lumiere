import SwiftUI
import LumiereKit

/// The tiles a folder library draws, in both shapes and both modes.
///
/// Split from FolderBrowserView.swift for the project's 300-line limit. The
/// selecting and navigating variants are deliberately separate functions rather
/// than one with a flag: they differ in what a click *does*, which is the whole
/// distinction, and a grid that both selects and navigates on one click is one
/// where every mis-aim costs a screen change.
///
/// Files and folders are drawn at the same size and in the same flow, which is what
/// lets one grid hold both — see `FolderBrowserView.cellWidth`. They still differ in
/// what they show: a folder has a folder mark, a file has its own still or a drawn
/// card carrying its name.
extension FolderBrowserView {

    /// One section of the wall: folders, or files, at that section's own tile width.
    ///
    /// Fixed columns, counted from the width available, and left-aligned — which is
    /// what Finder's icon view is and what `.adaptive` cannot be made into.
    ///
    /// `.adaptive(minimum:)` stretches its columns to divide the leftover space, so
    /// tiles drifted apart as the window widened. `.adaptive(minimum:maximum:)` — the
    /// previous attempt — caps the *tile* but not the column: the columns still
    /// stretched, the tile sat centred in one, and each row centred itself
    /// independently, so a row of five and a row of four did not even start at the
    /// same x. Counting the columns ourselves is the only way to get a tile pitch
    /// that is exactly tile-plus-gutter with the slack collected at the right edge.
    func grid(_ entries: [LibraryEntry], width: CGFloat, available: CGFloat) -> some View {
        LazyVGrid(
            columns: Self.columns(width: width, available: available),
            alignment: .leading,
            spacing: Theme.Space.lg
        ) {
            ForEach(entries) { entry in
                cell(entry).id(entry.id)
            }
        }
    }

    /// As many whole tiles as fit, and never fewer than one.
    ///
    /// `+ gutter` on both sides of the division because n tiles carry n-1 gutters:
    /// without it a width holding exactly four tiles and three gaps reports three.
    static func columns(width: CGFloat, available: CGFloat) -> [GridItem] {
        let gutter = Theme.Space.lg
        let count = max(1, Int((available + gutter) / (width + gutter)))
        return Array(
            repeating: GridItem(.fixed(width), spacing: gutter, alignment: .top),
            count: count
        )
    }

    @ViewBuilder
    func cell(_ entry: LibraryEntry) -> some View {
        if selection.isActive {
            // Folders are selectable too. On these libraries a folder *is* the
            // unit — marking a season's worth watched means picking the folder,
            // and excluding them would leave the gesture half-useful.
            Button { selection.toggle(entry.id) } label: {
                selectableCell(entry)
                    .overlay { SelectionOverlay(isSelected: selection.contains(entry.id)) }
            }
            .buttonStyle(.plain)
        } else {
            navigableCell(entry)
        }
    }

    @ViewBuilder
    func selectableCell(_ entry: LibraryEntry) -> some View {
        if entry.item.isFolder {
            folderCell(entry)
        } else {
            fileCell(entry)
        }
    }

    @ViewBuilder
    func navigableCell(_ entry: LibraryEntry) -> some View {
        if entry.item.isFolder {
            Button {
                path.append((id: entry.item.id, name: entry.item.name))
            } label: {
                folderCell(entry)
            }
            .buttonStyle(.plain)
            .modifier(MetadataContextMenu(actions: actions(for: entry)))
        } else {
            // Straight to playback. A loose file has no metadata worth a detail page,
            // and going through one would add a click to reach the only useful action.
            Button { play(entry) } label: {
                fileCell(entry)
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens a file, naming its source where it has no item of its own.
    ///
    /// A merged file's `id` is the *source* id — see `ItemRecord.mergedFile` — so
    /// playing it means handing back the id of the item it was folded into together
    /// with which of that item's files to open. Everything else plays as itself.
    private func play(_ entry: LibraryEntry) {
        if let owner = entry.item.mergedOwnerId {
            onPlay(owner, entry.item.id)
        } else {
            onPlay(entry.item.id, nil)
        }
    }

    /// A video file: a Continue Watching card, at that card's own width.
    ///
    /// No longer follows the per-library shape control — that control was always
    /// documented as governing the *folder* tiles, and now it only does. A loose
    /// file in one of these libraries has no scraped poster, so its picture is a
    /// frame grab off the video itself: 16:9, whatever shape the folders above it
    /// are set to. Drawing it portrait meant a 2:3 frame with the still letterboxed
    /// inside it, or a drawn plate where a real picture existed.
    ///
    /// The card carries its own menu, so it is not wrapped in another.
    @ViewBuilder
    func fileCell(_ entry: LibraryEntry) -> some View {
        WideCard(
            entry: entry, serverURL: serverURL, pipeline: pipeline,
            width: fileWidth,
            titleOverride: fileTitle(entry),
            metadata: actions(for: entry)
        )
    }

    /// What a loose video file is called here: the name on disk.
    ///
    /// Not the user's title setting, and not a switch — automatic, because in these
    /// libraries the item's name is not an identifier. Nothing scrapes them, so
    /// Jellyfin's name is whatever its filename cleaner made of the filename, and
    /// the cleaner is built for `Movie.Title.2019.1080p.mkv`. Given a file named for
    /// the site it came from it stops at the first separator, so on the real "My
    /// Videos" library eleven different files are all called "EPORNER.COM -" — one
    /// name, one tile after another, no way to tell them apart or to find the one
    /// you want. The filename is the only thing that distinguishes them.
    ///
    /// Files only. A folder's name already *is* its name on disk, so there is
    /// nothing to recover, and `TitleFormatter` has no path for a folder anyway.
    ///
    /// `.originalFilename` for the name, minus the extension.
    ///
    /// The container is dropped here and only here. `.originalFilename` keeps it,
    /// which is right for the global title setting — someone who picks "Original
    /// filename" is asking what the file is called on disk, and `.mkv` is part of
    /// that. On these walls it is noise: every tile in the library ends in the same
    /// three or four letters, so the extension is a column of repeated text stealing
    /// room from the part of the name that differs.
    func fileTitle(_ entry: LibraryEntry) -> String {
        let name = TitleFormatter.title(for: entry.item, style: .originalFilename)
        return (name as NSString).deletingPathExtension
    }

    /// The title a tile actually draws: a folder's name, a file's filename.
    ///
    /// The filter field and the A–Z rail both go through this rather than reading
    /// the item's name, so that typing what is on a tile finds it and jumping to a
    /// letter lands where the letters on screen say it should. A view whose search
    /// box and whose labels disagree is worse than one with no search box.
    func displayName(_ entry: LibraryEntry) -> String {
        entry.item.isFolder ? entry.item.name : fileTitle(entry)
    }

    func folderCell(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            RoundedRectangle(cornerRadius: Theme.Radius.poster)
                .fill(Theme.Palette.surface)
                .aspectRatio(tileAspect, contentMode: .fit)
                .overlay {
                    // Sized from the tile, not fixed at 30pt. The slider runs
                    // 100–220, so a fixed glyph was a third of the smallest tile and
                    // a seventh of the largest — the mark that says "this is a
                    // folder" got quieter the bigger you made the folder.
                    Image(systemName: "folder")
                        .font(.system(size: cellWidth * 0.42, weight: .light))
                        .foregroundStyle(Theme.Palette.accent)
                }

            Text(entry.item.name)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                // Reserved, like the file tiles beside it — a folder with a one-word
                // name must not make its row shorter than its neighbours'.
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
        }
        // `cellWidth`: the same number the section's columns are built from, so a
        // tile fills its column exactly and the pitch is tile-plus-gutter.
        .frame(width: cellWidth)
    }

    /// What right-clicking a file or folder here offers.
    ///
    /// Deliberately smaller than the library grid's menu, and honestly so: the shell
    /// builds this view with a repository and no `AppModel`, so there is no client to
    /// re-scrape with and no host for the identify, edit or artwork sheets. Every
    /// command listed is one the repository can actually carry out — which is why
    /// `MetadataActions.refresh` is optional rather than a closure that shrugs.
    ///
    /// Watch state is the point of it. These libraries are exactly where "I have seen
    /// this one" cannot be recorded any other way: a loose file opens straight into
    /// the player, so there is no detail page with a tick on it.
    var entryContext: EntryActionContext {
        EntryActionContext(
            app: app,
            repository: repository,
            refreshRow: { _ in await load() }
        )
    }

    func actions(for entry: LibraryEntry) -> MetadataActions? {
        entryState.actions(
            for: entry,
            in: entryContext,
            extras: EntryActionExtras(
                beginSelection: { selection.begin(with: $0) },
                // Only for a file, and only with a client to ask. A folder has
                // no frames to take one from.
                generateThumbnail: app?.client == nil || entry.item.isFolder
                    ? nil
                    : { _ in Task { await generateThumbnail(for: entry) } },
                // These libraries deliberately have no provider behind them —
                // 3D and My Videos are files on a disk, not titles a scraper
                // knows — so Refresh, Identify and Collections are not commands
                // that could work here. Absent rather than present and shrugging.
                allowsMetadata: false
            )
        )
    }

    /// Takes a frame out of the file and makes it the tile's picture.
    ///
    /// The same call the detail page's episodes use, so a thumbnail generated here
    /// and one generated there are the same act — including the freeze that stops
    /// the next scrape replacing it.
    func generateThumbnail(for entry: LibraryEntry) async {
        guard let app, let client = app.client else { return }
        do {
            try await GeneratedThumbnail.apply(
                itemId: entry.id,
                runtimeSeconds: entry.item.runtimeSeconds,
                client: client
            )
            try? await repository.refreshItem(itemId: entry.id)
            await load()
        } catch {
            app.report(error.localizedDescription)
        }
    }
}
