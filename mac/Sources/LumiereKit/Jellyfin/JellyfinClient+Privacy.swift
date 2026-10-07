import Foundation

/// Lumiere's server: which libraries are private, and which the naming pass
/// leaves alone. Kept on the server so the phone and TV follow the Mac.
public extension JellyfinClient {
    /// Libraries the server's naming pass leaves alone.
    func setLookupSkipped(_ libraryIds: Set<String>) async {
        let body = try? JSONSerialization.data(withJSONObject: ["Libraries": Array(libraryIds)])
        try? await sendVoid(path: "Lumiere/Metadata/Skip", method: "POST", body: body)
    }

    /// The private libraries, kept on the server so the phone and TV follow them.
    func setPrivateLibraries(_ libraryIds: Set<String>) async {
        let body = try? JSONSerialization.data(withJSONObject: ["Libraries": Array(libraryIds).sorted()])
        try? await sendVoid(path: "Lumiere/Private", method: "POST", body: body)
    }
}
