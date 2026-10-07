import SwiftUI
import LumiereKit

/// Home's background following what the pointer is on, as Apple TV's does
/// with focus: the hovered title's artwork, softened and dimmed, fades in
/// behind the shelves.
@MainActor
@Observable
final class HomeAmbient {
    static let shared = HomeAmbient()
    private(set) var entry: LibraryEntry?
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// From a card's hover. A short settle, so sweeping across a shelf does
    /// not flick through every picture on the way.
    func hover(_ entry: LibraryEntry, _ isHovering: Bool) {
        pending?.cancel()
        guard isHovering else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.entry = entry
        }
    }

    func clear() {
        pending?.cancel()
        entry = nil
    }
}

/// The picture behind Home. Follows the same switches as the backdrop at the
/// top of Home, separately in the private room.
struct HomeAmbientBackdrop: View {
    let pipeline: ImagePipeline
    let serverURL: URL
    var app: AppModel?
    @AppStorage(Preference.homeShowsBackdrop.name) private var homeBackdrop = Preference.homeShowsBackdrop.defaultValue
    @AppStorage(Preference.homeFollowsHover.name) private var followsHover = Preference.homeFollowsHover.defaultValue
    @AppStorage(Preference.roomBlursCovers.name) private var blursPrivate = Preference.roomBlursCovers.defaultValue
    @Environment(\.displayScale) private var scale

    /// A private title whose cover is held back is not shown large behind
    /// the page either.
    private func allowed(_ entry: LibraryEntry) -> Bool {
        guard blursPrivate, let library = entry.item.libraryId else { return true }
        return app?.privateLibraryIds.contains(library) != true
    }

    var body: some View {
        let shows = followsHover && homeBackdrop
        ZStack {
            if shows, let entry = HomeAmbient.shared.entry, allowed(entry) {
                RemoteImage(
                    request: .backdrop(for: entry, serverURL: serverURL, width: 960, scale: scale,
                                       preferSeriesThumb: true),
                    pipeline: pipeline
                )
                .scaledToFill()
                .blur(radius: 40, opaque: true)
                .overlay(Theme.Palette.canvas.opacity(0.72))
                .id(entry.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: HomeAmbient.shared.entry?.id)
        .onDisappear { HomeAmbient.shared.clear() }
    }
}
