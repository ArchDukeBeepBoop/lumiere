import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LumiereKit

/// Pick artwork from what the server's metadata providers offer, or upload a file
/// from this Mac directly.
///
/// Provider suggestions come from Jellyfin, which already holds whatever provider
/// credentials it is configured with — so there is no API key in this app and no
/// direct call to TMDB or anyone else for this path. A manual upload exists because
/// Thumb images specifically are a real gap: most scrapers populate Primary and
/// Backdrop but never Thumb, which is exactly the image Continue Watching wants and
/// so often has nothing to show. Either way, applying one writes it on the server,
/// so every other client sees the same artwork rather than this Mac having a
/// private opinion.
struct ArtworkPickerSheet: View {
    let itemId: String
    let client: JellyfinClient
    let onDone: (Bool) -> Void

    @State private var imageType: JellyfinImageURL.ImageKind = .primary
    @State private var options: [RemoteImageOption] = []
    @State private var isLoading = true
    @State private var applying: String?
    @State private var errorMessage: String?
    /// Set when the artwork changed but the sheet stayed open to explain something.
    @State private var changeApplied = false
    /// Whether to freeze the item so refreshes stop touching its artwork.
    ///
    /// Off by default, and that is a deliberate change from how this started.
    ///
    /// Deleting alone does not keep it deleted — Jellyfin re-downloads on the next
    /// image refresh, which is how a poster you got rid of last week is back today.
    /// But the only lock Jellyfin offers here is `LockData`, which freezes the
    /// *whole item*: no new cast, no better synopsis, no corrected air date, ever.
    /// Defaulting that on meant every artwork change anyone made quietly froze the
    /// item forever, which is a much larger promise than "keep this picture".
    @State private var keepsArtwork = false
    /// Whether an image you upload yourself is frozen automatically.
    ///
    /// On by default, and only for uploads. An image chosen from a provider can be
    /// fetched again; one off this Mac cannot — the server has no idea where it came
    /// from, so a refresh that discards it discards it for good. That asymmetry is
    /// the whole reason this is separate from the toggle below, which stays manual
    /// for provider picks.
    @AppStorage("locksUploadedArtwork") private var locksUploadedArtwork = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Choose \(imageType.rawValue)")
                    .font(Theme.Font.sectionHeader)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Button("Cancel") { onDone(changeApplied) }
                .keyboardShortcut(.cancelAction)
            }

            HStack {
                Picker("", selection: $imageType) {
                    Text("Poster").tag(JellyfinImageURL.ImageKind.primary)
                    Text("Thumb").tag(JellyfinImageURL.ImageKind.thumb)
                    Text("Backdrop").tag(JellyfinImageURL.ImageKind.backdrop)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                .onChange(of: imageType) { Task { await load() } }

                Spacer()

                // Removing is its own act, not a kind of replacing. A wrong poster
                // overwritten is still there if the next scrape prefers the
                // original; a wrong poster deleted is gone.
                Button("Remove") { Task { await removeCurrent() } }
                    .foregroundStyle(Theme.Palette.danger)
                    .disabled(applying != nil)

                Button("Upload from Mac…") { uploadFromDisk() }
            }

            Toggle("Freeze artwork I upload from this Mac", isOn: $locksUploadedArtwork)
                .font(Theme.Font.caption)
                .disabled(applying != nil)

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Freeze this item so refreshes cannot change it", isOn: $keepsArtwork)
                    .font(Theme.Font.caption)
                    // On the Toggle, not on the Spacer beside it, which is where
                    // this modifier used to sit — so it stayed live mid-apply.
                    .disabled(applying != nil)
                Text("The server has no lock for images alone. This freezes the whole "
                   + "item: it will stop receiving new cast, synopsis and ratings too.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                ProgressView("Asking the server's providers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.danger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if options.isEmpty {
                // Worth distinguishing from a failure: the providers answered and had
                // nothing, which usually means the item is not matched on the server.
                Text("No artwork offered. The server may not have matched this title "
                   + "to a provider yet — a metadata refresh often fixes that.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Space.md)],
                              spacing: Theme.Space.lg) {
                        ForEach(options) { option in
                            optionCell(option)
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 620, height: 520)
        .background(Theme.Palette.canvas)
        .task { await load() }
    }

    private func optionCell(_ option: RemoteImageOption) -> some View {
        Button {
            Task { await apply(option) }
        } label: {
            VStack(spacing: Theme.Space.xs) {
                // Loaded straight from the provider URL the server handed back rather
                // than through ImagePipeline: these are one-off previews of images not
                // yet on the server, so they have no item id or tag to cache against.
                AsyncImage(url: option.url.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Rectangle().fill(Theme.Palette.surface)
                    }
                }
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.poster))
                .overlay {
                    if applying == option.url {
                        ProgressView().controlSize(.small)
                    }
                }

                Text(option.providerName ?? "Unknown")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let dimensions = option.dimensions {
                    Text(dimensions)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(applying != nil)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            options = try await client.remoteImages(itemId: itemId, type: imageType.rawValue)
        } catch {
            errorMessage = ConnectionState.message(for: error)
        }
    }

    /// Deletes whatever image is currently set for this type.
    private func removeCurrent() async {
        applying = "remove"
        defer { applying = nil }
        do {
            try await client.deleteImage(itemId: itemId, type: imageType.rawValue)
            if await lockIfRequested() { onDone(true) }
        } catch {
            errorMessage = ConnectionState.message(for: error)
        }
    }

    /// Freezes the item's metadata and images against future refreshes.
    ///
    /// `LockData` rather than a per-image lock, because Jellyfin has no per-image
    /// lock — its `LockedFields` list covers text only. The cost is real and worth
    /// saying out loud: a locked item stops picking up new cast or a better
    /// synopsis too. For a collection, whose metadata you wrote by hand anyway,
    /// that is a trade most people want.
    /// - Returns: whether the sheet may close. A failure keeps it open, which is
    ///   the only way the message below is ever read: every caller ran `onDone(true)`
    ///   on the next line, nilling the presenting binding, so the explanation was
    ///   written to a view that was already being torn down. A 403 looked exactly
    ///   like success and the old poster returned on the next refresh.
    @discardableResult
    private func lockIfRequested() async -> Bool {
        guard keepsArtwork else { return true }
        do {
            try await client.updateItem(itemId: itemId, edit: ItemEdit(lockAll: true))
            return true
        } catch {
            // Said out loud rather than swallowed. A 403 here used to close the
            // sheet exactly like success, having told the user refreshes would stop
            // changing the artwork — and then the old poster came back.
            errorMessage = "The image was set, but freezing it failed: "
                         + ConnectionState.message(for: error)
            // The picture did change, so closing must still report it.
            changeApplied = true
            return false
        }
    }

    private func apply(_ option: RemoteImageOption) async {
        guard let url = option.url else { return }
        applying = url
        defer { applying = nil }
        do {
            try await client.applyRemoteImage(itemId: itemId, url: url, type: imageType.rawValue)
            if await lockIfRequested() { onDone(true) }
        } catch {
            errorMessage = ConnectionState.message(for: error)
        }
    }

    /// A native Open panel rather than a drop zone: this sheet already has a
    /// clear "choose one" shape, and reusing it needs no new UI idiom.
    private func uploadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else {
            errorMessage = "Couldn't tell what kind of image file that was."
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Couldn't read that file."
            return
        }

        applying = url.path
        Task {
            defer { applying = nil }
            do {
                try await client.uploadImage(
                    itemId: itemId, type: imageType.rawValue, data: data, mimeType: mimeType
                )
                // An uploaded image is the one kind the server cannot get back. It
                // is frozen unless you have turned that off, and the toggle below
                // is set to match so the state is visible rather than implied.
                if locksUploadedArtwork { keepsArtwork = true }
                await lockIfRequested()
                onDone(true)
            } catch {
                errorMessage = ConnectionState.message(for: error)
            }
        }
    }
}
