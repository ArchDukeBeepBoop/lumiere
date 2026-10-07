import Foundation

public extension LibraryEntry {
    /// Whether this counts as watched, for a menu that has to name its own command.
    ///
    /// One definition rather than one per surface, because the label is the command:
    /// a menu that says "Mark as Watched" over something already watched is a menu
    /// that does nothing when clicked. `PosterCard.isUnwatched` asks the same
    /// question for the corner badge and answers it the same way — a film is its own
    /// `played` flag, a show is whether anything under it is still unplayed — and the
    /// two must agree or a tile will carry an unwatched corner over a "Mark as
    /// Unwatched" command.
    ///
    /// Deliberately not `!isUnwatched`: an item part-way through is neither, and this
    /// side of the question wants "has it been marked watched", which a resume
    /// position is not.
    var isPlayed: Bool {
        switch item.itemType {
        case .series, .season:
            // A show with no counts reported falls back to its own flag, which
            // Jellyfin does set on a fully-watched series.
            if let unplayed = userData?.unplayedItemCount { return unplayed == 0 }
            return userData?.played == true
        default:
            return userData?.played == true
        }
    }

    /// Whether a tile draws the unwatched marker. The one rule every card
    /// and thumbnail uses — they each had their own copy, and copies of a
    /// watched rule are how a season came to disagree with its episodes.
    ///
    /// A film or episode: not watched and not started (a started one shows a
    /// progress bar instead). A show or season: episodes left. Anything else —
    /// a folder, a library — has no watched state to mark.
    var showsUnwatchedMarker: Bool {
        switch item.itemType {
        case .movie, .episode, .video:
            return !isPlayed && progress == nil
        case .series, .season, .boxSet:
            return (userData?.unplayedItemCount ?? 0) > 0
        default:
            return false
        }
    }

    /// Where playback should start: the resume position, or the beginning.
    ///
    /// Not `userData.resumeSeconds`, which is the raw number and says nothing about
    /// whether resuming there makes sense. Two cases where it does not, and both put
    /// you at a black frame with `-0:00` on the scrubber:
    ///
    /// - The item is **watched**. Finishing an episode reports the final position,
    ///   and nothing zeroes the cached ticks; going back to it afterwards resumed at
    ///   the end. This is the one that made "going back to a watched episode display
    ///   nothing" — the player was working exactly as told.
    /// - The position is inside the last few seconds. A file abandoned during the
    ///   credits is finished in every sense that matters, and resuming there gives
    ///   you a fade to black.
    ///
    /// `LibraryEntry` rather than `UserDataRecord` because the second rule needs the
    /// runtime, which lives on the item.
    var resumeStart: Double {
        guard let userData, userData.played == false else { return 0 }
        let seconds = userData.resumeSeconds
        guard seconds > 0 else { return 0 }
        if let runtime = item.runtimeSeconds, runtime > 0, seconds > runtime - 10 {
            return 0
        }
        return seconds
    }

    /// Whether this is finished for the purposes of Continue Watching.
    ///
    /// The played flag is not enough. A player that stops on the last frame
    /// reports that position and nothing marks the row watched, so an episode
    /// watched to the end sits at 99.99% and stays on the shelf for good — which
    /// is what "watched episodes still show up in Continue Watching" is.
    ///
    /// 90% is Jellyfin's own MaxResumePct, and the server's Resume query cuts at
    /// the same number. The two have to agree: this list is drawn from the cache
    /// and refreshed from the server, and a row that one includes and the other
    /// does not appears and disappears as the network comes and goes.
    ///
    /// An unknown runtime is not finished — it cannot be a percentage of
    /// anything, and dropping what cannot be measured loses rows silently.
    var isFinishedForResume: Bool {
        if userData?.played == true { return true }
        guard let runtime = item.runtimeSeconds, runtime > 0 else { return false }
        guard let seconds = userData?.resumeSeconds, seconds > 0 else { return false }
        return seconds >= runtime * Self.resumeCutoff
    }

    /// The fraction of a file past which it counts as watched.
    static var resumeCutoff: Double { 0.90 }

    /// Whether marking this watched or unwatched means anything.
    ///
    /// Excludes the containers Jellyfin has no watch state for. A person, a genre
    /// or a plain folder has no played flag, and offering the command over one is a
    /// menu item that reports success and changes nothing.
    var supportsWatchState: Bool {
        switch item.itemType {
        case .movie, .episode, .video, .series, .season, .boxSet, .audio, .musicAlbum:
            return true
        // Plain folders included, and only plain ones. In a folder-browsed library a
        // folder *is* the unit — it is how a series' worth of loose files is
        // organised — and Jellyfin marks a folder's children played along with it.
        // The batch bar has always allowed this; the right-click menu should not
        // disagree with the toolbar over the same tile. `collectionFolder` and
        // `userView` are libraries, not content, and stay out.
        case .folder:
            return true
        default:
            return false
        }
    }
}
