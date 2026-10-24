import SwiftUI
import LumiereKit

/// The first launch after an update: what changed, three things, once — the
/// card Apple's own apps show. Never on a first run (the setup guide has that
/// moment), never over the player, and off in Settings › Look for anyone who
/// would rather find out for themselves.
enum WhatsNew {
    static let seenKey = "whatsNewSeenVersion"

    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    static let version = "1.2"

    static let items: [Item] = [
        Item(icon: "desktopcomputer", title: "On This Computer",
             detail: "Open any file, folder, stream or playlist — from Finder, the Dock or File › Open. Lumiere can be your Mac’s player, server or not."),
        Item(icon: "sidebar.right", title: "The player’s new sidebar",
             detail: "Subtitles, Audio, Video and Playback beside the picture: sync subtitles by ear, picture and sound controls, bookmarks with ⌘B, and presets saved for a whole show."),
        Item(icon: "paintpalette", title: "Your colours, your keys",
             detail: "Choose an accent colour, tint the player from the artwork, and change the player’s letter keys in Settings."),
    ]

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? version
    }

    /// Whether to show it now. A Mac that has never recorded a version is
    /// either new (no libraries yet — the guide's job) or updating from
    /// before this card existed (libraries — show it).
    @MainActor static func shouldShow(hasLibraries: Bool) -> Bool {
        guard Preference.showsWhatsNew.value else { return false }
        let seen = UserDefaults.standard.string(forKey: seenKey)
        if seen == nil && !hasLibraries { markSeen(); return false }
        return seen.map { !$0.hasPrefix(version) } ?? true
    }

    static func markSeen() { UserDefaults.standard.set(current, forKey: seenKey) }
}

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("What’s New in Lumiere \(WhatsNew.version)")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                ForEach(WhatsNew.items) { item in
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Image(systemName: item.icon)
                            .font(Theme.Glyph.xl())
                            .foregroundStyle(Theme.Palette.accent)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(item.title).font(Theme.Font.body.weight(.semibold))
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(item.detail).font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack {
                Spacer()
                Button("Continue") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 480)
        .glassSheet()
        .onDisappear { WhatsNew.markSeen() }
    }
}

extension View {
    /// Shows `WhatsNewSheet` once after an update. See `WhatsNew`.
    func whatsNewAfterUpdate(app: AppModel) -> some View {
        modifier(WhatsNewModifier(app: app))
    }
}

private struct WhatsNewModifier: ViewModifier {
    let app: AppModel
    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .task {
                // After launch has settled, so it never races the setup guide.
                try? await Task.sleep(for: .seconds(2))
                guard app.nowPlayingItemId == nil, !app.isShowingSetupGuide else { return }
                isShowing = WhatsNew.shouldShow(hasLibraries: !app.libraries.isEmpty)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showWhatsNew)) { _ in isShowing = true }
            .sheet(isPresented: $isShowing) { WhatsNewSheet() }
    }
}

extension Notification.Name {
    /// Help › What’s New in Lumiere.
    static let showWhatsNew = Notification.Name("lumiere.showWhatsNew")
}
