import Foundation
import LumiereKit

/// Running the library sync, and deciding what its outcome means.
///
/// Split from AppModel.swift for the project's 300-line limit. The judgement worth
/// keeping in one place is the last part: a library that missed a page is not an
/// unreachable server, and conflating the two is what put an outage banner over a
/// sync that had very nearly finished.
extension AppModel {

    /// How far through a running pass we are. Declared here rather than in
    /// AppModel.swift, which is at its line limit, and because the loop below is the
    /// only thing that ever constructs one.
    struct SyncProgress: Equatable {
        var libraryName: String
        var synced: Int
        var total: Int
        /// Where this library sits in the pass, 1-based, and how many libraries the
        /// pass was asked to read. Both are needed: "Anime" on its own does not say
        /// whether three libraries are still queued behind it or none.
        var libraryIndex: Int = 1
        var libraryCount: Int = 1
        /// Whether this is the pass that can remove titles whose files are gone.
        /// Worth showing while it runs — it is the difference between a scan worth
        /// waiting for and one that is nearly free.
        var isFullScan: Bool = false

        var fraction: Double {
            total > 0 ? Double(synced) / Double(total) : 0
        }
    }

    /// What the last completed pass did.
    ///
    /// Kept apart from `lastPartialLibraries` because that one is a warning and this
    /// is a receipt. `removed` in particular is the only visible evidence that a full
    /// scan noticed the files deleted or renamed on disk — which is the complaint
    /// this whole panel exists to answer.
    struct SyncSummary: Equatable {
        var libraries: Int
        var seen: Int
        var removed: Int
        var wasFullScan: Bool
    }

    /// Records a change to the selection. The one place it is written, so nothing
    /// can change the selection without also persisting it.
    func updateSyncSelection(_ change: (inout SyncSelection) -> Void) {
        change(&syncSelection)
        syncSelection.save()
    }

    /// The panel's Scan button.
    ///
    /// Not a second sync path: it checks the two things a button press can be wrong
    /// about — the server being away, and nothing being ticked — and then goes
    /// through `startSync` like everything else. Both refusals are said out loud,
    /// because a button that does nothing when pressed is the worst of the options.
    func syncEverything(forceFull: Bool = false) async {
        guard let repository else {
            Diagnostics.log("[sync] no repository — sync skipped")
            return
        }

        do {
            let fromServer = try await repository.syncLibraries()
            // Re-read rather than using what the server returned. Folders added
            // from this Mac are libraries too, and taking the server's list
            // verbatim made every one of them disappear from the sidebar the
            // moment a sync ran.
            libraries = inHomeOrder((try? await repository.libraries()) ?? fromServer)
            Diagnostics.log("[sync] server returned \(fromServer.count) libraries")
        } catch is CancellationError {
            syncProgress = nil
            return
        } catch {
            // Only the library *list* failing is fatal to a sync — without it there
            // is nothing to iterate.
            Diagnostics.log("[sync] library list FAILED: \(error)")
            syncProgress = nil
            let message = Connection.message(for: error)
            if libraries.isEmpty { startupError = message }
            // Probed only when the failure was actually a transport one. A server
            // answering 401 is up, so a probe would resolve immediately, start a
            // sync, and fail the same way — a slow loop rather than a recovery.
            goOffline(message, probing: Connection.isUnreachable(error))
            return
        }

        // Each library is isolated. One library failing used to abort the loop and
        // every library after it went unsynced — on a large collection the first one
        // timed out and nothing else was ever fetched.
        //
        // Which libraries are read is now `SyncSelection`'s answer, and it still
        // skips music and playlist libraries whatever is ticked: syncing them
        // recursively pulls in every track, which is unbounded work and unbounded
        // cache for a video player that cannot play one of them.
        var failures: [String] = []
        var partial: [String] = []
        /// Whether any library failed because the server went away mid-sync, as
        /// opposed to failing on its own merits. Only the first case is worth
        /// watching for a recovery; a library that throws for its own reasons will
        /// keep throwing however many times the server is asked.
        var sawUnreachable = false
        var seenTotal = 0
        var removedTotal = 0

        // The owner's choice, applied to every pass rather than only to the ones he
        // starts by hand. A library he has unticked should not come back at launch —
        // that would make the setting look broken in the one case nobody is watching.
        // Asked once, before the loop. Only lumiered answers; Jellyfin has no
        // such endpoint and the nil is what the rule below expects of it.
        let repairedAt = (try? await client?.serverScanStatus())?.RepairedAt

        var selected = syncSelection.libraries(from: libraries)
        // An unticked library is still shown — its shelves, its folders — from
        // whatever the cache last read. When the server has since rewritten
        // rows it holds, what is shown is wrong, and "do not re-read this at
        // launch" was never a request to keep showing it wrong. One full read,
        // and it drops back out of the pass.
        for library in libraries
        where !syncSelection.includes(library.id) && library.holdsPlayableVideo
            && library.serverId != LocalLibrary.serverId {
            let lastFull = try? await repository.lastFullSync(libraryId: library.id)
            if SyncTrigger.repairedSince(lastFull: lastFull, repairedAt: repairedAt) {
                Diagnostics.log("[sync] \(library.name) is unticked but the server repaired rows — reading it once")
                selected.append(library)
            }
        }
        guard !selected.isEmpty else {
            // The library list loaded, so the server is up and saying so is honest —
            // otherwise unticking everything would strand the app in `.unknown` with
            // no way back. What is *not* honest is claiming a sync completed, so no
            // summary is recorded and the panel keeps showing the last real one.
            // `reconnectAttempts` is deliberately left alone: only a pass that
            // actually read every selected library earns a reset of the backoff.
            Diagnostics.log("[sync] no libraries selected — nothing to read")
            syncProgress = nil
            connection = .online
            return
        }

        await previewUnreadLibraries(selected)
        for (index, library) in selected.enumerated() {
            Diagnostics.log("[sync] starting \(library.name)")
            syncProgress = SyncProgress(
                libraryName: library.name, synced: 0, total: 0,
                libraryIndex: index + 1, libraryCount: selected.count,
                isFullScan: forceFull
            )
            do {
                // Incremental unless asked for a full scan or one is overdue. On a
                // 44,000-item library this is the difference between two hundred
                // requests and one or two: new episodes sort to the top of a
                // DateCreated list, so the pass stops as soon as it recognises
                // everything on a page.
                let lastFull = try? await repository.lastFullSync(libraryId: library.id)
                let overdue = lastFull.map {
                    Date().timeIntervalSince($0) > Self.fullScanInterval
                } ?? true
                // A folder library that has never collected its merged files needs
                // one full pass to do it: an incremental one stops at the first
                // recognised page and would never re-read the items that hold them.
                // See `LibraryRepository.needsVersionBackfill`.
                let owesVersions = await repository.needsVersionBackfill(
                    libraryId: library.id
                )
                // The server rewrote rows this client already holds — a folder
                // of clips it had filed as films, say — since the last full
                // read. New ids alone would never show that.
                let repaired = SyncTrigger.repairedSince(lastFull: lastFull, repairedAt: repairedAt)
                if repaired { Diagnostics.log("[sync] \(library.name) full — server repaired rows") }
                let isFull = forceFull || overdue || owesVersions || repaired
                let mode: LibraryRepository.SyncMode = isFull ? .full : .incremental

                // Captured, not re-read in the callback: it runs every page, and "2 of 4"
                // must name the library being read, not wherever the loop has moved on to.
                let libraryStarted = Date()
                let position = index + 1
                let count = selected.count
                let report = try await repository.syncLibrary(
                    id: library.id, mode: mode
                ) { synced, total in
                    Task { @MainActor in
                        self.syncProgress = SyncProgress(
                            libraryName: library.name, synced: synced, total: total,
                            libraryIndex: position, libraryCount: count,
                            isFullScan: isFull
                        )
                    }
                }
                if report.outcome == .partial { partial.append(library.name) }
                seenTotal += report.seen
                removedTotal += report.removed
                Diagnostics.log(
                    "[sync] finished \(library.name) — \(report.outcome) \(isFull ? "full" : "incremental"), "
                    + "\(report.seen) seen, \(report.removed) removed, \(Int(Date().timeIntervalSince(libraryStarted)))s"
                )
                // Per library, but only when the library actually changed.
                //
                // It was unconditional, and instrumenting it showed what that cost:
                // nine full re-reads in one pass, 1.7s each climbing to 5.3s as they
                // contended with the sync's own writes — about 25 seconds of query
                // work, and every one of them produced identical counts because an
                // up-to-date library has nothing new to show. `upToDate` means the
                // incremental pass reached rows it had already seen and stopped, so
                // there is nothing on the home screen that could have moved.
                //
                // The unconditional refresh at the end of the pass stays, and it is
                // what covers watch state changed on another device — that does not
                // show up as a changed row here.
                // What was written, not how the pass ended. `upToDate` means the
                // last few pages were familiar and it stopped — pages before
                // them may have carried new rows, and did: three shows arrived
                // in Anime under a report that said nothing had changed, so the
                // grid kept yesterday's answer.
                if report.wroteSomething || report.removed > 0 {
                    await homeModel?.refresh("after \(library.name) synced")
                    // And every other page showing this library.
                    //
                    // The home screen was the only surface a sync ever told.
                    // Standing in Anime while a sync brought three new shows in,
                    // the grid kept last visit's answer until it was left and
                    // reopened — which is the one moment somebody is watching
                    // for the thing they just asked for. Named by library, so a
                    // pass over Movies does not reload a folder wall in 3D.
                    LibraryChangeFeed.shared.note(
                        "library synced", libraryId: library.id
                    )
                    // Logged because a broadcast returns nothing, and "did the page
                    // hear about it" is the hard question every time this breaks.
                    Diagnostics.log("[sync] announced \(library.name) to open pages")
                }
            } catch is CancellationError {
                syncProgress = nil
                Diagnostics.log("[sync] cancelled during \(library.name)")
                return
            } catch {
                Diagnostics.log("[sync] \(library.name) FAILED: \(error)")
                failures.append(library.name)
                if Connection.isUnreachable(error) { sawUnreachable = true }
            }
        }

        syncProgress = nil
        lastPartialLibraries = partial
        lastSyncFinished = Date()
        // Tells the home screen its shelves are stale. It reloads when the *library
        // list* changes, and a sync that adds episodes to libraries you already have
        // does not change that list — so a finished sync left the shelves as they
        // were at launch until you navigated away and back, which rebuilt the view.
        // Unconditional: `seen` counts rows read, not rows changed, so there is no
        // cheaper "something differs" signal, and a sync is not a scroll-time event.
        homeReloadToken &+= 1
        // And once more at the end, for the libraries whose shelves changed because
        // of a *later* library's rows — Next Up crosses them, and so does the
        // spotlight.
        await homeModel?.refresh("after sync")
        lastSyncSummary = SyncSummary(
            libraries: selected.count - failures.count,
            seen: seenTotal,
            removed: removedTotal,
            // Only a pass that was asked for a full read of everything can claim to
            // be one. A routine pass where a single overdue library happened to go
            // full is not what the panel means by "full scan".
            wasFullScan: forceFull
        )
        if failures.isEmpty {
            // Partial libraries included. The server answered, everything read is
            // cached, and nothing was deleted — putting an outage banner over that
            // is what interrupted a sync that was very nearly complete. It is
            // reported in the sync panel instead, where it belongs.
            connection = .online
            startupError = nil
            // A sync that got through by other means — a manual Refresh Library —
            // has answered the probe's question, so the probe has no reason to keep
            // running. Harmless if none is: it is a nil check.
            cancelReconnectWatch()
            // Only here. A sync that reached every library is the only evidence the
            // server is properly back, so it is the only thing that earns a reset of
            // the backoff — a server answering the cheap probe and then failing
            // every page must keep widening rather than start over at five seconds.
            reconnectAttempts = 0
            Diagnostics.log(
                partial.isEmpty
                    ? "[sync] all libraries complete"
                    : "[sync] complete, partial: \(partial)"
            )
        } else {
            // Partly synced is worth saying out loud: what is cached is browsable,
            // but it is not the whole library and silence would imply it was.
            let message = failures.count == 1
                ? "\(failures[0]) didn't finish syncing."
                : "\(failures.count) libraries didn't finish syncing: \(failures.joined(separator: ", "))."
            Diagnostics.log("[sync] complete with failures: \(failures)")
            goOffline(message, probing: sawUnreachable)
        }
    }
}
