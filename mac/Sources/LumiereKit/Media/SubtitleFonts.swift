import Foundation
import CoreText

/// Fonts the user has added for subtitles, and where they live.
///
/// The presets in `SubtitleStyle` name three faces that ship in the bundle, chosen
/// to sit near the house styles people recognise. That covers the common case and
/// nothing else: a fansub script asks for whatever the group typeset it in, and a
/// subtitle rendered in a substituted face is not the subtitle that was written —
/// spacing, weight and line breaks all move. libass will use any font it is
/// pointed at, so the only thing missing was somewhere to put them.
///
/// Application Support rather than Caches: these are the user's files, added
/// deliberately, and the system may empty Caches whenever it likes.
public enum SubtitleFonts {

    /// Extensions libass can actually load. Anything else is refused at import
    /// rather than copied in and silently ignored — a font that does not work
    /// looks identical to a setting that does not work.
    public static let allowedExtensions: Set<String> = [
        "ttf", "otf", "ttc", "otc", "pfb", "dfont"
    ]

    public static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Lumiere/Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true
        )
        return base
    }

    /// Copies the bundled faces in, once, so one directory holds everything.
    ///
    /// mpv takes a single `sub-fonts-dir`, so pointing it at the user's folder
    /// would otherwise make the three presets resolve to nothing the moment a font
    /// was added — the setting would appear to break itself. Seeding means the
    /// directory is always the complete set. Existing files are left alone, so a
    /// user who deletes a bundled face keeps it deleted.
    public static func seed(from bundle: Bundle = .main) {
        guard let source = bundle.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: source, includingPropertiesForKeys: nil
              ) else { return }
        let marker = directory.appendingPathComponent(".seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }

        for file in files where allowedExtensions.contains(file.pathExtension.lowercased()) {
            let destination = directory.appendingPathComponent(file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: file, to: destination)
            }
        }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    /// Every font file added, by filename.
    public static func installed() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                == .orderedAscending }
    }

    /// Copies a font in, returning where it landed.
    ///
    /// A copy, not a reference. A font chosen from a Downloads folder that is later
    /// tidied away would otherwise take the subtitle styling with it, weeks after
    /// the choice was made and with nothing connecting the two.
    @discardableResult
    public static func install(from source: URL) throws -> URL {
        guard allowedExtensions.contains(source.pathExtension.lowercased()) else {
            throw SubtitleFontError.unsupported(source.lastPathComponent)
        }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    public static func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// The family names inside a font file, which is what libass is asked for.
    ///
    /// Read from the file rather than guessed from its name, because the two often
    /// disagree — `NotoSansJP-Regular.otf` is the family "Noto Sans JP", and asking
    /// for the filename gets a silent fallback to the default face, which is the
    /// failure this whole feature exists to remove.
    public static func familyNames(in url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor] else { return [] }
        var names: [String] = []
        for descriptor in descriptors {
            let value = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute)
            if let name = value as? String, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Every family available to pick, bundled and added, without duplicates.
    public static func availableFamilies(bundled: [String]) -> [String] {
        var families = bundled
        for url in installed() {
            for name in familyNames(in: url) where !families.contains(name) {
                families.append(name)
            }
        }
        return families
    }
}

public enum SubtitleFontError: LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let name):
            return "\(name) is not a font file Lumiere can use. "
                 + "TrueType and OpenType fonts (.ttf, .otf, .ttc) work."
        }
    }
}
