import SwiftUI
import LumiereKit

/// Layout B: a compact continue row, then a dense poster wall that pages.
///
/// Split out of HomeView.swift for the project's 300-line limit.
struct CompactHomeView: View {
    let model: HomeModel
    let pipeline: ImagePipeline
    let serverURL: URL
    /// Built by the parent, which owns the sheets these commands open.
    ///
    /// Passed in rather than rebuilt here: this layout had no menu at all, and the
    /// reason is that the actions live where the state does. Handing the factory
    /// down keeps the two together instead of growing a second copy that drifts.
    var actions: (LibraryEntry) -> MetadataActions? = { _ in nil }
    /// For the quick links, which switch section through `pendingRoute`.
    var app: AppModel?
    /// Opens a library, the same way the sidebar row and a "See All" do.
    var onOpenLibrary: (LibraryRecord) -> Void = { _ in }
    /// The See Alls. Compact had none: every section showed everything it had, so
    /// the one layout meant to be scannable was the one that put fifty unfinished
    /// titles on screen at once. Each capped section now offers the full list on a
    /// page built for it.
    var onSeeAllLatest: (LibraryRecord) -> Void = { _ in }
    var onSeeAllResume: () -> Void = {}
    var onSeeAllNextUp: () -> Void = {}
    /// For resolving the section order against the libraries that exist.
    var libraries: [LibraryRecord] = []

    @AppStorage(HomeOrder.storageKey) private var storedOrder = ""

    /// How much of a section Compact shows before deferring to its See All.
    ///
    /// Two numbers because the cells are two shapes: a poster grid fits twelve
    /// without becoming a wall, while the wide resume rows are three times the
    /// width and six is already a screenful.
    static let posterLimit = 12
    static let rowLimit = 6

    /// Not private: HomeView+Compact+Rows.swift draws from it.
    var sections: [HomeSection] {
        HomeOrder.resolve(stored: storedOrder, libraryIds: libraries.map(\.id))
    }

    // Not private: the rows file lays its grids out with these.
    let columns = [
        GridItem(.adaptive(minimum: 130, maximum: 170), spacing: Theme.Space.lg, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header

                // The same order Classic and Hero draw, from the same preference.
                // Compact renders each section its own way — grids where they are
                // rows elsewhere — but which comes first is one decision for the
                // whole app rather than three.
                ForEach(sections, id: \.id) { section in
                    view(for: section)
                }

                // Always last, and not part of the order: the paging wall is what
                // this layout *is*, and every section above it is a shortlist you
                // read on the way down to it.
                wall
            }
            .padding(.vertical, Theme.Space.xl)
        }
        .polishedScrolling()
    }

    private var header: some View {
        Text(greeting)
            .font(Theme.Font.hero)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Space.shelfInset)
    }

    /// The same header a `Shelf` draws, for the two sections here that are grids
    /// rather than rows. Compact used the smaller in-panel `sectionHeader` and so
    /// read as a different screen from the other two layouts.
    func sectionTitle(_ title: String, subtitle: String? = nil) -> some View {
        ShelfTitleCard(title: title, subtitle: subtitle)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<5: return "Still up"
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

/// The compact layout's continue-watching row: a small thumbnail, a title, and a
/// progress bar. Denser than a `WideCard` because this layout trades size for count.
struct CompactResumeRow: View {
    let entry: LibraryEntry
    let serverURL: URL
    let pipeline: ImagePipeline

    @State private var isHovering = false
    @Environment(\.displayScale) private var scale
    @Environment(\.folderLibraryIds) private var folderLibraryIds
    @AppStorage("titleStyle") private var titleStyle: TitleStyle = .metadataTitle

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            RemoteImage(
                request: .backdrop(
                    for: entry, serverURL: serverURL, width: 64, scale: scale,
                    preferSeriesThumb: true
                ),
                pipeline: pipeline
            )
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.badge))

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                // See `FolderTitle`: a loose file is its filename here too.
                Text(entry.item.seriesName
                     ?? FolderTitle.title(
                         for: entry, style: titleStyle, folderLibraryIds: folderLibraryIds
                     ))
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(entry.remainingText ?? "")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .lineLimit(1)

                if let progress = entry.progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Palette.border)
                            Capsule()
                                .fill(Theme.Palette.accent)
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(isHovering ? Theme.Palette.surfaceRaised : Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .animation(Theme.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
    }
}
