import SwiftUI
import LumiereKit

/// The Advanced cards of the General pane. Split from SettingsView+General.swift
/// for the 300-line rule.
extension SettingsView {
    /// The destructive and the diagnostic, kept out of Look.
    ///
    /// Forgetting watch history, clearing a cache and bulk-fetching artwork are
    /// not preferences — they are things you do once, when something is wrong.
    /// Sitting them beside "Appearance" made the pane a wall and buried the four
    /// settings anybody actually changes.
    @ViewBuilder
    var advancedGeneralCards: some View {
        SettingsCard(
            title: "Hidden from Shelves",
            icon: "eye.slash",
            subtitle: "Items kept out of Continue Watching and Next Up",
            accessory: {
                if !hiddenEntries.isEmpty {
                    Button("Forget All") { isConfirmingClearHidden = true }
                        .font(Theme.Font.caption)
                }
            }
        ) {
            if hiddenEntries.isEmpty {
                caption("Nothing hidden. Right-click anything on Continue Watching or "
                      + "Next Up to remove it from those shelves — it stays in your "
                      + "library and is never marked watched on the server.")
            } else {
                ForEach(hiddenEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.item.name)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            if let series = entry.item.seriesName {
                                Text(series)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.textMuted)
                            }
                        }
                        Spacer()
                        Button("Unhide") {
                            Task {
                                await app.unhideFromShelves(itemId: entry.item.id)
                                await loadHidden()
                            }
                        }
                        // Unhiding puts it straight back on the shelf it was hidden
                        // from, which is often not what was wanted. Erasing the
                        // history removes the reason it was ever on one.
                        Button("Forget") {
                            Task {
                                await app.clearWatchHistory(itemId: entry.item.id)
                                await loadHidden()
                            }
                        }
                        .labelledHelp("Erase this item's watch history. The file is untouched.")
                    }
                }
            }
        }
        .task { await loadHidden() }

        hiddenCollectionsCard
        // Confirmed rather than immediate: this erases real watch history, and there
        // is no undo for it.
        .confirmationDialog(
            "Forget these items?",
            isPresented: $isConfirmingClearHidden,
            titleVisibility: .visible
        ) {
            Button("Forget \(hiddenEntries.count) Items", role: .destructive) {
                Task {
                    await app.clearHiddenWatchHistory()
                    await loadHidden()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Says what it does to *history* and what it does not do to files,
            // because those are the two things anyone hesitates over here.
            Text("Erases their watch history — resume position and watched state — "
               + "on this Mac and on your server, then empties this list. Nothing is "
               + "deleted from disk and every title stays in your library, playable "
               + "from the beginning.")
        }

        SettingsCard(title: "Home Screen Timing", icon: "stopwatch",
                     subtitle: "How long the last few rebuilds took, and what set them off") {
            HomeTimingsRows()
        }

        SettingsCard(title: "Offline Artwork", icon: "arrow.down.circle") {
            if let progress = app.prefetchProgress {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.Palette.accent)
                    HStack {
                        Text("\(progress.done) of \(progress.total) · \(progress.bytesCached / 1_000_000) MB cached")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                        Spacer()
                        Button("Stop") { Task { await app.cancelPrefetch() } }
                    }
                }
            } else {
                Button("Download All Artwork") {
                    Task { await app.prefetchArtwork(widths: ArtworkPrefetcher.uiWidths, scale: 2) }
                }
                caption("Fetches every poster in your library so browsing works with "
                      + "the server switched off. One at a time, to leave the server "
                      + "alone — a large library takes a while, and you can keep using "
                      + "Lumiere while it runs.")
            }
        }

        SettingsCard(title: "Missing Artwork", icon: "wand.and.stars") {
            if let progress = app.artworkFetchProgress {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.Palette.accent)
                    Text(progress.currentTitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                    HStack {
                        Text("\(progress.done) of \(progress.total) · \(progress.applied) found")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                        Spacer()
                        Button("Stop") { Task { await app.cancelArtworkFetch() } }
                    }
                }
            } else {
                Button("Find Missing Posters") {
                    Task { await app.fetchArtwork(missingOnly: true) }
                }
                caption("Goes through every film, series and collection with no poster "
                      + "and takes the best one your server's providers offer — rather "
                      + "than choosing each by hand. Runs one at a time so the server "
                      + "stays responsive, and you can keep using Lumiere meanwhile. "
                      + "Right-click any title and choose Artwork to override a pick.")

                Button("Replace All Posters…") { isConfirmingReplaceArtwork = true }
                caption("Re-fetches artwork for everything, not only what is missing — "
                      + "for a library whose posters are wrong rather than absent.")
            }
        }
        // Confirmed, because unlike the missing-only pass this overwrites artwork
        // that is already there, including anything chosen by hand.
        .confirmationDialog(
            "Replace all posters?",
            isPresented: $isConfirmingReplaceArtwork,
            titleVisibility: .visible
        ) {
            Button("Replace All", role: .destructive) {
                Task { await app.fetchArtwork(missingOnly: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every film, series and collection gets whichever poster your "
               + "server's providers rate highest, discarding posters you picked "
               + "yourself. No files are touched and nothing is deleted.")
        }

    }

    /// Stores whatever is in a provider's field, if anything.
    ///
    /// Called from four places, and that is the fix rather than an accident:
    /// Return, the Save button, focus leaving the field, and the pane closing.
    /// It used to be reachable only by pressing Return, so a key that was typed
    /// and then clicked away from was discarded — `providerKeys` is view state
    /// and dies with the view. Nothing on screen said the key had not been kept,
    /// because from the field's point of view nothing had gone wrong.
    ///
    /// Empty is not a save: `MetadataCredentials.store` treats an empty string as
    /// a deletion, and running this over every provider on disappear would
    /// otherwise wipe the keys belonging to the fields nobody touched.
    func save(_ provider: MetadataProvider) {
        guard let value = providerKeys[provider.rawValue],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        try? MetadataCredentials.store(value, for: provider)
        // Cleared from memory once stored: the Keychain is the only place it lives.
        providerKeys[provider.rawValue] = ""
    }

    func loadHidden() async {
        hiddenEntries = await app.hiddenShelfEntries()
    }
}
