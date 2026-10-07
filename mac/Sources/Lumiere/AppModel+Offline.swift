import Foundation
import LumiereKit

/// Offline mode: noticing the server has gone, and noticing when it comes back.
///
/// The app was already *capable* of working offline — the library is a complete
/// local copy — but only the sync ever said so, and only at the moment it failed.
/// Anything else that touched the network failed on its own, one screen at a time,
/// with a network error where an explanation belonged; and once the banner was up
/// nothing brought it down again except the user pressing Retry. This file is the
/// two halves that were missing: any failed request can now put the app into
/// offline mode, and offline mode looks for its own way out.
///
/// Split from AppModel.swift for the project's 300-line limit, and because it is a
/// genuinely separate concern from wiring up a session.
extension AppModel {

    // MARK: - Engaging

    /// Reports a failed request, and enters offline mode if that is what it means.
    ///
    /// The call sites hand over whatever they caught rather than deciding for
    /// themselves, so there is exactly one place that knows which errors count —
    /// `ConnectionState.isUnreachable`. A 401 or a 500 is left alone here: the
    /// server is up, and the screen that failed should say what *it* could not do.
    ///
    /// Returns whether the app is now offline, so a caller can choose a different
    /// message for the two cases.
    @discardableResult
    func noteRequestFailure(_ error: Error) -> Bool {
        guard Connection.isUnreachable(error) else { return connection.isOffline }
        goOffline(Connection.message(for: error))
        return true
    }

    /// Enters offline mode and, unless told otherwise, starts watching for the
    /// server's return.
    ///
    /// `probing: false` is for the failures that are not about reachability — a
    /// library that only partly synced, a rejected token — where a probe would
    /// either succeed instantly and change nothing, or succeed instantly and start
    /// a sync that fails the same way. Neither is worth a background task.
    func goOffline(_ message: String, probing: Bool = true) {
        let wasOffline = connection.isOffline
        connection = .offline(message)
        justReconnected = false
        if probing, !wasOffline || reconnectTask == nil {
            startReconnectWatch()
        }
    }

    // MARK: - Recovering

    /// Polls for the server on a widening backoff, and stops the moment it answers.
    ///
    /// Three things keep this from becoming the infinite loop this project has
    /// already shipped once. It only ever starts from `goOffline`; every iteration
    /// re-checks that the app is *still* offline, so a manual Retry that succeeds
    /// ends it; and the interval doubles to two minutes, so a server that is off for
    /// the weekend costs about thirty requests a day rather than seventeen thousand.
    /// It is also cancelled by sign-out, along with downloads and the prefetcher.
    private func startReconnectWatch() {
        guard reconnectTask == nil else { return }
        // Nothing to poll: demo mode has no server, and without a repository there
        // is no client to ask with. Both would otherwise spin a task that can only
        // ever fail.
        guard !isDemo, repository != nil else { return }

        Diagnostics.log("[offline] watching for the server to come back")
        reconnectTask = Task { @MainActor in
            while !Task.isCancelled, connection.isOffline {
                let delay = Connection.retryDelay(attempt: reconnectAttempts)
                nextReconnectAttempt = Date().addingTimeInterval(delay)
                try? await Task.sleep(for: .seconds(delay))
                // Re-read after the sleep, not before it: a Retry pressed during the
                // wait may already have reconnected, and probing again would be
                // asking a question that has been answered.
                guard !Task.isCancelled, connection.isOffline,
                      let repository else { break }

                nextReconnectAttempt = nil
                isCheckingConnection = true
                let reachable = await repository.isReachable()
                isCheckingConnection = false
                guard !Task.isCancelled else { break }

                if reachable {
                    Diagnostics.log(
                        "[offline] server answered after \(reconnectAttempts + 1) attempt(s)"
                    )
                    didReconnect()
                    break
                }
                reconnectAttempts += 1
            }
            // Only a task that finished on its own terms tidies up after itself. A
            // cancelled one has already been replaced: `cancelReconnectWatch` nils
            // the handle, and a failed Retry starts a fresh watch immediately —
            // before this one wakes from its sleep to notice it was cancelled.
            // Clearing unconditionally would null out the *new* task's handle and
            // let a third one start alongside it.
            guard !Task.isCancelled else { return }
            nextReconnectAttempt = nil
            isCheckingConnection = false
            reconnectTask = nil
        }
    }

    /// Comes back online and catches the cache up.
    ///
    /// Through `startSync` rather than `syncEverything`, so the one-at-a-time guard
    /// still holds — a reconnect landing while a launch sync is somehow still in
    /// flight must not start a second loop writing the same rows. The sync itself
    /// decides what the result means and will put the banner straight back if the
    /// server was only briefly awake.
    private func didReconnect() {
        connection = .online
        startupError = nil
        justReconnected = true
        // Before the sync, not after. The sync overwrites local watch state with the
        // server's, so a flush that ran afterwards would be sending positions the
        // sync had already replaced. See `AppModel+Outbox`.
        Task { @MainActor in
            await flushPlaybackOutbox()
            startSync()
        }
        // Clears itself, like `report(_:)` does. The banner is a statement about
        // right now, and "reconnected" stops being true a few seconds later.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            justReconnected = false
        }
    }

    /// Re-attempts the sync behind the offline banner's Retry.
    func retryConnection() async {
        // The probe is asking this same question on a timer; a press is asking it
        // now. Stopping it first means the two cannot both be in flight, and the
        // sync below decides the outcome for both.
        cancelReconnectWatch()
        connection = .unknown
        guard !isDemo else {
            // Demo mode has no server to reach, so a retry can only ever resolve
            // to whatever the launch hook asked for.
            applyForcedOfflineIfRequested()
            return
        }
        await loadCachedLibraries()
        await runSync(userInitiated: true)
    }

    /// `LUMIERE_FORCE_OFFLINE=1` pretends the server is unreachable.
    ///
    /// The offline banner and the empty-cache offline state cannot otherwise be
    /// seen without a server that is up long enough to sync and then goes down,
    /// which is not something a build shell can arrange. Same purpose as the other
    /// `LUMIERE_*` hooks: make a state reachable so it can actually be looked at.
    func applyForcedOfflineIfRequested() {
        guard ProcessInfo.processInfo.environment["LUMIERE_FORCE_OFFLINE"] == "1" else { return }
        // No probe: the point of the hook is to hold the app in offline mode so the
        // state can be looked at, and a real server answering would end it.
        goOffline("Simulated failure: connection refused.", probing: false)
    }

    /// Stops the probe. Called by sign-out and by a manual retry, which is asking
    /// the same question sooner.
    func cancelReconnectWatch() {
        reconnectTask?.cancel()
        reconnectTask = nil
        nextReconnectAttempt = nil
        isCheckingConnection = false
    }

    // MARK: - Refusing, at the point of use

    /// Whether an action that needs the server should be offered at all.
    var isOffline: Bool { connection.isOffline }

    /// Says plainly that something cannot be done right now.
    ///
    /// The alternative — letting the action run and fail — is what this is here to
    /// replace: an Identify sheet that opens, searches, and shows a transport error
    /// is three steps of work to learn something the app already knew before the
    /// first one. `action` reads as the start of a sentence: "Identifying".
    func refuseOffline(_ action: String) {
        let server = client?.session.serverName ?? "the server"
        report("\(action) needs \(server), which is unreachable right now.")
    }

    /// How many downloaded titles still play with the server away.
    ///
    /// Shown in the offline banner because it is the one genuinely good news in that
    /// state, and nothing said it: browsing works from the cache, but only these
    /// actually start.
    var playableOfflineCount: Int {
        downloadRecords.filter { $0.state == .complete }.count
    }
}
