import AppKit
import UniformTypeIdentifiers
import LumiereKit

/// Lumiere as the Mac's player for video and audio.
///
/// Asked once, at a launch after this arrived, and from Settings › On This
/// Computer any time after. Never claimed silently: the Info.plist ranks every
/// type Alternate, so nothing changes until someone says yes.
@MainActor
enum DefaultPlayer {
    private static let askedKey = "askedDefaultPlayer"

    /// Every type Lumiere opens, one per extension, without repeats.
    static var types: [UTType] {
        var seen = Set<String>()
        return LocalLibrary.playableExtensions.sorted()
            .compactMap { UTType(filenameExtension: $0) }
            .filter { !$0.isDynamic && seen.insert($0.identifier).inserted }
    }

    /// Whether Lumiere opens most of them now.
    static var isDefault: Bool {
        let me = Bundle.main.bundleURL.standardizedFileURL
        let mine = types.filter {
            NSWorkspace.shared.urlForApplication(toOpen: $0)?.standardizedFileURL == me
        }
        return !types.isEmpty && mine.count * 2 >= types.count
    }

    /// Makes Lumiere the default for every type; returns how many took.
    @discardableResult
    static func makeDefault() async -> Int {
        var done = 0
        for type in types {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
                done += 1
            } catch {
                Diagnostics.log("[default-player] \(type.identifier): \(error.localizedDescription)")
            }
        }
        return done
    }

    /// The one-time question. Skipped for a build run from anywhere but
    /// Applications — a development copy must not take the Mac's files.
    static func askOnce(report: (String) -> Void) async {
        guard !UserDefaults.standard.bool(forKey: askedKey),
              Bundle.main.bundleURL.path.hasPrefix("/Applications/"),
              !isDefault
        else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        let alert = NSAlert()
        alert.messageText = "Make Lumiere your video and audio player?"
        alert.informativeText = "Double-clicking a film, an episode or a song in Finder will open it here. You can change this later in Settings › On This Computer."
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let done = await makeDefault()
        report(done > 0 ? "Lumiere now opens video and audio files." : "macOS didn’t accept the change. Try again from Settings › On This Computer.")
    }
}
