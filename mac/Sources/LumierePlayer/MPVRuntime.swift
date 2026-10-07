import Foundation
import CMPV

/// A thin probe over libmpv, used at launch to prove the dylib is linked and
/// usable before any playback is attempted. The full engine lands in phase 6;
/// this exists so a broken Homebrew mpv surfaces as a clear diagnostic line
/// rather than a crash three screens in.
public enum MPVRuntime {

    /// The libmpv client API version this binary is linked against, as major.minor.
    public static var clientAPIVersion: String {
        let raw = mpv_client_api_version()
        return "\(raw >> 16).\(raw & 0xFFFF)"
    }

    /// Creates and immediately destroys a handle. Returns nil if libmpv is present
    /// but unusable, which is the failure mode worth catching early.
    public static func probe() -> String? {
        guard let handle = mpv_create() else { return nil }
        defer { mpv_terminate_destroy(handle) }

        guard mpv_initialize(handle) >= 0 else { return nil }

        guard let version = mpv_get_property_string(handle, "mpv-version") else {
            return "libmpv \(clientAPIVersion)"
        }
        defer { mpv_free(version) }
        return String(cString: version)
    }
}
