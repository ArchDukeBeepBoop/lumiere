import SwiftUI
import LumiereKit

/// The header's controls: the Play button, and the row of icon actions beneath it.
///
/// Split from DetailHeroHeader.swift to keep it under the project's 300-line limit.
/// Purely presentation — every action is a closure the header was handed.
extension DetailHeroHeader {

    /// The one thing on the page that has to look pressable.
    ///
    /// It was a 12pt label in a 40pt pill with a 6pt corner, which under a
    /// full-width backdrop read as a link with a box drawn round it. Apple TV
    /// gives its primary action a genuinely large target and lets the label carry
    /// weight; this is that. It also borrows the app's own hover lift rather than
    /// keeping a 1.02 scale of its own — there is one hover gesture in Lumiere and
    /// this button was the last thing not using it.
    var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "play.fill").font(.system(size: 16))
                Text(playLabel).font(Theme.Font.playLabel)
            }
            .foregroundStyle(Theme.Palette.playButtonLabel)
            .frame(maxWidth: .infinity, minHeight: DetailMetrics.playButtonHeight)
            .background(Theme.Palette.playButton)
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.Radius.playControl, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        // Written the shelves' way — radius zero at rest — even though one button
        // per page would survive an always-installed shadow, so that nobody copies
        // the wrong pattern out of the most-read view in the folder.
        .shadow(
            color: isHoveringPlay ? Theme.Palette.cardShadow : .clear,
            radius: isHoveringPlay ? Theme.Elevation.hoverShadow : 0,
            y: isHoveringPlay ? Theme.Elevation.hoverShadowY : 0
        )
        .scaleEffect(isHoveringPlay ? Theme.Elevation.hoverScale : 1)
        .animation(Theme.Motion.hover, value: isHoveringPlay)
        .onHover { isHoveringPlay = $0 }
    }

    /// Watched, favourite and download all act on the hero episode — whichever one
    /// is on screen — not on the series. Marking "the series" watched is not a
    /// coherent action; marking one episode is.
    /// The version picker, where a title genuinely has more than one file.
    ///
    /// It existed only on the older header, which films never reach — every film
    /// takes the hero layout — so a 4K and a 1080p rip of one film had a picker
    /// that could not be seen and, until the source was plumbed into playback, would
    /// not have changed anything if it had been.
    @ViewBuilder
    var versionPicker: some View {
        if versions.count > 1, let selectedVersion {
            Picker("Version", selection: selectedVersion) {
                ForEach(versions) { source in
                    Text(source.name ?? "Version").tag(Optional(source.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // Matched to the Play pill above it rather than left at an arbitrary
            // 240, so the action column has one edge instead of three.
            .frame(maxWidth: DetailMetrics.actionColumnWidth)
        }
    }

    /// Quiet by design. These are outlined boxes no longer: see QuietIconButton for
    /// why four bordered controls under a Play pill of the same height left nothing
    /// on the header reading as the primary action.
    ///
    /// Nudged left by the button's own hover padding so the row's first glyph still
    /// lines up with the Play pill's leading edge.
    var actionRow: some View {
        HStack(spacing: Theme.Space.xs) {
            QuietIconButton(
                systemName: hero.isPlayed ? "eye.fill" : "eye",
                help: hero.isPlayed ? "Mark as unwatched" : "Mark as watched",
                isOn: hero.isPlayed
            ) {
                Task { await onToggleWatched() }
            }
            // The series on a series page, the film on a film page. See
            // `favouriteEntry`.
            let starred = (favouriteEntry ?? hero)
            let isStarred = starred.userData?.isFavorite == true
            QuietIconButton(
                systemName: isStarred ? "star.fill" : "star",
                help: isStarred
                    ? "Remove \(starred.item.name) from favourites"
                    : "Add \(starred.item.name) to favourites",
                isOn: isStarred
            ) {
                Task { await onToggleFavourite() }
            }
            if let download {
                QuietIconButton(
                    systemName: download.icon, help: download.help, isOn: download.isComplete
                ) {
                    Task { await download.act() }
                }
            }
            if let onEditMetadata {
                QuietIconButton(
                    systemName: "square.and.pencil",
                    help: "Edit title, synopsis and year — and lock them against refreshes",
                    action: onEditMetadata
                )
            }
        }
        .padding(.leading, -Theme.Space.sm)
    }

    var playLabel: String {
        guard let userData = hero.userData, userData.isInProgress else { return "Play" }
        let seconds = Int(userData.resumeSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "Resume %d:%02d:%02d", hours, minutes, secs)
            : String(format: "Resume %d:%02d", minutes, secs)
    }
}
