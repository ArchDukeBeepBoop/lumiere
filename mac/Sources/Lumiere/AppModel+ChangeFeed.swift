import AppKit
import LumiereKit

/// Keeping the library current from the server's change feed.
///
/// One request held open: the server answers the moment anything is added,
/// changed or removed, with exactly those items, and the cache takes them in.
/// No periodic passes, no weekly full read, no Sync button to remember — the
/// way Photos keeps a library current. On a real Jellyfin, which has no feed,
/// the periodic sync and the change-marker check carry on as before.
@MainActor
extension AppModel {

    /// Held here rather than on `AppModel`, which is at the line budget.
    @MainActor enum Feed {
        static var task: Task<Void, Never>?
        /// The server answered the feed: periodic passes stand down.
        static var live = false
        static var wakeObserver: NSObjectProtocol?
    }

    var feedIsLive: Bool { Feed.live }

    private var feedTokenKey: String? {
        client.map { "changeToken.\($0.session.serverId)" }
    }

    private var feedToken: Int64 {
        get { feedTokenKey.flatMap { Int64(UserDefaults.standard.string(forKey: $0) ?? "") } ?? 0 }
        set { feedTokenKey.map { UserDefaults.standard.set(String(newValue), forKey: $0) } }
    }

    /// Launch: when the feed can bring the cache up to date, that is all the
    /// catching up needed — no pass over every library. Otherwise the sync
    /// as before. Either way, ends with the watchers running.
    func catchUpAtLaunch() async {
        var caughtUp = false
        if feedToken > 0, let client, let repository,
           let page = try? await client.changes(since: feedToken), !page.reset {
            _ = try? await repository.syncLibraries()
            libraries = inHomeOrder((try? await repository.libraries()) ?? libraries)
            caughtUp = await apply(page)
            if caughtUp {
                Diagnostics.log("[feed] caught up at launch from change \(page.next)")
                lastSyncFinished = Date()
                connection = .online
                await afterSync()
            }
        }
        if !caughtUp {
            // No usable token. On Lumiere's server, one full read earns one —
            // taken before the read begins, so nothing changed during it is
            // missed — and the feed carries on from there instead of reading
            // everything a second time. On Jellyfin, the sync as before.
            if let client, let start = try? await client.changes(since: 0) {
                let before = lastSyncFinished
                await runSync(full: true)
                if lastSyncFinished != before { feedToken = start.next }
            } else {
                await runSync()
            }
        }
        startAutoSync(); startChangeWatch(); startChangeFeed(); startDriftCheck()
    }

    /// Starts the feed. Safe to call more than once — the old loop is replaced.
    func startChangeFeed() {
        Feed.task?.cancel()
        Feed.task = Task { @MainActor [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, let client = self.client else { return }
                if self.isOffline {
                    try? await Task.sleep(for: .seconds(10))
                    continue
                }
                do {
                    let token = self.feedToken
                    let page = try await client.changes(since: token, wait: token > 0 ? 45 : 0)
                    failures = 0
                    Feed.live = true
                    if page.reset {
                        // No token, or one the server no longer recognises: one
                        // full read, then on from the token taken before it began.
                        let before = self.lastSyncFinished
                        await self.runSync(full: true)
                        guard self.lastSyncFinished != before else {
                            // Refused — a film is playing. Ask again shortly.
                            try? await Task.sleep(for: .seconds(60))
                            continue
                        }
                        self.feedToken = page.next
                    } else if await self.apply(page) {
                        self.lastSyncFinished = Date()
                    }
                    if !page.more { await self.feedPause() }
                } catch is CancellationError {
                    return
                } catch {
                    if case JellyfinError.httpError(let status, _) = error, status == 404 {
                        Diagnostics.log("[feed] this server has no change feed — periodic sync stays on")
                        Feed.live = false
                        return
                    }
                    failures += 1
                    _ = self.noteRequestFailure(error)
                    try? await Task.sleep(for: .seconds(min(60, 1 << min(failures, 6))))
                }
            }
        }
        watchForWake()
    }

    func cancelChangeFeed() {
        cancelDriftCheck()
        Feed.task?.cancel()
        Feed.task = nil
        Feed.live = false
    }

    /// Writes one page into the cache and moves the token on. False if it
    /// could not be written, so the same page is asked for again.
    private func apply(_ page: ChangePage) async -> Bool {
        guard let repository else { return false }
        if !page.changed.isEmpty || !page.removed.isEmpty {
            let wanted = Set(syncSelection.libraries(from: libraries).map(\.id))
            do {
                let result = try await repository.applyChanges(
                    changed: page.changed, removed: page.removed, libraryIds: wanted
                )
                Diagnostics.log("[feed] \(result.changed) changed, \(result.removed) removed")
                if result.changed + result.removed > 0 {
                    let one = page.changed.count + page.removed.count == 1
                        ? (page.changed.first ?? page.removed.first) : nil
                    await LibraryChangeFeed.shared.post(LibraryChange(reason: "server changes", itemId: one))
                }
            } catch {
                Diagnostics.log("[feed] could not apply: \(error)")
                return false
            }
        }
        feedToken = page.next
        return true
    }

    /// Between answers. Straight back to listening normally; when the Mac
    /// is on Low Power Mode or running hot, or Lumiere is in the background,
    /// changes are gathered for a while and taken in one batch.
    private func feedPause() async {
        let info = ProcessInfo.processInfo
        let strained = info.isLowPowerModeEnabled
            || info.thermalState == .serious || info.thermalState == .critical
        if strained {
            try? await Task.sleep(for: .seconds(120))
        } else if !NSApp.isActive {
            try? await Task.sleep(for: .seconds(20))
        }
    }

    /// After sleep the held request is dead; listen again at once, and send
    /// anything watched offline before it.
    private func watchForWake() {
        guard Feed.wakeObserver == nil else { return }
        Feed.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSignedIn else { return }
                Diagnostics.log("[feed] woke from sleep — listening again")
                await self.flushPlaybackOutbox()
                self.startChangeFeed()
            }
        }
    }
}
