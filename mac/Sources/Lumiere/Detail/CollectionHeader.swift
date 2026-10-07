import SwiftUI
import LumiereKit

/// A collection's header: not one piece of media, so no Play button, no runtime,
/// no rating — just what it is, how many titles it holds, and the two ways to
/// change that: add more members, or ask the server for real artwork when the
/// mosaic fallback below is standing in for it.
struct CollectionHeader: View {
    @Bindable var model: DetailModel
    let entry: LibraryEntry
    let pipeline: ImagePipeline
    let serverURL: URL
    let onAddItems: () -> Void
    /// nil where there is no client to ask — a preview or demo context. Owned by
    /// the caller rather than done inline here, because a refresh that actually
    /// changed something has to reload the page, and only DetailView can do that.
    var onRefreshArtwork: (() async -> Void)?
    /// Opens the authoring wizard on this one collection.
    var onFinish: (() -> Void)?
    /// Asks to delete this collection. Confirmed by the page, not here.
    var onDelete: (() -> Void)?
    /// Identify… — choose its film series. See `CollectionSeriesSheet`.
    var onIdentify: (() -> Void)?
    /// Scan Collection — find its series, name, picture and fill it, by itself.
    var onScan: (() async -> Void)?
    @State private var isScanning = false

    @Environment(\.displayScale) private var scale
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle
    @State private var isRefreshing = false
    /// Films in this collection's series the library lacks. See `missingFilms`.
    @State private var missing: [String] = []

    /// Sized like every other detail page, rather than to a fixed band.
    ///
    /// A collection's backdrop was pinned at 300pt while series and films size
    /// theirs to a full-width 16:9, so opening a collection after a series dropped
    /// the art to roughly half the height for no reason anyone could see — the same
    /// picture, smaller, on the page that has the *most* art to show.
    ///
    /// `Color.clear.aspectRatio(_:contentMode: .fit)` is what does it, and a
    /// `GeometryReader` cannot: a reader fills whatever it is handed and reports
    /// nothing back to its parent, so the height would have to be guessed from the
    /// screen — wrong the moment the sidebar opens or the window is resized.
    var body: some View {
        Color.clear
            .aspectRatio(Theme.Art.backdropAspect, contentMode: .fit)
            .overlay { backdrop }
            // Only the band the title and actions sit on. See `BackdropTextWash`.
            .overlay { BackdropTextWash() }
            // Overlaid at the bottom, the same as a series or film page, so the
            // title and actions sit at the foot of the art rather than over the
            // middle of it. Nothing darkens it any more — see the backdrop below.
            .overlay(alignment: .bottomLeading) { content }
            .clipped()
    }

    private var backdrop: some View {
        ZStack {
            GeometryReader { geometry in
                    RemoteImage(
                        request: .backdrop(
                            for: entry, serverURL: serverURL,
                            width: geometry.size.width, scale: scale
                        ),
                        pipeline: pipeline,
                        // Text is drawn on this. See `Theme.Palette.artworkPlaceholder`.
                        carriesText: true
                    )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }

        }
    }

    /// No portrait poster.
    ///
    /// It was 180pt of a 2:3 cover sitting beside its own backdrop, which is the
    /// same artwork twice at two aspect ratios — and on a collection it is usually a
    /// generated collage, so it says nothing the row of tiles below does not. Series
    /// and film pages dropped theirs for the same reason; this brings collections
    /// into line and gives the text and the actions the full width.
    ///
    /// It carries the same three bands a series or film header does — name, a
    /// tight metadata line, then the actions — at the same sizes and on the same
    /// 40pt page margin. A collection never has logo artwork, so its name is set
    /// at `detailTitle`, which is exactly what those pages fall back to when the
    /// server has no logo for them either.
    private var content: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(entry.item.name)
                    .font(Theme.Font.detailTitle)
                    .foregroundStyle(Theme.Palette.onArtworkText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: DetailMetrics.readingMeasure, alignment: .leading)

                Text(countText)
                    .font(Theme.Font.detailMeta)
                    .foregroundStyle(Theme.Palette.onArtworkTextMuted)
                    .task(id: entry.id) { missing = await model.repository.missingFilms(collectionId: entry.id) }

                if let overview = entry.item.overview, !overview.isEmpty {
                    ExpandableText(text: overview, collapsedLines: 3)
                        .frame(maxWidth: DetailMetrics.readingMeasure, alignment: .leading)
                }

                actions
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.shelfInset)
        .padding(.bottom, Theme.Space.xxl)
        // The synopsis inside is `ExpandableText`, shared with the page below where
        // the page colours are correct. See `onArtwork`.
        .onArtwork()
    }


    private var allWatched: Bool {
        !model.collectionItems.isEmpty && model.collectionItems.allSatisfy { !$0.showsUnwatchedMarker && $0.progress == nil }
    }

    private var countText: String {
        let count = model.collectionItems.count
        let held = "\(count) title\(count == 1 ? "" : "s")"
        guard !missing.isEmpty else { return held }
        let shown = missing.prefix(3).joined(separator: ", ")
        let more = missing.count > 3 ? " and \(missing.count - 3) more" : ""
        return held + " · missing " + shown + more
    }

    /// One primary, then quiet glyphs — the shape a film or series page has.
    ///
    /// This was five labelled buttons in four different styles side by side, and
    /// the eye had nowhere to land: "Add Items…" is the thing you came to a
    /// collection's header to do, and it was the same size and weight as "Refresh
    /// Artwork". Everything but the primary and the order picker is now an icon
    /// with a tooltip, exactly as the hero header's watched/favourite/download row
    /// is. Nothing was removed.
    private var actions: some View {
        HStack(spacing: Theme.Space.md) {
            Button("Add Items…", action: onAddItems)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)

            HStack(spacing: Theme.Space.xs) {
                // Every title in it at once — a show down to its episodes. The
                // server does the cascade; see store.SetPlayed.
                QuietIconButton(
                    systemName: allWatched ? "checkmark.circle.fill" : "checkmark.circle",
                    help: allWatched ? "Mark Collection Unwatched" : "Mark Collection Watched"
                ) {
                    Task { await model.setCollectionWatched(!allWatched) }
                }

                // The same wizard the scan ends on, reachable for a collection that
                // already exists — the ones built before it, and the ones built by
                // hand, need naming just as much as a freshly scanned one.
                if let onFinish {
                    QuietIconButton(
                        systemName: "square.and.pencil",
                        help: "Finish Details… — name and describe this collection",
                        action: onFinish
                    )
                }

                // Only offered when the server can actually act on it: refreshing
                // requires the app's client, which a preview or demo context lacks.
                if let onRefreshArtwork {
                    QuietIconButton(
                        systemName: "arrow.clockwise",
                        help: "Refresh Artwork — ask the server for real art in place "
                            + "of the mosaic below",
                        isBusy: isRefreshing
                    ) {
                        Task {
                            isRefreshing = true
                            await onRefreshArtwork()
                            isRefreshing = false
                        }
                    }
                }

                if let onIdentify {
                    QuietIconButton(
                        systemName: "magnifyingglass",
                        help: "Identify… — choose this collection's film series",
                        action: onIdentify
                    )
                }
                if let onScan {
                    QuietIconButton(
                        systemName: "wand.and.stars",
                        help: "Scan Collection — find its series and fill in its poster, details and films",
                        isBusy: isScanning
                    ) {
                        Task {
                            isScanning = true
                            await onScan()
                            isScanning = false
                        }
                    }
                }

                if let onDelete {
                    QuietIconButton(
                        systemName: "trash",
                        help: "Delete this collection…",
                        isDestructive: true,
                        action: onDelete
                    )
                }
            }

            // A collection is a viewing plan as much as a grouping, so how it is
            // ordered is a way of reading it. Remembered per collection rather than
            // per session: arranging a personal watch order and finding the page
            // back in release order next time would make the arranging pointless.
            Picker("", selection: Binding(
                get: { model.collectionSort },
                set: { model.collectionSort = $0 }
            )) {
                ForEach(CollectionOrder.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 210)

            // Only in the personal order, and only once there is one to forget.
            if model.collectionSort == .personal, !model.collectionRanks.isEmpty {
                Button("Reset Order") { Task { await model.clearPersonalOrder() } }
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .labelledHelp("Forget the arrangement and go back to release order")
            }
        }
        .padding(.top, Theme.Space.xs)
    }
}
