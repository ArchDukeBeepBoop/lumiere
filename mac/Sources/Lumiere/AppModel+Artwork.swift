import Foundation
import LumiereKit
import LumierePlayer

/// Metadata refresh and the two artwork passes: the offline prefetch, and the
/// automatic poster fetch that fills gaps or replaces everything.
///
/// Split out of AppModel.swift, which is well past the project's 300-line limit.
extension AppModel {
    // MARK: - Metadata

    /// Asks the server to re-scrape an item, then re-syncs the row so the change
    /// shows up here without waiting for the next full sync.
    func refreshMetadata(itemId: String, replaceEverything: Bool) async {
        guard let client, let repository else { return }
        // Refused here rather than attempted and failed. Every scrape happens on the
        // *server* — that is the whole design, and why no API key lives in this app
        // — so with the server away there is nothing to ask, and the three-second
        // wait below would be ceremony around a request that never left the machine.
        guard !isOffline else { return refuseOffline("Refreshing metadata") }
        // Marked before the request, cleared however it ends. See
        // `refreshingItemIds`.
        refreshingItemIds.insert(itemId)
        defer { refreshingItemIds.remove(itemId) }
        do {
            try await client.refreshMetadata(
                itemId: itemId,
                replaceAllMetadata: replaceEverything,
                replaceAllImages: replaceEverything
            )
            // The server scrapes asynchronously, so there is nothing to read back
            // immediately. A short wait then a targeted refresh is the difference
            // between the new poster appearing and the user thinking it did nothing.
            try? await Task.sleep(for: .seconds(3))
            try await repository.refreshItem(itemId: itemId)
            // The shelves are showing the old title and the old poster. See
            // `AppModel.contentDidChange`.
            await contentDidChange("after metadata refresh")
            // Said out loud as well as shown on the tile: the shelf you were
            // looking at may have scrolled, or the change may be one — a
            // corrected synopsis — that a poster cannot show.
            let name = try? await repository.entry(id: itemId)?.item.name
            report("\((name ?? "Metadata")) updated")
            Diagnostics.log("[metadata] refreshed \(itemId)")
        } catch {
            Diagnostics.log("[metadata] refresh failed for \(itemId): \(error)")
            // A scrape is one of the longest requests this app makes, so it is often
            // the first thing to notice a server that went away mid-session. Offered
            // to the connection state rather than swallowed; it only counts if it
            // was a transport failure.
            noteRequestFailure(error)
        }
    }

    /// Stars or unstars anything, from any grid or shelf.
    ///
    /// Server-backed through the repository, which writes the local row first and
    /// rolls it back if the request fails — so the star answers the click rather
    /// than the round trip, and never lies about the outcome.
    @discardableResult
    func toggleFavourite(itemId: String, isFavourite: Bool) async -> Bool {
        guard let repository else { return false }
        // A star is a fact about the *account*, not about this Mac, so writing one
        // offline would either be lost or have to be replayed later — and a queue of
        // pending writes is a much larger promise than this feature makes. Saying so
        // is more honest than an optimistic star that silently rolls back a moment
        // later, which is what happened before.
        guard !isOffline else {
            refuseOffline("Changing favourites")
            return false
        }
        let changed = await repository.setFavorite(itemId: itemId, favorite: !isFavourite)
        if changed { await contentDidChange("after favourite") }
        return changed
    }

    // MARK: - Artwork prefetch

    /// Warms every poster in the cache so browsing works with the server off.
    func prefetchArtwork(widths: [CGFloat], scale: CGFloat) async {
        guard let prefetcher, let repository else { return }
        // The irony is worth naming: this is the pass that *makes* offline browsing
        // look right, and it is the one thing here that cannot run offline — every
        // poster it warms is fetched from the server. Started with the server away
        // it would grind through thousands of failing requests and warm nothing.
        guard !isOffline else { return refuseOffline("Caching artwork") }
        let targets = (try? await repository.artworkTargets()) ?? []
        guard !targets.isEmpty else { return }
        let cursor = try? await repository.prefetchCursor()
        Diagnostics.log("[prefetch] \(targets.count) items, cursor \(cursor ?? "none")")

        await prefetcher.run(
            targets: targets, widths: widths,
            aspectRatio: 2.0 / 3.0, screenScale: scale,
            // Below the cache's own 4 GB ceiling, so a completed prefetch is not
            // immediately evicting itself. See `ImagePipeline.init` for the
            // measurement this comes from.
            byteBudget: 3_500_000_000,
            resumeAfter: cursor,
            onProgress: { progress in
                Task { @MainActor in
                    self.prefetchProgress = progress.done < progress.total ? progress : nil
                    // Clearing the cursor on completion means the next run starts over
                    // rather than believing it has nothing to do — new items arrive.
                    if progress.done >= progress.total {
                        try? await self.repository?.setPrefetchCursor(nil)
                    }
                }
            },
            onItemComplete: { itemId in
                Task { @MainActor in
                    try? await self.repository?.setPrefetchCursor(itemId)
                }
            }
        )
    }

    func cancelPrefetch() async {
        await prefetcher?.cancel()
        prefetchProgress = nil
    }

    // MARK: - Automatic artwork

    /// Pulls posters from the server's providers, so the gap does not have to be
    /// closed one right-click at a time.
    ///
    /// `missingOnly: false` re-fetches everything, for when what is already there is
    /// wrong rather than absent — a library matched to the wrong titles ends up with
    /// plausible but incorrect artwork, which no "missing" pass would ever revisit.
    func fetchArtwork(missingOnly: Bool = true) async {
        guard let client, let repository, artworkFetcher == nil else { return }
        // Same reason as the prefetch above: the posters come from the server's
        // providers, so with the server away this is a progress bar over nothing.
        guard !isOffline else { return refuseOffline("Fetching artwork") }
        let missing = (try? await repository.artworkFetchTargets(missingOnly: missingOnly)) ?? []
        guard !missing.isEmpty else {
            artworkFetchProgress = nil
            return
        }
        Diagnostics.log(
            "[artwork] \(missing.count) items (\(missingOnly ? "missing only" : "replace all"))"
        )

        let fetcher = ArtworkAutoFetcher(client: client)
        artworkFetcher = fetcher
        await fetcher.run(
            items: missing,
            onProgress: { progress in
                Task { @MainActor in
                    self.artworkFetchProgress =
                        progress.done < progress.total ? progress : nil
                    if progress.done >= progress.total { self.artworkFetcher = nil }
                }
            },
            // Re-read the row so the new tag lands in the cache and the grid redraws
            // without waiting for the next full sync.
            onItemUpdated: { itemId in
                Task { @MainActor in
                    try? await self.repository?.refreshItem(itemId: itemId)
                }
            }
        )
    }

    func cancelArtworkFetch() async {
        await artworkFetcher?.cancel()
        artworkFetcher = nil
        artworkFetchProgress = nil
    }

    /// Cheap refresh for when the window regains focus — watch state only, since
    /// that is what changes when you watch something on another device.
    func refreshWatchState() async {
        guard let repository, !isOffline else { return }
        do {
            try await repository.refreshWatchState()
            // A cheap request that just succeeded is proof the server is up, and
            // this one runs on every window focus. It is the fastest route back
            // online when the app has been sitting offline and the user returns to
            // it — faster than waiting out the probe's backoff.
            if connection == .unknown { connection = .online }
        } catch {
            // Was `try?`, which is how a server that went away mid-session stayed
            // invisible until the next sync: this runs on focus, so it is usually
            // the first request to fail.
            noteRequestFailure(error)
        }
    }
}
