import Foundation

/// Starting, stopping and watching `lumiered`.
///
/// The server is a child process rather than a launchd job. That is a deliberate
/// trade: launchd would restart it after a crash and survive a logout, but it
/// also puts the process outside this app's reach — you cannot read its exit
/// status, and "start it" becomes "ask launchd to, then poll and hope". Here the
/// controller owns the process, so the menu can say *why* the server stopped
/// rather than only that it is not answering.
///
/// The consequence is honest and worth naming: quitting this app stops the
/// server. The menu says so.
@MainActor
@Observable
final class ServerProcess {

    enum State: Equatable {
        case stopped
        case starting
        case running
        /// Exited on its own. The reason is kept because a server that refuses to
        /// start is the one moment a menu bar app has to explain itself — the
        /// usual causes are a port already in use and a missing database, and
        /// both are fixable if you are told which.
        case failed(String)
    }

    private(set) var state: State = .stopped {
        didSet {
            // When it started serving, for the uptime in the menu. Set on the
            // transition rather than by each caller, so adopting a server that
            // was already running and starting a fresh one agree.
            if state == .running, oldValue != .running { startedAt = Date() }
            if state != .running { startedAt = nil }
        }
    }
    private(set) var startedAt: Date?
    /// The server refused to start because its library is gone while a backup
    /// or its witness says there was one. The menu offers Restore and Start
    /// Fresh rather than a restart, which would only be refused again.
    private(set) var libraryMissing = false
    /// Whether the process is this app's own. An adopted server — one started
    /// from a terminal — is reported when it stops answering, never signalled.
    var ownsProcess: Bool { process != nil }
    /// The last few log lines, for the "why did it stop" case.
    private(set) var recentLog: [String] = []

    private var process: Process?
    private var probe: Task<Void, Never>?

    /// Where the server binary lives: inside this app bundle.
    ///
    /// Bundled rather than found on PATH so the controller always runs the server
    /// it was built against. A `lumiered` from six months ago on $PATH, answering
    /// an app that expects today's endpoints, is a failure that looks like a bug
    /// in the client.
    static var binaryURL: URL? {
        Bundle.main.url(forResource: "lumiered", withExtension: nil)
    }

    let address = URL(string: "http://127.0.0.1:8098")!

    /// The exit status the server uses for a missing library.
    static let exitLibraryMissing: Int32 = 3

    func start(fresh: Bool = false) {
        guard state != .running, state != .starting else { return }
        guard let binary = ServerProcess.binaryURL else {
            state = .failed("The server binary is missing from this app.")
            return
        }

        let task = Process()
        task.executableURL = binary
        // The server's own defaults are the values for this machine; only what
        // the person chose in Settings is passed, and Start Fresh when asked.
        var arguments: [String] = []
        if let mirror = BackupRestorer.mirrorFolder {
            arguments += ["-backup-mirror", mirror.path]
        }
        if let pictures = UserDefaults.standard.string(forKey: PictureFolder.key), !pictures.isEmpty {
            arguments += ["-cache", pictures]
        }
        if fresh { arguments.append("-start-fresh") }
        task.arguments = arguments
        libraryMissing = false

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.absorb(text) }
        }

        task.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.finished(status: finished.terminationStatus)
            }
        }

        do {
            try task.run()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        process = task
        state = .starting
        watchUntilListening()
    }

    func stop() {
        probe?.cancel()
        probe = nil
        // SIGTERM, not SIGKILL: the server drains in-flight requests and closes
        // its database cleanly. Killing it mid-write is how a library ends up
        // needing a recovery pass on next start.
        process?.terminate()
        process = nil
        state = .stopped
    }

    /// Stop, wait for the old process to let go of the port and the database,
    /// then start. Waiting is the point: a start issued straight after a stop
    /// races the old server for 8098 and loses with "address already in use".
    func restart() async {
        await stopAndWait()
        start()
    }

    /// Stops the server and waits for it to be gone, so its database file
    /// is closed before anything replaces it.
    func stopAndWait() async {
        let running = process
        stop()
        for _ in 0..<100 where running?.isRunning == true {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Poll until the server answers, so "running" means *serving* rather than
    /// *spawned*. The two are several hundred milliseconds apart while SQLite
    /// opens a 300 MB database, and a green dot that arrives before the server
    /// can answer is worse than no dot.
    private func watchUntilListening() {
        probe?.cancel()
        probe = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<40 {
                if Task.isCancelled { return }
                if await self.isAnswering() {
                    self.state = .running
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if case .starting = self.state {
                self.state = .failed("The server did not answer within ten seconds.")
            }
        }
    }

    func isAnswering() async -> Bool {
        var request = URLRequest(url: address.appending(path: "System/Info/Public"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Liveness: does the process answer HTTP at all, within five seconds?
    ///
    /// `/health/live` touches no lock and no database, so a busy library
    /// cannot make it slow. Any HTTP answer counts, a 404 from a server too
    /// old to have the route included: liveness is "the process answers",
    /// and only no answer at all is a miss.
    func isLive() async -> Bool {
        var request = URLRequest(url: address.appending(path: "health/live"))
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return response is HTTPURLResponse
    }

    /// Writes why this app acted into the server's own log, so a restart is
    /// never a gap with no explanation in the one place anyone will look.
    func note(_ reason: String) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
        let line = "time=\(stamp) level=WARN msg=\"LumiereControl: \(reason)\"\n"
        guard let handle = try? FileHandle(forWritingTo: LibraryMonitor.logFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Gives up on a server that will not stay up, with the reason shown.
    func giveUp(_ reason: String) {
        stop()
        state = .failed(reason)
    }

    /// Adopt a server that is already running — one started from a terminal, or
    /// left behind by a previous run of this app. Without this the menu would
    /// offer to start a second one and report a port clash as a failure.
    func adoptIfAlreadyRunning() async {
        guard state == .stopped, await isAnswering() else { return }
        state = .running
    }

    private func absorb(_ text: String) {
        for line in text.split(separator: "\n") {
            recentLog.append(String(line))
        }
        recentLog = Array(recentLog.suffix(40))
    }

    private func finished(status: Int32) {
        process = nil
        probe?.cancel()
        if status == 0 {
            state = .stopped
            return
        }
        libraryMissing = status == Self.exitLibraryMissing
        state = .failed(reasonFromLog() ?? "The server stopped (status \(status)).")
    }

    /// The server's own last error line beats a status code. "bind: address
    /// already in use" tells you what to do; "status 1" does not.
    private func reasonFromLog() -> String? {
        guard let line = recentLog.last(where: { $0.contains("level=ERROR") }) else { return nil }
        guard let range = line.range(of: "msg=") else { return line }
        return String(line[range.upperBound...])
            .replacingOccurrences(of: "\"", with: "")
    }
}
