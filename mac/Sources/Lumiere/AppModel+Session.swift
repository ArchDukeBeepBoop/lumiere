import Foundation
import LumiereKit

/// Ending a session and starting one.
///
/// Split out of AppModel.swift for the 300-line rule. Kept together because they are
/// two halves of one fact: everything `attach` builds — database, repository, image
/// pipeline, downloads, the music player's credentials — `signOut` has to take back
/// apart, and a thing added to one and forgotten in the other is another account's
/// data surviving into the next session.
@MainActor
extension AppModel {

    func signOut() {
        let database = self.database
        SessionStore.clear()
        // Stopped before the database goes, not after. A download in flight holds
        // the old client and the old token and would keep writing rows into a
        // database being wiped — with the previous account's credentials.
        let stoppingDownloads = self.downloads
        let stoppingPrefetcher = self.prefetcher
        Task {
            await stoppingDownloads?.cancelAll()
            await stoppingPrefetcher?.cancel()
        }
        cancelSync()
        cancelAutoSync()
        // With the sync, and for the same reason: it holds the old client through
        // the repository and would keep probing a server this session no longer has
        // any business asking about.
        cancelReconnectWatch()
        connection = .unknown
        justReconnected = false
        reconnectAttempts = 0
        client = nil
        repository = nil
        imagePipeline = nil
        setTransfers(downloads: nil, prefetcher: nil)
        downloadRecords = []
        nowPlayingItemId = nil
        self.database = nil
        libraries = []
        homeModel = nil

        // Another account's items must never survive into the next session.
        Task {
            try? await database?.reset()
        }
    }

    // MARK: - Wiring

    /// Not private: `signOut` and `attach` live in AppModel+Session.swift, and Swift's
    /// `private` is file-scoped, so `restoreSession` over in AppModel.swift could not
    /// see it. Internal to this module, not to the app.
    func attach(_ client: JellyfinClient) async {
        self.client = client
        // Artwork requests need the same auth header as the API; Jellyfin rejects
        // unauthenticated image requests on most configurations. Snapshotting the
        // header here is safe because a new token always arrives as a new client,
        // which re-attaches.
        let headers = await client.streamingHeaders
        do {
            let database = try LibraryDatabase(url: try LibraryDatabase.defaultURL())
            self.database = database
            let repository = LibraryRepository(database: database, client: client)
            self.repository = repository
            await repository.announceWatchStateChanges()
            let pipeline = try ImagePipeline(headers: headers)
            self.imagePipeline = pipeline
            setTransfers(
                downloads: try DownloadManager(database: database, client: client),
                prefetcher: ArtworkPrefetcher(
                    pipeline: pipeline, serverURL: client.session.serverURL
                )
            )
            // AVPlayer fetches audio outside this client's URLSession, so it needs
            // the token itself rather than the auth header everything else uses.
            music.configure(
                serverURL: client.session.serverURL,
                deviceId: client.session.deviceId,
                token: await client.accessToken
            )
            await refreshDownloads()
        } catch {
            startupError = "Couldn't open the local library cache. \(error.localizedDescription)"
        }
    }
}
