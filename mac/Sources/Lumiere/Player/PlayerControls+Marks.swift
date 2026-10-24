import SwiftUI
import LumiereKit

/// The marks along the scrubber: chapter notches and bookmark dots.
///
/// Split from PlayerControls+Scrubber.swift for the project's 300-line rule.
extension PlayerControls {

    /// Chapter boundaries.
    ///
    /// Full-height notches rather than the old floating hairlines: at 2pt on a 4pt
    /// bar they read as artefacts, and they were drawn in the chrome colour, so a
    /// mark on the played gold and a mark on the empty track were two different
    /// things. One dark notch punched through the bar reads the same everywhere.
    @ViewBuilder
    func chapterMarkers(width: CGFloat, height: CGFloat) -> some View {
        if model.chapters.count > 1, model.duration > 0 {
            ForEach(Array(model.chapters.enumerated()), id: \.offset) { _, chapter in
                let fraction = chapter.startSeconds / model.duration
                if fraction > 0.001 && fraction < 0.999 {
                    Capsule()
                        .fill(Theme.PlayerPalette.chapterMark)
                        .frame(width: Theme.PlayerMetric.chapterMarkWidth, height: height)
                        .offset(x: width * fraction - Theme.PlayerMetric.chapterMarkWidth / 2)
                }
            }
        }
    }

    /// Bookmarks (⌘B), as dots riding just above the bar — a different shape
    /// from a chapter's notch, so the two never read as one thing. Hovering one
    /// names it in the preview card.
    @ViewBuilder
    func bookmarkMarkers(width: CGFloat, height: CGFloat) -> some View {
        if model.duration > 0 {
            ForEach(model.bookmarks) { mark in
                Circle()
                    .fill(Theme.PlayerPalette.scrubPlayed)
                    .overlay(Circle().strokeBorder(Theme.Palette.videoGround.opacity(0.5), lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .offset(x: width * (mark.seconds / model.duration) - 3.5, y: -(height / 2 + 6))
                    .accessibilityLabel("Bookmark: \(mark.label)")
            }
        }
    }
}
