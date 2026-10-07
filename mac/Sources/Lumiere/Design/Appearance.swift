import SwiftUI
import AppKit

/// Which appearance the app runs in.
///
/// `auto` follows the system, which is what Infuse does and what most Mac apps
/// should. The overrides exist because a media client is often the one app
/// someone wants dark on a light desktop, or vice versa.
public enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case auto
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var explanation: String {
        switch self {
        case .auto: return "Follows your system setting."
        case .light: return "Always light, whatever the system is doing."
        case .dark: return "Always dark, whatever the system is doing."
        }
    }

    /// nil means "inherit", which is how AppKit expresses following the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies to the whole app.
    ///
    /// Set on `NSApp` rather than per-window so that panels, menus and the
    /// video chrome all agree — a window-level override leaves popovers on the
    /// system appearance and the mismatch is glaring.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
