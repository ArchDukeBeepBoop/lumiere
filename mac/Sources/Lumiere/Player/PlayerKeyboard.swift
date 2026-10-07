import SwiftUI
import AppKit
import LumiereKit

/// A key the player responds to.
enum PlayerKey: Sendable, Equatable {
    case space, k, j, l, m, f
    case left, right, up, down
    case shiftLeft, shiftRight
    case optionLeft, optionRight
    case home, end
    case comma, period
    /// Subtitle timing, on mpv's own letters: z shows them earlier, Z later.
    case subtitleEarlier, subtitleLater
    /// The way out. The player is a full-window overlay rather than a sheet, so
    /// nothing dismisses it for free — and in `.preparing` there was no Close
    /// button drawn either, which made a file that never started unescapable.
    case escape
    /// 0–9: that tenth of the way through. See `PlayerModel.jump(toTenth:)`.
    case digit(Int)
    /// I: the info panel, Apple TV's swipe down.
    case info
    /// P: Picture in Picture.
    case pictureInPicture
}

/// Captures key presses for the player.
///
/// SwiftUI's `.keyboardShortcut` only fires for focusable controls and steals
/// the keys from the rest of the app, which is wrong for a transport that must
/// respond wherever the pointer happens to be. A first-responder NSView is the
/// mechanism that actually matches how a video player behaves.
struct KeyCaptureView: NSViewRepresentable {
    /// Return true when the key was handled, so unhandled keys still beep or
    /// reach the menu bar rather than being swallowed silently.
    let onKey: (PlayerKey) -> Bool
    /// A sideways scroll, already turned into seconds to seek by.
    let onScroll: (Double) -> Void
    /// A key let go — how a held arrow's scan knows to land.
    var onKeyUp: ((PlayerKey) -> Void)? = nil

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKey = onKey
        view.onScroll = onScroll
        view.onKeyUp = onKeyUp
        return view
    }

    func updateNSView(_ view: KeyCaptureNSView, context: Context) {
        view.onKey = onKey
        view.onScroll = onScroll
        view.onKeyUp = onKeyUp
    }
}

final class KeyCaptureNSView: NSView {
    var onKey: ((PlayerKey) -> Bool)?
    var onScroll: ((Double) -> Void)?
    var onKeyUp: ((PlayerKey) -> Void)?
    /// Whether the key being handled is the system's auto-repeat of a held
    /// one. Read by the handler during `onKey`; a held arrow scans.
    @MainActor static var isRepeat = false

    private var scrollMonitor: Any?
    private var scrollSeek = ScrollSeek()

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Claim first responder once hosted, so the transport works the moment
        // the player opens rather than after a click.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
        installScrollMonitor()
    }

    /// Removed when the view leaves its window rather than in deinit, which
    /// under strict concurrency may not touch main-actor state.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, let scrollMonitor else { return }
        NSEvent.removeMonitor(scrollMonitor)
        self.scrollMonitor = nil
    }

    /// A monitor rather than `scrollWheel(with:)`: this view sits behind the
    /// picture and the chrome, so a scroll over either never reaches it by
    /// hit-testing. The monitor sees every scroll in the window and keeps the
    /// sideways ones; vertical scrolls are left alone, so a list in a panel
    /// still scrolls.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let sideways = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            guard sideways else { return event }
            if event.phase == .began || event.momentumPhase == .began {
                self.scrollSeek.reset()
            }
            // Momentum is the trackpad coasting after the fingers lift. Following
            // it would carry the picture on past where the hand stopped.
            guard event.momentumPhase == [] else { return nil }
            if let seconds = self.scrollSeek.add(
                deltaX: event.scrollingDeltaX, precise: event.hasPreciseScrollingDeltas
            ) {
                self.onScroll?(seconds)
            }
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let key = Self.map(event) else {
            super.keyDown(with: event)
            return
        }
        Self.isRepeat = event.isARepeat
        defer { Self.isRepeat = false }
        if onKey?(key) != true {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let key = Self.map(event) else {
            super.keyUp(with: event)
            return
        }
        onKeyUp?(key)
    }

    private static func map(_ event: NSEvent) -> PlayerKey? {
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        // Anything with Command belongs to the menu bar, not the transport.
        guard !event.modifierFlags.contains(.command) else { return nil }

        switch Int(event.keyCode) {
        case 49: return .space
        case 123: return option ? .optionLeft : (shift ? .shiftLeft : .left)
        case 124: return option ? .optionRight : (shift ? .shiftRight : .right)
        case 126: return .up
        case 125: return .down
        case 115: return .home
        case 119: return .end
        case 53: return .escape
        default: break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k": return .k
        case "j": return .j
        case "l": return .l
        case "m": return .m
        case "f": return .f
        case "i": return .info
        case "p": return .pictureInPicture
        case ",": return .comma
        case ".": return .period
        case "z": return shift ? .subtitleLater : .subtitleEarlier
        case let digit? where !option && digit.count == 1 && "0123456789".contains(digit):
            return .digit(Int(digit)!)
        default: return nil
        }
    }
}
