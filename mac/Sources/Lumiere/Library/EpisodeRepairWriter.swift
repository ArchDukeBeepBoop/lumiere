import Foundation
import LumiereKit

/// Writes rebuilt episode numbering to the server.
///
/// One implementation for both callers — the single-series sheet and the
/// library-wide sweep — because the risky part is identical and must not drift:
/// what gets locked, whether thumbnails are replaced, and the fact that it is
/// serial.
///
/// Serial on purpose. A sweep is hundreds of writes plus hundreds of image
/// extractions against a machine that is probably also streaming something, and
/// firing them in parallel is how a media server becomes unresponsive mid-repair.
/// It also means a failure stops at a known point rather than halfway through an
/// unknown subset.
struct EpisodeRepairWriter {
    let client: JellyfinClient
    let repository: LibraryRepository
    /// Whether to replace each episode's thumbnail with a frame from its own file.
    /// The expensive half: renumbering is one small request per episode, a
    /// thumbnail is a tile sheet fetched, cropped and uploaded.
    var refreshesThumbnails: Bool
    /// Runtimes, so the frame can be taken a fifth of the way in rather than at
    /// zero. Missing runtimes still work; they just take the opening frame.
    var runtimes: [String: Double] = [:]

    enum Outcome {
        case done
        case failed(String)
    }

    /// Applies one episode. Returns nil on success, or why it stopped.
    func apply(_ proposal: FilenameEpisodeRepair.Proposal) async -> Outcome {
        do {
            // The thumbnail first, so the write that follows can carry the freeze.
            //
            // A frame out of this file, not a scrape: asking the server to refresh
            // images gives back the *same* still for every episode of a merged
            // series, because the listing the scraper matched has one still and all
            // sixteen files were told they were that episode.
            //
            // Failing here is not failing the repair. The numbering is the point; a
            // server with no trickplay data still gets its episodes put right, and
            // the thumbnails stay as they were.
            var thumbnailLanded = false
            if refreshesThumbnails {
                do {
                    try await GeneratedThumbnail.apply(
                        itemId: proposal.id,
                        runtimeSeconds: runtimes[proposal.id],
                        client: client,
                        // Folded into the edit below instead: one write per episode
                        // rather than two, across a sweep of several hundred.
                        locksItem: false
                    )
                    thumbnailLanded = true
                } catch {
                    Diagnostics.log("[repair] thumbnail for \(proposal.id): \(error)")
                }
            }

            try await client.updateItem(
                itemId: proposal.id,
                edit: ItemEdit(
                    name: proposal.title,
                    // No sort name. With the season and episode numbers now right,
                    // Jellyfin orders episodes by them without help — and writing
                    // one would have put a Lumiere-internal numeric key ("00010004")
                    // into ForcedSortName, a permanent server-side field visible to
                    // every other client.
                    episodeNumber: proposal.episode,
                    seasonNumber: proposal.season,
                    // Without the lock this undoes itself. The scraper that merged
                    // these arcs is still configured, still scheduled, and still
                    // confident it was right.
                    lockedFields: [.name],
                    // Only where a frame actually replaced the still. LockData is
                    // the only image lock Jellyfin has and it freezes the whole
                    // item, so an episode whose thumbnail never arrived must not
                    // pay for one — on a server without trickplay that would be
                    // every episode in the sweep.
                    lockAll: thumbnailLanded
                )
            )
            return .done
        } catch JellyfinError.unauthorized {
            return .failed(
                "Your account cannot edit items. Renumbering episodes needs "
                + "an administrator account on the server."
            )
        } catch {
            return .failed(ConnectionState.message(for: error))
        }
    }

    /// Re-reads the written items so the cache stops showing the old numbering.
    ///
    /// Without this the episode list would show the repair as having done nothing
    /// until the next full sync — which, on a library this size, is the difference
    /// between "it worked" and "it silently failed".
    func refreshCache(ids: [String]) async {
        for id in ids {
            try? await repository.refreshItem(itemId: id)
        }
    }
}
