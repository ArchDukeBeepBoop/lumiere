import Foundation
import LumierePlayer

/// A held arrow, scanning: the picture holds still and the bar's preview moves.
struct KeyScan {
    let began: ContinuousClock.Instant
    /// Where the picture really is — the step on release is measured from here.
    let from: Double
    let wasPlaying: Bool
    var target: Double
    var lastStep: ContinuousClock.Instant
}

/// Seeking with the keyboard.
///
/// It was janky in four ways, all fixed here. A step was an absolute keyframe
/// seek, which lands on the keyframe *before* its target — on a file with
/// keyframes ten seconds apart, → could land where it started or behind it.
/// Each press then seeked a second time to settle. Holding a key fired thirty
/// seeks a second at a decoder that could not keep up, so the picture froze
/// and lurched. And nothing showed where a step had gone.
///
/// Now: one direction-aware step per press (exact when paused); holding scans —
/// the picture waits, the preview runs ahead, faster the longer it is held —
/// and letting go makes one step to where the preview stopped; and every press
/// shows the bar with its preview. Apple TV's grammar, on a Mac keyboard.
extension PlayerModel {

    /// One press, or one repeat of a held key.
    func keyStep(by step: Double, isRepeat: Bool) async {
        guard engine != nil, duration > 0 else { return }
        let now = ContinuousClock.now
        if !isRepeat {
            // A fresh press ends a scan whose key-up went astray.
            if keyScan != nil { await keyRelease() }
            let from = position
            let target = clamp(from + step)
            showKeyPreview(at: target)
            await stepEngine(from: from, to: target, exact: !isPlaying)
            return
        }
        if keyScan == nil {
            let wasPlaying = isPlaying
            if wasPlaying, let engine {
                await engine.pause()
                state = .paused
            }
            keyScan = KeyScan(began: now, from: position, wasPlaying: wasPlaying,
                              target: position, lastStep: now - .seconds(1))
        }
        guard var scan = keyScan, now - scan.lastStep >= .milliseconds(90) else { return }
        // Faster the longer it is held: the step, then 30 s, then 2 minutes.
        let held = now - scan.began
        let size = held < .milliseconds(1500) ? abs(step) : held < .seconds(4) ? max(30, abs(step)) : 120
        scan.target = clamp(scan.target + (step < 0 ? -size : size))
        scan.lastStep = now
        keyScan = scan
        position = scan.target
        showKeyPreview(at: scan.target)
    }

    /// The arrow let go: one step to where the scan stopped, and play on.
    func keyRelease() async {
        guard let scan = keyScan else { return }
        keyScan = nil
        await stepEngine(from: scan.from, to: scan.target, exact: !scan.wasPlaying)
        if scan.wasPlaying, let engine {
            await engine.play()
            state = .playing
        }
        showKeyPreview(at: scan.target)
    }

    /// 0–9: that tenth of the way in, as on YouTube.
    func jump(toTenth tenth: Int) async {
        guard duration > 0 else { return }
        let target = clamp(duration * Double(tenth) / 10)
        showKeyPreview(at: target)
        await stepEngine(from: position, to: target, exact: !isPlaying)
    }

    /// Chapter skip is what the ⌥← / ⌥→ bindings do, and what the prev/next
    /// buttons fall back to when there is no adjacent episode.
    func skipChapter(forward: Bool) async {
        // Chapters, and the intro and credits marks: both are places worth
        // landing, and a file with no chapters often still has the marks.
        let stops = (chapters.map(\.startSeconds)
            + segments.filter { $0.skipLabel != nil }.flatMap { [$0.start, $0.end] })
            .filter { $0 > 0 && $0 < duration }
            .sorted()
        guard !stops.isEmpty else {
            await skip(by: forward ? 60 : -60)
            return
        }
        if forward {
            guard let next = stops.first(where: { $0 > position + 1 }) else {
                await seek(to: duration)
                return
            }
            await seek(to: next)
        } else {
            // Two seconds of grace so pressing back mid-chapter restarts it
            // rather than jumping to the previous one, which is what people mean.
            let previous = stops.last { $0 < position - 2 }
            await seek(to: previous ?? 0)
        }
    }

    /// Exact when paused — placing a frame, where a little decoding is worth
    /// it; a keyframe in the direction of travel while playing.
    private func stepEngine(from: Double, to target: Double, exact: Bool) async {
        guard let engine, target != from else { return }
        position = target
        seeksInFlight += 1
        if exact {
            await engine.seek(to: target, precise: true)
        } else {
            await engine.step(by: target - from, from: from)
        }
        seeksInFlight -= 1
        Task { await report(force: true) }
    }

    /// The bar's preview at a time, cleared a moment after the last press.
    private func showKeyPreview(at seconds: Double) {
        keyPreviewSeconds = seconds
        keyPreviewClear?.cancel()
        keyPreviewClear = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled, let self, self.keyScan == nil else { return }
            self.keyPreviewSeconds = nil
        }
    }

    private func clamp(_ seconds: Double) -> Double {
        max(0, min(seconds, max(0, duration - 1)))
    }
}
