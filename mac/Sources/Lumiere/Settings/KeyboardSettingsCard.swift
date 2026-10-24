import SwiftUI
import AppKit

/// Settings › Playback › Keyboard: the player's letter keys, changeable by
/// pressing the new key — the way System Settings records a shortcut.
struct KeyboardSettingsCard: View {
    @State private var recording: PlayerKeyBinding?
    @State private var monitor: Any?
    @State private var note: String?
    /// Bumped on every change, so the rows reread their keys.
    @State private var revision = 0

    var body: some View {
        SettingsCard(title: "Keyboard", icon: "keyboard",
                     subtitle: "The player’s letter keys") {
            ForEach(PlayerKeyBinding.allCases) { binding in
                SettingsRow(label: binding.title) {
                    Button { start(binding) } label: {
                        Text(recording == binding ? "Press a key…" : PlayerKeyBinding.display(binding.key))
                            .font(Theme.Font.timecode)
                            .frame(minWidth: 90)
                    }
                    .id("\(binding.id)-\(revision)")
                    .accessibilityLabel("\(binding.title): \(PlayerKeyBinding.display(binding.key)). Click, then press a new key.")
                }
            }
            if let note {
                Text(note).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            HStack {
                Button("Reset to Defaults") {
                    PlayerKeyBinding.resetAll()
                    note = nil
                    revision += 1
                }
                Button("All Shortcuts…") { ShortcutsWindow.show() }
            }
            SettingsNote("Space, the arrows, the number keys and Esc stay as they are. A key already in use swaps with the one you replace.")
        }
        .onDisappear(perform: stop)
    }

    private func start(_ binding: PlayerKeyBinding) {
        stop()
        recording = binding
        note = "Press the new key for \(binding.title), or Esc to cancel."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stop() }
            if event.keyCode == 53 { note = nil; return nil }
            guard !event.modifierFlags.contains(.command),
                  let typed = event.charactersIgnoringModifiers?.lowercased(),
                  PlayerKeyBinding.isAllowed(typed)
            else {
                note = "That key can’t be used — choose a letter or a punctuation key."
                return nil
            }
            let displaced = PlayerKeyBinding.binding(for: typed).flatMap { $0 == binding ? nil : $0 }
            binding.bind(typed)
            note = displaced.map { "\($0.title) moved to \(PlayerKeyBinding.display($0.key))." }
            revision += 1
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}
