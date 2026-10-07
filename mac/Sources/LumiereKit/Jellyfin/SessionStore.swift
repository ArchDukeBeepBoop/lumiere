import Foundation

/// Remembers which server you signed into, so the app opens straight to your
/// library instead of a sign-in screen. The token lives in `TokenStore`; only the
/// non-secret half of the session is stored here.
public enum SessionStore {

    private static let key = "com.lumiere.session"

    public static func save(_ session: JellyfinSession) throws {
        let data = try JSONEncoder().encode(session)
        UserDefaults.standard.set(data, forKey: key)
    }

    public static func load() -> JellyfinSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(JellyfinSession.self, from: data)
    }

    /// Restores a ready-to-use client, or nil if there is no stored session or the
    /// token file has been removed.
    public static func restoreClient() -> JellyfinClient? {
        guard let session = load(),
              let token = TokenStore.value(account: session.serverId) else {
            return nil
        }
        return JellyfinClient(session: session, token: token)
    }

    public static func clear() {
        if let session = load() {
            TokenStore.delete(account: session.serverId)
        }
        UserDefaults.standard.removeObject(forKey: key)
    }
}
