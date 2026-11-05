import AppKit
import SwiftUI

/// Where the server keeps its pictures and scrubbing previews — gigabytes,
/// where the library itself is megabytes — chosen here and handed to the
/// server as `-cache`. The server moves what it already has to the new
/// folder by itself, and uses its own folder for a run when the chosen one's
/// drive is unplugged.
enum PictureFolder {
    static let key = "cachePath"
}

struct PictureFolderSection: View {
    let server: ServerProcess
    @AppStorage(PictureFolder.key) private var folder = ""

    var body: some View {
        Section {
            LabeledContent("Pictures and previews") {
                HStack {
                    Text(folder.isEmpty ? "This Mac" : URL(fileURLWithPath: folder).lastPathComponent)
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(folder.isEmpty ? "Inside the server's own folder on this Mac" : folder)
                    if !folder.isEmpty { Button("Use This Mac") { set("") } }
                    Button("Choose Folder…") { choose() }
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Artwork and scrubbing previews, several gigabytes. Put them beside your media — "
                 + "the server moves what it has there by itself, in the background. While that drive "
                 + "is unplugged the server still starts, without those pictures. The library stays on this Mac. "
                 + "Changing it restarts the server.")
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where the server keeps its pictures and scrubbing previews."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        set(url.path)
    }

    /// An argument to the server, so it takes a restart to apply.
    private func set(_ path: String) {
        folder = path
        guard server.state == .running else { return }
        server.note(path.isEmpty ? "pictures kept on this Mac" : "pictures folder set")
        Task { await server.restart() }
    }
}
