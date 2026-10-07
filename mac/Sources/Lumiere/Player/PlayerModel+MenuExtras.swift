import AppKit
import LumiereKit
import LumierePlayer

/// What the menu bar can do that the player's own controls do not offer.
@MainActor
extension PlayerModel {

    /// Remembered for this file, as the subtitle offset is: audio drift is a
    /// property of one file, and fixing it again every time it is opened is
    /// the chore this removes. Zero forgets it.
    func setAudioDelay(_ seconds: Double) async {
        audioDelay = max(-10, min(10, (seconds * 10).rounded() / 10))
        await engineRef?.setAudioDelay(audioDelay)
        AudioOffsets.save(audioDelay, itemId: itemId)
        say(audioDelay == 0 ? "Audio in sync" : String(format: "Audio %+.1f s", audioDelay))
    }

    /// Puts back this file's remembered audio offset, once the engine runs.
    func restoreAudioDelay() async {
        // And the output, if one was chosen and is still connected.
        if let uid = UserDefaults.standard.string(forKey: "audioDeviceUID"),
           AudioOutputs.all().contains(where: { $0.uid == uid }) {
            audioDeviceUID = uid
            await engineRef?.setAudioDevice(uid: uid)
        }
        let saved = AudioOffsets.saved(itemId: itemId)
        guard saved != 0 else { return }
        audioDelay = saved
        await engineRef?.setAudioDelay(saved)
    }

    /// The frame on screen to the clipboard, via a file mpv writes.
    func copyFrame() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumiere-frame-\(UUID().uuidString).png")
        guard await engineRef?.saveScreenshot(to: url) == true,
              let image = NSImage(contentsOf: url) else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        try? FileManager.default.removeItem(at: url)
        NSSound(named: "Pop")?.play()
        say("Frame copied")
        Diagnostics.log("[player] frame copied")
    }

    func nudgeAudioDelay(_ direction: Double) async {
        await setAudioDelay(audioDelay + 0.1 * direction)
    }

    /// A quarter step, within the range the speed keys already use.
    func nudgeSpeed(_ delta: Double) async {
        await setPlaybackSpeed(min(4, max(0.25, playbackSpeed + delta)))
    }

    /// A, then B, then off — one key, as VLC and mpv have it. A B before its A
    /// is taken as the new A, so the two ends are never reversed.
    func stepABLoop() async {
        switch abLoop {
        case (nil, _):
            abLoop = (position, nil)
            say("Loop from \(Self.timecode(position))")
        case (let a?, nil) where position > a:
            abLoop = (a, position)
            await engineRef?.setABLoop(a: a, b: position)
            say("Looping \(Self.timecode(a))–\(Self.timecode(position))")
        default:
            abLoop = (nil, nil)
            await engineRef?.setABLoop(a: nil, b: nil)
            say("Loop cleared")
        }
    }

    /// Remembered for the next file: an output is chosen for the room, not
    /// for a film. Cleared by choosing System Output.
    func setAudioDevice(_ device: AudioOutputs.Device?) async {
        audioDeviceUID = device?.uid
        UserDefaults.standard.set(device?.uid, forKey: "audioDeviceUID")
        await engineRef?.setAudioDevice(uid: device?.uid)
        say("Sound: " + (device?.name ?? "System output"))
    }

    /// Puts a word on screen briefly. See `PlayerOSD`.
    func say(_ text: String) { osd = (text, Date()) }

    func toggleFlip(horizontal: Bool) async {
        await setFlip(
            horizontal: horizontal ? !flipHorizontal : flipHorizontal,
            vertical: horizontal ? flipVertical : !flipVertical
        )
    }

    /// Saves the frame to Pictures › Lumiere, named after the title and the
    /// moment, and plays the system's shutter-like sound so it is known to
    /// have happened without anything drawn over the picture.
    func saveScreenshot() async {
        guard let pictures = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first else { return }
        let folder = pictures.appendingPathComponent("Lumiere", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Self.timecode(position).replacingOccurrences(of: ":", with: ".")
        let name = (title.isEmpty ? "Lumiere" : title)
            .replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent("\(name) \(stamp).png")
        let saved = await engineRef?.saveScreenshot(to: url) ?? false
        Diagnostics.log("[player] screenshot \(saved ? "saved" : "failed") — \(url.lastPathComponent)")
        if saved { NSSound(named: "Pop")?.play(); say("Screenshot saved") } else { NSSound.beep() }
    }

    /// Opens a subtitle file from disk and selects it.
    func addSubtitleFile(_ url: URL) async {
        let added = await engineRef?.addSubtitle(
            url: url, title: url.deletingPathExtension().lastPathComponent, language: ""
        ) ?? false
        Diagnostics.log("[player] subtitle file \(added ? "added" : "refused") — \(url.lastPathComponent)")
        if added { await refreshTracks() }
    }
}
