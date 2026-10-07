import SwiftUI
import LumiereKit

/// "This section differs from how Lumiere comes" — a dot by the heading — and
/// one Reset that puts it back.
///
/// Settings is large enough that what you changed months ago is invisible:
/// a section looks the same whether you have tuned it or not. The dot says
/// which sections carry your choices, and Reset is the way back without
/// remembering what each default was.
struct SettingsResettable: ViewModifier {
    /// Each key and the value it starts at.
    let defaults: [String: Any]
    @State private var isChanged = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isChanged {
                    HStack(spacing: Theme.Space.xs) {
                        Circle().fill(Theme.Palette.accent).frame(width: 6, height: 6)
                            .help("Changed from how Lumiere comes")
                        Button("Reset") { reset() }
                            .buttonStyle(.link)
                            .font(Theme.Font.caption)
                    }
                    .padding(.top, Theme.Space.lg)
                    .padding(.trailing, Theme.Space.sm)
                }
            }
            .onAppear { isChanged = changed() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let now = changed()
                if now != isChanged { isChanged = now }
            }
    }

    private func changed() -> Bool {
        defaults.contains { key, value in
            guard let stored = UserDefaults.standard.object(forKey: key) else { return false }
            return !(stored as AnyObject).isEqual(value)
        }
    }

    private func reset() {
        for key in defaults.keys { UserDefaults.standard.removeObject(forKey: key) }
    }
}

extension View {
    func resettable(_ defaults: [String: Any]) -> some View {
        modifier(SettingsResettable(defaults: defaults))
    }
}

/// The defaults of the sections that carry `.resettable`, in one place.
enum SettingsDefaults {
    static var home: [String: Any] { [
        "homeLayout": HomeLayout.classic.rawValue,
        "showsAllShelves": false,
        Preference.latestIncludesVideos.name: Preference.latestIncludesVideos.defaultValue,
        Preference.mergesUpNext.name: Preference.mergesUpNext.defaultValue,
        Preference.shufflePlaysAtOnce.name: Preference.shufflePlaysAtOnce.defaultValue,
        Preference.changeCheckSeconds.name: Preference.changeCheckSeconds.defaultValue,
        Preference.collectionDefaultOrder.name: Preference.collectionDefaultOrder.defaultValue,
    ] }
    static var room: [String: Any] { [
        Preference.roomRequiresUnlock.name: Preference.roomRequiresUnlock.defaultValue,
        Preference.roomLockMinutes.name: Preference.roomLockMinutes.defaultValue,
        Preference.roomUsesOwnTheme.name: Preference.roomUsesOwnTheme.defaultValue,
        Preference.roomBlocksCapture.name: Preference.roomBlocksCapture.defaultValue,
        Preference.roomBlursCovers.name: Preference.roomBlursCovers.defaultValue,
        Preference.looksUpPrivateLibraries.name: Preference.looksUpPrivateLibraries.defaultValue,
    ] }
    static var player: [String: Any] { [
        Preference.seekStepSeconds.name: Preference.seekStepSeconds.defaultValue,
        Preference.seekLongStepSeconds.name: Preference.seekLongStepSeconds.defaultValue,
        Preference.scrollSeeks.name: Preference.scrollSeeks.defaultValue,
        Preference.playsNextAutomatically.name: Preference.playsNextAutomatically.defaultValue,
        Preference.hidesSingleFilmCollections.name: Preference.hidesSingleFilmCollections.defaultValue,
        Preference.homeShowsBackdrop.name: Preference.homeShowsBackdrop.defaultValue,
        Preference.homeFollowsHover.name: Preference.homeFollowsHover.defaultValue,
        Preference.showsUpNextStage.name: Preference.showsUpNextStage.defaultValue,
        Preference.screensaverMinutes.name: Preference.screensaverMinutes.defaultValue,
        Preference.stillWatchingAfter.name: Preference.stillWatchingAfter.defaultValue,
        Preference.autoSkipsIntros.name: Preference.autoSkipsIntros.defaultValue,
        Preference.offersRecapSkip.name: Preference.offersRecapSkip.defaultValue,
    ] }
}
