import Foundation
import LumiereKit

/// Which libraries stay out of sight, and whether they are showing right now.
///
/// Two separate things, deliberately. *Which* libraries are private is a settled
/// preference and persists; *whether* they are on screen is a decision about this
/// moment and does not. So the app opens with them hidden every single time, and
/// revealing them is a thing you do rather than a thing you forget you did.
///
/// What this is, said plainly: it stops your library appearing behind your
/// shoulder — on the home screen, in Continue Watching, in a search for an
/// unrelated word, in the spotlight. It is not a security boundary. There is no
/// password on it, the files are exactly where they were, and anyone with access
/// to this Mac can read them. Claiming otherwise would be the more harmful lie.
@MainActor
extension AppModel {

    static let privateLibrariesKey = "privateLibraryIds"

    var privateLibraryIds: Set<String> {
        get {
            Set((UserDefaults.standard.string(forKey: Self.privateLibrariesKey) ?? "")
                .split(separator: ",").map(String.init))
        }
        set {
            UserDefaults.standard.set(
                newValue.sorted().joined(separator: ","), forKey: Self.privateLibrariesKey
            )
            Task { await applyPrivacy() }
        }
    }

    /// Libraries to draw in the sidebar and on the home screen.
    ///
    /// The list itself, not only its contents: a row reading "Adult" is the thing
    /// being hidden as much as anything inside it.
    var visibleLibraries: [LibraryRecord] {
        let hidden = privateLibraryIds
        // In the room, only its own libraries; outside, everything else.
        guard !isShowingPrivateLibraries else { return libraries.filter { hidden.contains($0.id) } }
        return libraries.filter { !hidden.contains($0.id) }
    }

    var hasPrivateLibraries: Bool { !privateLibraryIds.isEmpty }

    /// Pushes the current state down to the repository, which is where every
    /// cross-library query applies it.
    ///
    /// Revealing empties the set rather than setting a flag the queries would each
    /// have to check — one mechanism, and no second place for it to be forgotten.
    func applyPrivacy() async {
        await repository?.setPrivateLibraryIds(
            isShowingPrivateLibraries ? [] : privateLibraryIds
        )
        await repository?.setRoomLibraryIds(isShowingPrivateLibraries ? privateLibraryIds : [])
        // The full set, not the currently-hidden one. The Top 10 rows exclude a
        // private library whether or not it is on screen: revealing one means "let
        // me browse it", never "rank it on my home screen". Pushed here as well as
        // at attach, because ticking a library in Settings changes this mid-session
        // and nothing else would tell the shelves.
        homeModel?.privateLibraryIds = privateLibraryIds
        await client?.setPrivateLibraries(privateLibraryIds)
        await client?.setLookupSkipped(Preference.looksUpPrivateLibraries.value ? [] : privateLibraryIds)
        await homeModel?.refresh("after privacy change")
    }

    func setShowingPrivateLibraries(_ showing: Bool) async {
        isShowingPrivateLibraries = showing
        await applyPrivacy()
        // The home screen is built from queries that have just changed their
        // answers, and nothing else would tell it.
        await loadCachedLibraries()
        homeReloadToken &+= 1
    }
}
