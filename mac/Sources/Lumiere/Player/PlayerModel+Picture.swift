import Foundation
import LumiereKit
import LumierePlayer

/// The sidebar's newer controls: picture, sound, subtitle placement, sync by
/// ear, bookmarks, and a show's saved preset.
@MainActor
extension PlayerModel {

    // MARK: - Picture and sound

    func setPicture(_ picture: PictureAdjustments) async {
        self.picture = picture
        await engineRef?.setPicture(picture)
    }

    func setSoundPreset(_ preset: SoundPreset) async {
        soundPreset = preset
        // App-wide, like Enhance Dialogue: the room you are in, not the film.
        UserDefaults.standard.set(preset.rawValue, forKey: "soundPreset")
        await engineRef?.setSoundPreset(preset)
        say(preset == .flat ? "Sound: Flat" : "Sound: \(preset.title)")
    }

    // MARK: - Subtitle placement

    func setSubtitlePosition(_ percent: Int) async {
        subtitlePosition = max(0, min(100, percent))
        await engineRef?.setSubtitlePosition(subtitlePosition)
    }

    /// An exact size; nil goes back to the named sizes.
    func setSubtitleScale(_ scale: Double?) async {
        subtitleScale = scale.map { max(0.3, min(3, ($0 * 20).rounded() / 20)) }
        await engineRef?.setSubtitleScale(subtitleScale)
    }

    /// Sync by ear: press as the line is spoken, and the line shows now.
    /// `lines` 1 brings the next line forward; -1 holds the last one back.
    func syncSubtitleLine(_ lines: Int) async {
        guard let engine = engineRef else { return }
        let delay = await engine.stepSubtitleTiming(lines: lines)
        subtitleDelay = delay
        say(delay == 0 ? "Subtitles in sync" : String(format: "Subtitles %+.2f s", delay))
        try? await repository.saveSubtitleOffset(delay, itemId: itemId)
    }

    // MARK: - Bookmarks

    func loadBookmarks() { bookmarks = Bookmarks.all(for: itemId) }

    /// ⌘B: marks this moment.
    func addBookmark() {
        let mark = Bookmark(seconds: position, label: "Bookmark \(bookmarks.count + 1)")
        bookmarks.append(mark)
        bookmarks.sort { $0.seconds < $1.seconds }
        Bookmarks.save(bookmarks, for: itemId)
        say("Bookmarked at \(Self.timecode(position))")
    }

    func removeBookmark(_ mark: Bookmark) {
        bookmarks.removeAll { $0.id == mark.id }
        Bookmarks.save(bookmarks, for: itemId)
    }

    func renameBookmark(_ mark: Bookmark, to label: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == mark.id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        bookmarks[index].label = trimmed.isEmpty ? mark.label : trimmed
        Bookmarks.save(bookmarks, for: itemId)
    }

    // MARK: - Show presets

    /// The show, for a preset: the series, or for a file on this Mac its
    /// folder, so a season in one folder shares one preset.
    func presetTitleId() async -> String {
        let item = (try? await repository.entry(id: itemId))?.item
        if let series = item?.seriesId { return series }
        if LocalLibrary.isLocal(itemId: itemId), let folder = item?.parentId { return folder }
        return itemId
    }

    /// Everything set now, saved for every episode of this show.
    func saveShowPreset() async {
        var preset = ShowPreset()
        if subtitleDelay != 0 { preset.subtitleDelay = subtitleDelay }
        if audioDelay != 0 { preset.audioDelay = audioDelay }
        preset.subtitleScale = subtitleScale
        if subtitlePosition != 100 { preset.subtitlePosition = subtitlePosition }
        preset.subtitleStyleId = subtitleStyle.id
        preset.subtitleSizeId = subtitleSize.rawValue
        if !picture.isNeutral { preset.picture = try? JSONEncoder().encode(picture) }
        if soundPreset != .flat { preset.soundPreset = soundPreset.rawValue }
        ShowPreset.save(preset, for: await presetTitleId())
        hasShowPreset = true
        say("Saved for every episode")
    }

    func forgetShowPreset() async {
        ShowPreset.save(nil, for: await presetTitleId())
        hasShowPreset = false
        say("Preset forgotten")
    }

    /// At load, once the engine runs: the app-wide sound, then the show's
    /// preset over it. A delay saved for this one file wins over the show's.
    func applyShowPreset() async {
        loadBookmarks()
        await loadLinkedSubtitles()
        if let raw = UserDefaults.standard.string(forKey: "soundPreset"),
           let saved = SoundPreset(rawValue: raw), saved != .flat {
            soundPreset = saved
            await engineRef?.setSoundPreset(saved)
        }
        guard let preset = ShowPreset.load(for: await presetTitleId()), let engine = engineRef else {
            hasShowPreset = false
            return
        }
        hasShowPreset = true
        if subtitleDelay == 0, let delay = preset.subtitleDelay {
            subtitleDelay = delay
            await engine.setSubtitleDelay(delay)
        }
        if audioDelay == 0, let delay = preset.audioDelay {
            audioDelay = delay
            await engine.setAudioDelay(delay)
        }
        if let id = preset.subtitleStyleId {
            subtitleStyle = .style(id: id)
            await engine.setSubtitleStyle(subtitleStyle)
        }
        if let id = preset.subtitleSizeId {
            subtitleSize = .size(id: id)
            await engine.setSubtitleSize(subtitleSize)
        }
        if let scale = preset.subtitleScale { await setSubtitleScale(scale) }
        if let position = preset.subtitlePosition { await setSubtitlePosition(position) }
        if let data = preset.picture, let saved = try? JSONDecoder().decode(PictureAdjustments.self, from: data) {
            await setPicture(saved)
        }
        if let raw = preset.soundPreset, let saved = SoundPreset(rawValue: raw) {
            soundPreset = saved
            await engine.setSoundPreset(saved)
        }
    }
}
