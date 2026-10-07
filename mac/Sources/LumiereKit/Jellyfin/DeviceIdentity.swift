import Foundation

/// What this client calls itself when it talks to Jellyfin.
///
/// Nothing here is secret — a device id, a machine name, a version string — which
/// is why it outlived the Keychain enum it used to share a file with.
public enum DeviceIdentity {

    private static let defaultsKey = "com.lumiere.deviceId"

    public static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: defaultsKey)
        return fresh
    }

    public static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    public static let clientName = "Lumiere"

    public static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
