import SwiftUI
import LumiereKit

/// Settings, laid out as Infuse has it: categories down the left, a form on the
/// right, built from native macOS controls rather than bespoke ones — this is the
/// one screen where looking like the rest of the system matters more than looking
/// like the rest of the app.
// Several members below are deliberately not private: SettingsView+General.swift
// holds the General pane and reads them. Swift's `private` is file-scoped, so
// splitting a view across files means widening whatever the other half touches.
struct SettingsView: View {
    @Bindable var app: AppModel
    @State var isConfirmingSignOut = false
    @State var hiddenEntries: [LibraryEntry] = []
    @State var hiddenCollections: [HiddenCollection] = []
    /// Only what is being typed. Stored keys are never read back out of the Keychain
    /// into the UI — there is nothing a view can legitimately do with one.
    @State var providerKeys: [String: String] = [:]
    /// Which key field has the cursor, so leaving one can save what is in it.
    /// See `SettingsView.save` — typing a key and clicking away used to discard it.
    @FocusState var focusedKeyField: String?
    @Binding var homeLayout: HomeLayout

    @AppStorage("appearance") var appearance: AppearanceSetting = .auto
    // Same keys and defaults as RootView, which is what actually draws it.
    @AppStorage("glassBackground") var isGlass = true
    @AppStorage("glassOpacity") var glassOpacity = 0.62
    @AppStorage("titleStyle") var titleStyle: TitleStyle = .metadataTitle
    @AppStorage("unifiedEpisodeArt") var unifiedEpisodeArt = false
    /// Stored as the raw value so the picker binds without a Codable AppStorage
    /// wrapper; the player reads it back through SubtitleKind(rawValue:).
    @AppStorage("preferredSubtitleKind") var preferredSubtitleKind = SubtitleKind.dialogue.rawValue
    @AppStorage("subtitleStyle") var subtitleStyle = "default"
    @AppStorage("subtitleSize") var subtitleSize = SubtitleSize.normal.rawValue
    @AppStorage("maxBitrateMbps") var maxBitrateMbps: Double = 0
    @AppStorage("defaultVolumeBoost") var defaultVolumeBoost: Double = 100

    // Not private: the sidebar that reads both lives in SettingsView+Sidebar.swift.
    @State var category: Category = .atLaunch
    /// What is typed in the sidebar's search field. See `SettingsIndex`.
    @State var query = ""
    @AppStorage(Preference.showsAllShelves.name) var showsAllShelves
        = Preference.showsAllShelves.defaultValue
    @AppStorage(Preference.latestIncludesVideos.name) var latestIncludesVideos
        = Preference.latestIncludesVideos.defaultValue
    @AppStorage(Preference.creditsWindowMinutes.name) var creditsWindowMinutes
        = Preference.creditsWindowMinutes.defaultValue
    @AppStorage(Preference.followsLinkedChapters.name) var followsLinkedChapters
        = Preference.followsLinkedChapters.defaultValue
    @AppStorage(Preference.pausesWhileScrubbing.name) var pausesWhileScrubbing
        = Preference.pausesWhileScrubbing.defaultValue
    @AppStorage(Preference.scrollSeeks.name) var scrollSeeks
        = Preference.scrollSeeks.defaultValue
    @AppStorage(Preference.seekStepSeconds.name) var seekStepSeconds
        = Preference.seekStepSeconds.defaultValue
    @AppStorage(Preference.seekLongStepSeconds.name) var seekLongStepSeconds
        = Preference.seekLongStepSeconds.defaultValue
    @AppStorage(Preference.playsFromDisk.name) var playsFromDisk
        = Preference.playsFromDisk.defaultValue
    @AppStorage(Preference.remembersFlip.name) var remembersFlip
        = Preference.remembersFlip.defaultValue
    @AppStorage(Preference.seekLanding.name) var seekLanding
        = Preference.seekLanding.defaultValue
    /// The card a search result asked for: scrolled to, then briefly ringed.
    @State var searchTarget: String? = Category.launchCard
    /// The long section open on a page of its own. See `SettingsPages`.
    @State var openCard: String?
    @State private var cacheBytes: Int?
    @State private var isClearing = false
    @State var isConfirmingClearHidden = false
    @State var isConfirmingReplaceArtwork = false


    var body: some View {
        HStack(spacing: 0) {
            categoryList
            Divider()
            detail
        }
        .background(Theme.Palette.canvas)
        .task { await refreshCacheSize() }
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                // The pane's own title, rather than relying on the selected row in
                // the sidebar to say where you are. A settings window is often
                // opened straight to one pane from a menu, with the sidebar never
                // looked at.
                if let open = openCard {
                    Button {
                        withAnimation(Theme.Motion.transition) { openCard = nil }
                    } label: {
                        Label(category.title, systemImage: "chevron.left")
                            .font(Theme.Font.body.weight(.medium))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    Text(open)
                        .font(Theme.Font.hero)
                        .foregroundStyle(Theme.Palette.textPrimary)
                } else {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    // The pane's own icon at display size, which is what makes a
                    // settings screen feel like a place rather than a form: tvOS
                    // and iOS both lead a pane with the same mark that got you
                    // there, so arriving confirms where you are.
                    SettingsIconChip(category.icon, size: 40, isProminent: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(Theme.Font.hero)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(category.summary)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Each room has its own settings. See `RoomPreferences`.
                        if app.isShowingPrivateLibraries {
                            Label("The private room's own settings — the library's are kept apart.",
                                  systemImage: "lock")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.accent)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, Theme.Space.xs)
                }

                switch category {
                case .look:
                    generalForm
                    titleCards
                    DetailsCard()
                case .home: homeSettings
                case .playback:
                    playbackForm
                    audioForm
                    hotKeysForm
                    SubtitleProviderCard(app: app)
                case .yours: yourSetupForm
                case .library: libraryForm
                case .privacy: privacySettings
                case .advanced: advancedForm
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.vertical, Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.canvas)
        .environment(\.settingsHighlight, searchTarget)
        .environment(\.settingsOpenCard, $openCard)
        .onChange(of: category) { openCard = nil }
        // ⌘[ out of a section's page. See `ShellView`'s Back.
        .onReceive(NotificationCenter.default.publisher(for: .settingsBack)) { _ in
            withAnimation(Theme.Motion.transition) { openCard = nil }
        }
        .animation(Theme.Motion.transition, value: openCard)
        .onChange(of: searchTarget, initial: true) {
            guard let searchTarget else { return }
            // A long section's answer is its own page; a short one is scrolled to.
            openCard = SettingsPages.isPage(searchTarget) ? searchTarget : nil
            // A beat, so the new pane has laid its cards out before we ask the
            // proxy for one of them.
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(Theme.Motion.hover) {
                    proxy.scrollTo(searchTarget, anchor: .center)
                }
                // The ring is a pointer, not a state. Left up, it becomes a
                // selection the pane never explains.
                try? await Task.sleep(for: .seconds(2.5))
                self.searchTarget = nil
            }
        }
        }
    }

    // MARK: - Helpers

    // Not private: the General pane in SettingsView+General.swift uses it throughout.
    func caption(_ text: String) -> some View {
        SettingsExplanation(text)
    }

    private func formatted(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func refreshCacheSize() async {
        cacheBytes = await app.imagePipeline?.diskByteCount()
    }

    /// Advanced: caches, hidden things, and what the machine can decode.
    ///
    /// One click away and visibly apart, because none of it is a preference.
    /// Everything here is something you reach for when a poster is wrong, a
    /// library is cluttered, or a file will not play.
    @ViewBuilder
    private var advancedForm: some View {
        advancedGeneralCards

        SettingsCard(
            title: "Artwork cache",
            icon: "photo.stack",
            subtitle: "Kept on disk so browsing survives a relaunch"
        ) {
            LabeledContent("On disk", value: cacheBytes.map(formatted) ?? "—")
            caption("Posters and backdrops are kept compressed on disk so they survive "
                  + "a relaunch. Clearing this only costs a re-download.")
            Button(isClearing ? "Clearing…" : "Clear artwork cache") {
                Task {
                    isClearing = true
                    await app.imagePipeline?.clearAll()
                    await refreshCacheSize()
                    isClearing = false
                }
            }
            .disabled(isClearing)
        }

        thisMacForm
    }
}
