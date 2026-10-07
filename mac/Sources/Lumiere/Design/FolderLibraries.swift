import SwiftUI
import LumiereKit

/// Which libraries are plain folders rather than scraped collections.
///
/// It changes what a `Primary` image *is*. In a Movies library the Primary is a
/// scraped 2:3 poster, and forcing one into a 16:9 card upscales it past its own
/// width and crops it through the middle — sharp source, blurry result, which is
/// why `ImageRequest.backdrop` refuses to reach for it. In a folder library there is
/// no scraper: Jellyfin's Primary for a loose file is a frame grab off the video
/// itself, already 16:9, and refusing it means the wide card falls through to
/// `GeneratedThumb` and draws the filename on a coloured plate while a perfectly
/// good still of the file sits on the server.
///
/// That is what happened to Continue Watching for `My Videos` and `3D`: those rows
/// are `Movie`, not `Episode`, so the one exception the rule already had did not
/// cover them.
///
/// Carried in the environment rather than looked up per card, because the answer
/// belongs to the *library* and a card only knows its item.
private struct FolderLibraryIdsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var folderLibraryIds: Set<String> {
        get { self[FolderLibraryIdsKey.self] }
        set { self[FolderLibraryIdsKey.self] = newValue }
    }
}

/// Which libraries are anime, for the metadata line.
///
/// Beside the folder ids and for the same reason: the question belongs to the
/// *library* and a card only knows its item. The classification itself is
/// `LibraryKinds.isAnime`, which the Top 10 rows already use — one answer, not
/// two that can disagree.
private struct AnimeLibraryIdsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var animeLibraryIds: Set<String> {
        get { self[AnimeLibraryIdsKey.self] }
        set { self[AnimeLibraryIdsKey.self] = newValue }
    }
}

/// Which libraries show only the show's artwork on wide cards. See
/// `DiscreetArtPolicy`.
private struct DiscreetArtLibraryIdsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var discreetArtLibraryIds: Set<String> {
        get { self[DiscreetArtLibraryIdsKey.self] }
        set { self[DiscreetArtLibraryIdsKey.self] = newValue }
    }
}

/// The private libraries, for cards that hold their covers back. See
/// `CoverHoldBack`.
private struct PrivateLibraryIdsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var privateLibraryIds: Set<String> {
        get { self[PrivateLibraryIdsKey.self] }
        set { self[PrivateLibraryIdsKey.self] = newValue }
    }
}

extension View {

    /// Publishes the folder libraries from the server's own list.
    ///
    /// A folder library is one Jellyfin gives no `collectionType` — it has not been
    /// told the folder is films or shows, so it neither scrapes it nor makes posters
    /// for it.
    func folderLibraries(_ libraries: [LibraryRecord]) -> some View {
        environment(
            \.folderLibraryIds,
            Set(libraries.filter { $0.collectionType == nil }.map(\.id))
        )
        .environment(
            \.animeLibraryIds,
            Set(libraries.filter { LibraryKinds.isAnime($0.name) }.map(\.id))
        )
        .environment(
            \.privateLibraryIds,
            Set((UserDefaults.standard.string(forKey: AppModel.privateLibrariesKey) ?? "")
                .split(separator: ",").map(String.init))
        )
        .environment(
            \.discreetArtLibraryIds,
            DiscreetArtPolicy.discreet(
                libraries: libraries,
                stored: UserDefaults.standard.string(forKey: DiscreetArtPolicy.storageKey)
            )
        )
    }
}
