import Foundation

extension SettingsView.Category {
    /// LUMIERE_SETTINGS=library opens Settings on that section — for the
    /// walkthrough's Library Health shot, which cannot click its way there.
    static var atLaunch: Self {
        ProcessInfo.processInfo.environment["LUMIERE_SETTINGS"].flatMap(Self.init(rawValue:)) ?? .look
    }

    /// LUMIERE_SETTINGS_CARD="Library Health" scrolls to that card, as a
    /// search result does.
    static var launchCard: String? {
        ProcessInfo.processInfo.environment["LUMIERE_SETTINGS_CARD"]
    }
}
