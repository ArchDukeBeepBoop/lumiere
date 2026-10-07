import SwiftUI
import LumiereKit

/// The bottom of the Subtitles tab: fetching one, and lining it up.
///
/// Split from PlayerTrackPanel.swift for the project's 300-line limit, and
/// along a real seam — everything here talks to the server, where the rest of
/// that file only talks to the engine.
extension PlayerTrackPanel {

    @ViewBuilder
    var subtitleTools: some View {
        Divider()
            .overlay(Theme.PlayerPalette.surfaceStroke)
            .padding(.vertical, Theme.Space.xxs)

        // Only where a subtitle is actually showing: syncing nothing is a
        // control that can only disappoint.
        if model.selectedSubtitleTrack != nil {
            PlayerPanelRow(
                title: "Sync to audio", detail: syncDetail, selected: false
            ) {
                Task { await model.syncCurrentSubtitle() }
            }
        }

        PlayerPanelRow(
            title: "Find subtitles…",
            detail: model.subtitleResults.isEmpty ? nil : "\(model.subtitleResults.count) found",
            selected: false
        ) {
            Task { await model.findSubtitles() }
        }

        switch model.subtitleTask {
        case .idle:
            EmptyView()
        case .searching:
            note("Asking the provider…")
        case .downloading:
            note("Fetching and checking the timing…")
        case .syncing:
            note("Listening for the dialogue…")
        case .done(let text):
            note(text)
        case .failed(let text):
            note(text)
        case .unsure(let sync):
            note(String(format: "Only %.0f%% sure of the timing.", sync.confidence * 100))
            PlayerPanelRow(
                title: String(format: "Try %+.1f s", sync.offset),
                detail: "Undo afterwards if the lines miss", selected: false
            ) {
                Task { await model.tryUnsureSync(sync) }
            }
        case .offerSeason(let seconds, let message):
            note(message)
            if model.queue.count > 1 {
                PlayerPanelRow(
                    title: "Use for the rest of the season",
                    detail: String(format: "%+.1f s on %d more", seconds, model.queue.count - 1),
                    selected: false
                ) {
                    Task { await model.applyDelayToSeason(seconds) }
                }
            }
        case .tried(let previous):
            note("Shifted. If the lines still miss, go back.")
            PlayerPanelRow(
                title: "Revert", detail: String(format: "to %+.1f s", previous), selected: false
            ) {
                Task { await model.revertTriedSync(to: previous) }
            }
        }

        ForEach(model.subtitleResults) { candidate in
            PlayerPanelRow(
                title: candidate.release.isEmpty ? "Untitled release" : candidate.release,
                detail: detail(for: candidate),
                selected: false
            ) {
                Task { await model.downloadSubtitle(candidate) }
            }
        }
    }

    /// What the sync row says under its title: the shift now in force, where
    /// there is one, so pressing it twice is not a mystery.
    private var syncDetail: String? {
        model.subtitleDelay == 0 ? nil : String(format: "%+.1f s now", model.subtitleDelay)
    }

    /// A release line is long and a panel is narrow, so the second line
    /// carries what actually decides between two: how many people took it,
    /// and the marks against it. A machine translation reads badly and is
    /// worth saying so rather than hiding.
    private func detail(for candidate: RemoteSubtitle) -> String {
        var parts: [String] = [candidate.language.uppercased()]
        if candidate.downloads > 0 {
            parts.append("\(candidate.downloads.formatted()) downloads")
        }
        if candidate.fromTrusted { parts.append("trusted") }
        if candidate.hearingImpaired { parts.append("SDH") }
        if candidate.aiTranslated { parts.append("AI") }
        else if candidate.machineTranslated { parts.append("machine") }
        return parts.joined(separator: " · ")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.onPlayerChromeSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .fixedSize(horizontal: false, vertical: true)
    }
}
