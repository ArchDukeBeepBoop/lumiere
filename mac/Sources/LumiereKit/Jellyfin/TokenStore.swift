import Foundation

/// Where the Jellyfin access token and any provider keys are kept, now that the
/// Keychain is gone.
///
/// **This is a deliberate downgrade in protection, and it should be understood as
/// one.** A Keychain item is encrypted at rest and its ACL is bound to the signing
/// identity of the binary that created it; a file is neither. Anything running as
/// this user account can read this file. What that bought, in practice, was a
/// modal password prompt on *every rebuild* — a re-signed binary is a different
/// identity to the ACL, so the app stopped dead behind a system dialog several
/// times a day and twice sat there while a sync it had already started went stale.
///
/// The exposure that remains is bounded by what the token is: a session for a media
/// server on the local network, revocable from Jellyfin's own dashboard, granting
/// nothing beyond that server. Weighed against a prompt that blocked the app from
/// starting, keeping it in a file the owner alone can read is the trade taken.
///
/// `0o600` and inside the app's own Application Support directory, so it is not
/// world-readable and not in a shared location. Excluded from backups for the same
/// reason a Keychain item would not be copied around casually.
public enum TokenStore {

    /// One file per purpose, keyed like the Keychain accounts it replaces.
    private static func url(for account: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("Lumiere", isDirectory: true)
        .appendingPathComponent("Credentials", isDirectory: true)

        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true,
            // The directory too: a 0700 directory means the file cannot be reached
            // by another account even if its own mode were ever wrong.
            attributes: [.posixPermissions: 0o700]
        )
        return base.appendingPathComponent("\(account).token")
    }

    public static func store(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clearing the field removes the credential rather than storing an empty
        // one, so "delete my key" needs no separate control.
        guard !trimmed.isEmpty else {
            delete(account: account)
            return
        }
        let url = try url(for: account)
        try Data(trimmed.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
    }

    public static func value(account: String) -> String? {
        guard let url = try? url(for: account),
              let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    public static func delete(account: String) -> Bool {
        guard let url = try? url(for: account) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }
}
