import Foundation

/// Whether the server has the routes this app was built against.
///
/// The app and Lumiere's server ship separately, and the app now leans on
/// routes only this server has — library health, episode orders, the sync
/// window. An app newer than its server failed at each of those with a
/// generic error; one check on connect says the real reason once.
public enum ServerCompatibility {

    /// The server API level this build needs. Bump with `APILevel` in
    /// LumiereServer/internal/api/system.go.
    public static let requiredLevel = 6

    /// A sentence to show, or nil when the server is new enough — or is a
    /// Jellyfin server, which never has these routes and is not "old".
    public static func warning(for info: PublicSystemInfo) -> String? {
        guard let level = info.lumiereApi else { return nil }
        guard level < requiredLevel else { return nil }
        return "Lumiere Server is older than this app. Update LumiereControl "
             + "so library health, episode orders and subtitle fetching work."
    }

    /// Asks the server and returns the warning, if any. Silent on failure:
    /// an unreachable server is the connection banner's business.
    public static func check(_ serverURL: URL) async -> String? {
        guard let info = try? await JellyfinSignIn.publicInfo(for: serverURL) else { return nil }
        return warning(for: info)
    }
}
