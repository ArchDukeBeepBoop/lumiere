import Foundation
import Observation
import LumiereKit

/// Drives the sign-in flow: find the server, then authenticate against it.
///
/// Two steps rather than one screen, because the second step depends on what the
/// server supports — Quick Connect only appears when the server has it enabled,
/// and the user list only appears when the server publishes one.
@MainActor
@Observable
final class SignInModel {

    enum Step: Equatable {
        case server
        case credentials
    }

    var step: Step = .server
    var address: String = ""
    var username: String = ""
    var password: String = ""
    /// Typed twice when making the first account. See `SignInView+FirstAccount`.
    var confirmPassword: String = ""
    /// A brand-new server with no account yet: the second step makes one.
    private(set) var needsAccount = false

    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var resolvedURL: URL?
    private(set) var serverInfo: PublicSystemInfo?
    private(set) var publicUsers: [JellyfinUser] = []

    private(set) var quickConnectAvailable = false
    private(set) var quickConnectCode: String?
    private var quickConnectTask: Task<Void, Never>?

    /// Servers that answered the discovery broadcast, offered as one-click choices
    /// so that nobody has to know their own server's address.
    private(set) var discovered: [DiscoveredServer] = []
    private(set) var isDiscovering = false

    /// Set when sign-in succeeds. The app shell watches this to swap in the library.
    var onSignedIn: ((JellyfinClient) -> Void)?

    var serverDisplayName: String {
        serverInfo?.serverName ?? resolvedURL?.host ?? "Lumiere"
    }

    var canSubmitCredentials: Bool {
        !username.isEmpty && !isBusy
    }

    // MARK: - Step 1: find the server

    /// Looks for servers on the network. Runs on appearing, and again on demand.
    func findServers() async {
        isDiscovering = true
        let servers = await JellyfinDiscovery.discover()
        discovered = servers
        isDiscovering = false

        // Prefill a lone result rather than auto-connecting. Filling the field
        // shows what is about to be used and leaves it editable; connecting on its
        // own would be a network call the user never asked for.
        if let only = servers.first, servers.count == 1, address.isEmpty {
            address = only.displayAddress
        }
        // A server on this Mac — the usual first run — answers on loopback even
        // when nothing answered the broadcast.
        if address.isEmpty, let local = URL(string: "http://127.0.0.1:8098"),
           (try? await JellyfinSignIn.publicInfo(for: local)) != nil {
            address = "127.0.0.1:8098"
        }
    }

    /// Connects to a discovered server directly, skipping the resolve guesswork —
    /// the server told us its own address, so there is nothing to guess.
    func connect(to server: DiscoveredServer) async {
        address = server.displayAddress
        await connect()
    }

    /// `LUMIERE_AUTH_DIAG=1` posts a deliberately-wrong credential and logs the
    /// status, through the app's real networking rather than a shell tool.
    ///
    /// The distinction it exists to draw: 401 means the request was well formed and
    /// the credentials were refused, so the problem is the password. Anything else —
    /// 400 in particular — means the app built a request the server would not even
    /// parse, and no password would have worked. `curl` cannot answer this, because
    /// it does not encode headers the way URLSession does.
    func runAuthDiagnostic() async {
        guard ProcessInfo.processInfo.environment["LUMIERE_AUTH_DIAG"] == "1",
              let url = resolvedURL, let info = serverInfo else { return }

        Diagnostics.log("[diag] device name: \(DeviceIdentity.deviceName.debugDescription)")
        Diagnostics.log("[diag] header: \(JellyfinClient.diagnosticAuthorizationValue())")
        do {
            _ = try await JellyfinSignIn.authenticate(
                serverURL: url, serverInfo: info,
                username: "__lumiere_diag__", password: "__deliberately_wrong__"
            )
            Diagnostics.log("[diag] unexpected success")
        } catch {
            Diagnostics.log("[diag] result: \(error)")
        }
    }

    /// `LUMIERE_SERVER=<address>` connects at launch.
    ///
    /// Signing in needs typing, and driving the keyboard needs Accessibility
    /// permission a build shell does not have — so without this the sign-in flow
    /// cannot be exercised against a real server at all, which is exactly how it
    /// stayed broken this long.
    func applyLaunchServerIfRequested() async {
        guard let value = ProcessInfo.processInfo.environment["LUMIERE_SERVER"],
              !value.isEmpty else { return }
        address = value
        await connect()
    }

    func connect() async {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let (url, info) = try await JellyfinSignIn.resolve(address: address)
            resolvedURL = url
            serverInfo = info
            publicUsers = await JellyfinSignIn.publicUsers(serverURL: url)
            quickConnectAvailable = await JellyfinSignIn.quickConnectEnabled(serverURL: url)
            needsAccount = await JellyfinSignIn.needsFirstAccount(serverURL: url)
            step = .credentials
            await runAuthDiagnostic()
        } catch {
            var message = (error as? JellyfinError)?.errorDescription
                ?? error.localizedDescription

            // "Couldn't reach the server" on its own leaves the user with nowhere to
            // go. If a broadcast did find something, name it — the usual cause of
            // this failure is an address on the wrong subnet, and the right one is
            // already sitting in the list.
            if !discovered.isEmpty {
                let names = discovered.map { "\($0.name) at \($0.displayAddress)" }
                message += names.count == 1
                    ? "\n\nFound \(names[0]) on your network — try that instead."
                    : "\n\nFound these on your network: " + names.joined(separator: ", ")
            } else if !isDiscovering {
                message += "\n\nNothing answered a search of your local network either."
                    + " Check the server is running, and that Lumiere is allowed to"
                    + " find devices on your network in System Settings › Privacy &"
                    + " Security › Local Network."
            }
            errorMessage = message
        }
    }

    func backToServer() {
        cancelQuickConnect()
        step = .server
        errorMessage = nil
        password = ""
    }

    // MARK: - Step 2a: password

    func signIn() async {
        guard let url = resolvedURL, let info = serverInfo else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let (session, token) = try await JellyfinSignIn.authenticate(
                serverURL: url, serverInfo: info, username: username, password: password
            )
            try await finish(session: session, token: token)
        } catch {
            errorMessage = (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Step 2, first run: make the account

    var canCreateAccount: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 4
            && password == confirmPassword && !isBusy
    }

    func createAccount() async {
        guard let url = resolvedURL, let info = serverInfo, canCreateAccount else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let (session, token) = try await JellyfinSignIn.createFirstAccount(
                serverURL: url, serverInfo: info, username: username, password: password
            )
            confirmPassword = ""
            // The guide opens on a new server; see `SetupGuide`.
            UserDefaults.standard.set(false, forKey: SetupGuide.doneKey)
            try await finish(session: session, token: token)
        } catch {
            errorMessage = (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Step 2b: Quick Connect

    func startQuickConnect() {
        guard let url = resolvedURL, let info = serverInfo else { return }
        cancelQuickConnect()
        errorMessage = nil

        quickConnectTask = Task { [weak self] in
            do {
                let result = try await JellyfinSignIn.initiateQuickConnect(serverURL: url)
                guard let self, !Task.isCancelled else { return }
                self.quickConnectCode = result.code

                try await JellyfinSignIn.awaitQuickConnectApproval(
                    serverURL: url, secret: result.secret
                )
                guard !Task.isCancelled else { return }

                let (session, token) = try await JellyfinSignIn.authenticateWithQuickConnect(
                    serverURL: url, serverInfo: info, secret: result.secret
                )
                try await self.finish(session: session, token: token)
            } catch is CancellationError {
                // User backed out; nothing to report.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.quickConnectCode = nil
                self.errorMessage = (error as? JellyfinError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    func cancelQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectCode = nil
    }

    // MARK: - Completion

    private func finish(session: JellyfinSession, token: String) async throws {
        try TokenStore.store(token, account: session.serverId)
        try SessionStore.save(session)
        password = ""
        onSignedIn?(JellyfinClient(session: session, token: token))
    }
}
