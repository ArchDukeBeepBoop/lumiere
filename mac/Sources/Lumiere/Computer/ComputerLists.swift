import SwiftUI
import LumiereKit

/// Recent and Folders on the On This Computer page, as grouped lists in the
/// manner of Finder's sidebar and System Settings: one rounded panel, rows
/// divided by hairlines, the icon in a tinted square.
struct ComputerRecentList: View {
    let recents: [URL]
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                ComputerSectionTitle(title: "Recent")
                Spacer()
                if !recents.isEmpty {
                    Button("Clear") { OpenRecents.clear() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.accent)
                        .padding(.horizontal, Theme.Space.shelfInset)
                }
            }
            if recents.isEmpty {
                ComputerEmptyRow(
                    icon: "clock",
                    text: Preference.remembersRecentFiles.value
                        ? "Files and streams you open appear here."
                        : "Recent files are off in Settings › On This Computer."
                )
            } else {
                ComputerGroup {
                    ForEach(Array(recents.prefix(12).enumerated()), id: \.element) { index, url in
                        if index > 0 { Divider().padding(.leading, 52) }
                        ComputerRow(
                            icon: Self.icon(for: url),
                            title: Self.title(for: url),
                            detail: Self.detail(for: url),
                            isMissing: url.isFileURL && !FileManager.default.fileExists(atPath: url.path),
                            previewURL: url.isFileURL && !url.hasDirectoryPath ? url : nil,
                            action: { open(url) }
                        )
                        .contextMenu {
                            if url.isFileURL {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            } else {
                                Button("Copy Address") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                }
                            }
                            Button("Remove from Recent") { OpenRecents.forget(url) }
                        }
                    }
                }
            }
        }
    }

    static func icon(for url: URL) -> String {
        if !url.isFileURL { return "antenna.radiowaves.left.and.right" }
        if url.hasDirectoryPath { return "folder.fill" }
        if StreamPlaylist.isPlaylist(url) { return "list.bullet" }
        return LocalLibrary.audioExtensions.contains(url.pathExtension.lowercased()) ? "music.note" : "film"
    }

    static func title(for url: URL) -> String {
        url.isFileURL ? url.deletingPathExtension().lastPathComponent : (url.host ?? url.absoluteString)
    }

    static func detail(for url: URL) -> String {
        guard url.isFileURL else { return url.absoluteString }
        return (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

struct ComputerFolderList: View {
    let folders: [LibraryRecord]
    let isAdding: Bool
    let open: (LibraryRecord) -> Void
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                ComputerSectionTitle(title: "Folders")
                Spacer()
                Button(isAdding ? "Reading…" : "Add Folder…", action: add)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(isAdding)
                    .padding(.horizontal, Theme.Space.shelfInset)
            }
            if folders.isEmpty {
                ComputerEmptyRow(icon: "folder.badge.plus",
                                 text: "Add a folder to browse it here, with its files in order and Next always ready.")
            } else {
                ComputerGroup {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        if index > 0 { Divider().padding(.leading, 52) }
                        ComputerRow(
                            icon: "folder.fill", title: folder.name,
                            detail: "\(folder.itemCount ?? 0) files",
                            isMissing: false, action: { open(folder) }
                        )
                    }
                }
            }
        }
    }
}

/// The rounded panel a group of rows sits in.
struct ComputerGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.Palette.surface.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.Palette.hairline))
            .padding(.horizontal, Theme.Space.shelfInset)
    }
}

struct ComputerRow: View {
    let icon: String
    let title: String
    let detail: String
    let isMissing: Bool
    /// A file to show a Quick Look still for, in place of the icon.
    var previewURL: URL? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                if let previewURL {
                    RecentThumbnailView(url: previewURL, fallbackIcon: icon, isMissing: isMissing)
                } else {
                    Image(systemName: icon)
                        .font(Theme.Glyph.md(.medium))
                        .foregroundStyle(Theme.Palette.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Theme.Palette.accent.opacity(isMissing ? 0.35 : 1),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Font.cardTitleLarge).lineLimit(1)
                        .foregroundStyle(isMissing ? Theme.Palette.textMuted : Theme.Palette.textPrimary)
                    Text(isMissing ? "Not found — is its drive connected?" : detail)
                        .font(Theme.Font.caption).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm)
            .background(hovering ? Theme.Palette.surfaceRaised.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isMissing ? "\(title), not found" : "\(title), \(detail)")
    }
}

struct ComputerEmptyRow: View {
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.shelfInset)
    }
}

/// Open Address…: a stream or a playlist link.
struct OpenAddressSheet: View {
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var url: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), StreamPlaylist.isStream(url) else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Open Address").font(Theme.Font.sectionHeader)
            Text("A stream (http, https, rtsp, rtmp, udp, srt) or an .m3u playlist of channels.")
                .font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
            TextField("https://example.com/live.m3u8", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open", action: submit).keyboardShortcut(.defaultAction).disabled(url == nil)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 460)
        .glassSheet()
        .onAppear {
            if let clip = NSPasteboard.general.string(forType: .string),
               let url = URL(string: clip.trimmingCharacters(in: .whitespacesAndNewlines)),
               StreamPlaylist.isStream(url) { text = url.absoluteString }
        }
    }

    private func submit() {
        guard let url else { return }
        dismiss()
        open(url)
    }
}
