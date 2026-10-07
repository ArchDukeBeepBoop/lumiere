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

    private(set) var state: State = .stopped
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

    func start() {
        guard state != .running, state != .starting else { return }
        guard let binary = ServerProcess.binaryURL else {
            state = .failed("The server binary is missing from this app.")
            return
        }

        let task = Process()
        task.executableURL = binary
        // No arguments: the server's own defaults are the values for this
        // machine, which is the whole reason it takes flags rather than a file.
        task.arguments = []

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

    /// Poll until the server answers, so "running" means *serving* rather than
    /// *spawned*. The two are several hundred milliseconds apart while SQLite
    /// opens a 300 MB database, and a green dot that arrives before the server
    /// can answer is worse than no dot.
    /// Stops the server and waits for it to be gone, so its database file
    /// is closed before anything replaces it.
    func stopAndWait() async {
        let running = process
        stop()
        for _ in 0..<100 where running?.isRunning == true {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

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
