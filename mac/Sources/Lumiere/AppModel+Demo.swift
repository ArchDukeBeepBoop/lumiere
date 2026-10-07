import Foundation
import LumiereKit
import LumierePlayer

/// Demo mode: a synthetic library for developing and measuring the UI with no server.
///
/// Split out of AppModel.swift, which is well past the project's 300-line limit.
extension AppModel {
    // MARK: - Demo mode

    /// Builds the app against a synthetic library, for developing and measuring
    /// the UI without a server. Guarded by `LUMIERE_DEMO=1`.
    ///
    /// Everything below the view layer is real — real SQLite, real image pipeline,
    /// real decode — so scroll behaviour and memory figures taken here hold.
    func enterDemoMode() async {
        // Not `client == nil`: a Mac with a saved session restores it first,
        // and the demo then refused to start while the real library was never
        // loaded either — an empty window, and memory figures that measured
        // nothing. Asked for, the demo replaces whatever was restored.
        guard DemoFixtures.isEnabled else { return }

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumiere-demo.db")
            let database = try LibraryDatabase(url: url)
            let pipeline = try ImagePipeline()

            // Seed before publishing the client. Setting it first makes the shell
            // appear immediately, which reads rows out of a half-seeded cache and
            // asks for artwork that has not been written yet — every miss is
            // permanent, because RemoteImage does not retry.
            // LUMIERE_DEMO_MOVIES scales the library for the memory audit. The
            // budget in the plan is stated against a 1000-item library, and the
            // default 180 would let it pass without ever testing windowing.
            let movieCount = ProcessInfo.processInfo.environment["LUMIERE_DEMO_MOVIES"]
                .flatMap(Int.init) ?? 180
            try await DemoFixtures.seed(
                database: database, pipeline: pipeline, movieCount: movieCount
            )

            let session = JellyfinSession(
                serverURL: DemoFixtures.serverURL,
                serverName: "Demo library",
                serverId: DemoFixtures.serverId,
                userId: "demo-user",
                userName: "demo",
                deviceId: "demo-device"
            )
            let client = JellyfinClient(session: session, token: "demo")
            let repository = LibraryRepository(database: database, client: client)

            self.database = database
            self.imagePipeline = pipeline
            self.repository = repository
            self.libraries = inHomeOrder((try? await repository.libraries()) ?? [])
            self.client = client
        } catch {
            startupError = "Demo mode failed: \(error.localizedDescription)"
        }
    }

    /// True when running against the synthetic library, so the shell can skip the
    /// network sync that would otherwise wipe it.
    var isDemo: Bool {
        client?.session.serverId == DemoFixtures.serverId
    }
}
