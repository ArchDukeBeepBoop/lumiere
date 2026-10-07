import SwiftUI
import LumiereKit

/// The General pane: appearance, home layout, metadata provider keys, the hidden
/// shelf list, offline artwork and title style.
///
/// Split out of SettingsView.swift, which had drifted well past the project's
/// 300-line limit — this pane alone was half the file.
extension SettingsView {
    @ViewBuilder
    var generalForm: some View {
        SettingsCard(title: "Appearance", icon: "paintbrush") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: appearance) { appearance.apply() }
            caption(appearance.explanation)

            Divider().padding(.vertical, Theme.Space.xs)

            ThemePicker()
            ChromeStylePicker()

            Divider().padding(.vertical, Theme.Space.xs)

            AppIconPicker()
            GlassBackgroundRows(isGlass: $isGlass, opacity: $glassOpacity)
        }
    }

    /// The Home pane's own settings: layout, what shows, and in what order.
    @ViewBuilder
    var homeForm: some View {
        SettingsCard(title: "Home", icon: "house") {
            Picker("Layout", selection: $homeLayout) {
                ForEach(HomeLayout.allCases) { Text($0.title).tag($0) }
            }
            caption(homeLayout.explanation)
            HomeBackdropToggles()

            Divider().padding(.vertical, Theme.Space.xs)

            Toggle("Show every shelf", isOn: $showsAllShelves)
            caption("The home screen stops at seven shelves and says how many it "
                  + "is holding back. This shows them all. Empty shelves never "
                  + "count either way.")

            Toggle("Count loose videos as new", isOn: $latestIncludesVideos)
            caption("A Latest row includes files that are neither a film nor an "
                  + "episode — which is everything in a folder library such as "
                  + "3D or My Videos. Off, those rows show only what was "
                  + "catalogued as a film.")

            UpNextToggle()
            ChangeCheckPicker()
            CollectionDefaultOrderPicker()
        }
        .resettable(SettingsDefaults.home)

        HomeOrderCard(libraries: app.libraries) { app.reapplyLibraryOrder() }
    }

    /// The keys that let titles be named and fixed. Library, not Look: they
    /// decide what the library knows, not how it is drawn.
    @ViewBuilder
    var metadataForm: some View {
        SettingsCard(
            title: "Metadata Providers",
            icon: "key",
            subtitle: "Optional. Your server's own providers are used first"
        ) {
            caption("The server already scrapes with its own provider keys, and anything "
                  + "it fetches benefits every client. Keys here are for looking a "
                  + "title up from Lumiere when the server's match is wrong — most "
                  + "often with anime.")

            ForEach(MetadataProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(provider.title)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        // Whether a key exists, never the key itself. Once stored, a
                        // credential has no business being read back into a view.
                        if MetadataCredentials.hasKey(for: provider) {
                            Text("Saved")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.success)
                            Button("Remove") {
                                MetadataCredentials.delete(provider)
                                providerKeys[provider.rawValue] = ""
                            }
                        }
                    }

                    HStack(spacing: Theme.Space.sm) {
                        SecureField(
                            provider.credentialLabel,
                            text: Binding(
                                get: { providerKeys[provider.rawValue] ?? "" },
                                set: { providerKeys[provider.rawValue] = $0 }
                            )
                        )
                        .focused($focusedKeyField, equals: provider.rawValue)
                        .onSubmit { save(provider) }

                        // Visible only with something to save. A field whose only
                        // way to commit is the Return key is a field that loses
                        // what you typed, and nothing on screen said so.
                        if !(providerKeys[provider.rawValue] ?? "").isEmpty {
                            Button("Save") { save(provider) }
                                .font(Theme.Font.caption)
                        }
                    }

                    caption(provider.helpText)
                }
                .padding(.vertical, 2)
            }
            // Leaving a field commits it. Focus moving to the next field, to
            // another control, or out of the window entirely all land here.
            .onChange(of: focusedKeyField) { previous, _ in
                guard let previous,
                      let provider = MetadataProvider(rawValue: previous) else { return }
                save(provider)
            }
            // And closing the window while the cursor is still in the field,
            // which is the one way out that never changes focus.
            .onDisappear {
                for provider in MetadataProvider.allCases { save(provider) }
            }
        }

        // Directly beneath the keys, because the key is what makes it possible
        // and the relationship is otherwise invisible.
        ServerMetadataCard(app: app)
    }

    /// What a title and a thumbnail say. Appearance, so: Look.
    ///
    /// These two cards were rendered from `advancedGeneralCards`, three
    /// categories away from the pane that claims to hold "appearance, titles,
    /// and what appears on your shelves" — and Settings search, which files them
    /// under Look, sent you to a pane that did not contain them.
    @ViewBuilder
    var titleCards: some View {
        SettingsCard(title: "Titles", icon: "textformat") {
            Picker("Show", selection: $titleStyle) {
                ForEach(TitleStyle.allCases) { Text($0.title).tag($0) }
            }
            caption(titleStyle.explanation)
            UnwatchedMarkerSettings()
        }

        SettingsCard(title: "Episode stills", icon: "photo.on.rectangle") {
            Toggle("Use the show's artwork", isOn: $unifiedEpisodeArt)
            caption("Gives every episode of a show the same picture — its backdrop — "
                  + "rather than its own scraped image. A season then reads as one "
                  + "thing instead of a strip of unrelated frames, and it is the "
                  + "answer for shows whose provider has no per-episode stills and "
                  + "hands back the same image twelve times over. Real stills your "
                  + "server actually holds are used either way.")
        }
    }
}
