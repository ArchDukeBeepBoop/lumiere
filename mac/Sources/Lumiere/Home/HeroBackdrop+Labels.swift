import SwiftUI
import LumiereKit

/// The hero's button labels and play state. Split from HeroBackdrop.swift
/// for the 300-line rule.
extension HeroBackdrop {
    func primaryLabel(icon: String, text: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon).font(.system(size: 13))
            Text(text).font(Theme.Font.cardTitle)
        }
        .foregroundStyle(Theme.Palette.playButtonLabel)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.sm + 2)
        .background(Theme.Palette.playButton)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    func secondaryLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.cardTitle)
            // The on-artwork colours, not the page's: this sits on the hero's
            // dark gradient in every theme, and the page's grey read as
            // disabled there — in light mode, and worse on Paper.
            .foregroundStyle(Theme.Palette.onArtworkText)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm + 2)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(Theme.Palette.onArtworkTextMuted, lineWidth: 1)
            }
    }

    /// Only these have a file behind them. A series or a folder does not.
    var isPlayable: Bool {
        switch entry.item.itemType {
        case .movie, .episode, .video: return true
        default: return false
        }
    }

    /// "Resume", not "Resume 1:04:22". The timecode was the widest thing in the
    /// hero and it says less than the progress bar directly above it does.
    var resumeLabel: String {
        entry.userData?.isInProgress == true ? "Resume" : "Play"
    }
}
