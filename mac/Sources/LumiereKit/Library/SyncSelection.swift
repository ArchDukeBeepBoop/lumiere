import Foundation

/// Which libraries a sync reads, and how deeply.
///
/// This lives in the kit rather than in the view for one reason: deciding *which*
/// libraries a pass touches is the same class of decision as deciding what a sync
/// outcome means, and it is worth pinning with tests. A checkbox list that quietly
/// resolves to "no libraries" — or, worse, to "every library including music" — is
/// not something a screenshot would catch.
public struct SyncSelection: Sendable, Equatable {

    /// How much of a library to read, worded the way the panel words it.
    ///
    /// Deliberately not the same type as `LibraryRepository.SyncMode`: that one
    /// describes a single library's read strategy, this one is a stored preference
    /// about what the person pressing the button wants. Keeping them apart means
    /// the repository stays free to add modes the panel does not offer, and the
    /// stored value never has to survive a change to the repository's enum.
    public enum Depth: String, Sendable, CaseIterable {
        /// Newest-first, stops early. Finds new items; cannot notice a removal.
        case quick
        /// Reads the whole library and then sweeps. The only pass that can remove
        /// titles whose files are gone from the server.
        case full
    }

    public var depth: Depth

    /// Libraries the user has turned *off*, rather than the ones left on.
    ///
    /// Storing the exclusions is what makes a library added on the server later
    /// behave sensibly: it is not in the set, so it is scanned. Storing inclusions
    /// would mean a new library silently never syncs until someone happens to open
    /// this panel and tick it, which is the same class of bug as the stale rows
    /// this panel exists to fix.
    public var excludedLibraryIds: Set<String>

    public init(depth: Depth = .quick, excludedLibraryIds: Set<String> = []) {
        self.depth = depth
        self.excludedLibraryIds = excludedLibraryIds
    }

    /// Whether this library would be read by the next sync.
    public func includes(_ libraryId: String) -> Bool {
        !excludedLibraryIds.contains(libraryId)
    }

    public mutating func setIncluded(_ included: Bool, for libraryId: String) {
        if included {
            excludedLibraryIds.remove(libraryId)
        } else {
            excludedLibraryIds.insert(libraryId)
        }
    }

    /// The libraries a pass should actually walk, in the server's own order.
    ///
    /// `holdsPlayableVideo` is applied here as well as in the panel, and that is not
    /// belt-and-braces: the sync loop reads this, and a music library reaching it
    /// would recurse into every track — unbounded work and unbounded cache for a
    /// video player that cannot play one of them. The rule stays true even if some
    /// future caller forgets to filter first.
    /// Folders on this Mac are excluded here rather than at every call site.
    ///
    /// They are libraries in every sense the UI cares about — sidebar, home cards,
    /// browsing, playback — but there is nothing to sync: their contents come from
    /// a directory walk, not from a server. Offering one in the scan list would be
    /// a tick box that does nothing, and running a sync over one would ask Jellyfin
    /// about ids it has never heard of.
    public func libraries(from all: [LibraryRecord]) -> [LibraryRecord] {
        all.filter {
            $0.serverId != LocalLibrary.serverId && $0.holdsPlayableVideo && includes($0.id)
        }
    }

    // MARK: - Persistence

    /// The defaults keys. Namespaced so they read as sync's own, and stable —
    /// renaming one silently resets everyone's choices back to "scan everything".
    private static let depthKey = "sync.depth"
    private static let excludedKey = "sync.excludedLibraryIds"

    /// Reads the stored choice, falling back to "everything, quickly".
    ///
    /// The fallback matters more than it looks: it is what a first run gets, and it
    /// has to match the behaviour the app had before this panel existed — every
    /// video library, incremental, with a full pass forced on a schedule.
    public static func load(from defaults: UserDefaults = .standard) -> SyncSelection {
        let depth = (defaults.string(forKey: depthKey).flatMap(Depth.init(rawValue:))) ?? .quick
        let excluded = defaults.stringArray(forKey: excludedKey) ?? []
        return SyncSelection(depth: depth, excludedLibraryIds: Set(excluded))
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(depth.rawValue, forKey: Self.depthKey)
        // Sorted so the stored value is stable between writes. A Set's iteration
        // order is not, and an unstable plist value makes any diff of the defaults
        // file — the usual way to check what the app actually remembered — useless.
        defaults.set(excludedLibraryIds.sorted(), forKey: Self.excludedKey)
    }
}
