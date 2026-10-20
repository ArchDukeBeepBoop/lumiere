import ControlCore
import SwiftUI

/// A Control Center tile: the circled glyph, a title and its state.
///
/// The whole tile is the button, as in Control Center, where Wi-Fi and
/// Bluetooth switch from anywhere on their module rather than from the circle
/// alone. A target the size of a thumb is the reason the pattern exists.
struct Tile: View {
    let symbol: String
    let title: String
    let state: String
    var active = false
    var busy = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    IconCircle(symbol: symbol, active: active, size: 30)
                    if busy {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(state).font(Menu.caption).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: Menu.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.04 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: Menu.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.18), value: active)
    }
}

/// The library at a glance, in the manner of a Control Center module: four
/// numbers that matter, then one line of what it has been doing.
struct LibraryCard: View {
    let stats: LibraryStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let stats {
                HStack(spacing: 0) {
                    figure(stats.films, "Films")
                    figure(stats.shows, "Shows")
                    figure(stats.episodes, "Episodes")
                    figure(stats.tracks, "Songs")
                }
                HStack(spacing: 14) {
                    Label("\(stats.watched.formatted()) watched", systemImage: "checkmark.circle.fill")
                    Label("\(stats.inProgress.formatted()) in progress", systemImage: "circle.lefthalf.filled")
                }
                .font(Menu.caption)
                .foregroundStyle(.secondary)
                .labelStyle(TightLabel())
                footnote(stats)
            } else {
                Label("The library could not be read.", systemImage: "externaldrive.badge.exclamationmark")
                    .font(Menu.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func figure(_ value: Int, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted())
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(name).font(Menu.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// When it last looked at the disk, and whether the backups are sound —
    /// the two quiet jobs nobody sees unless they are told.
    @ViewBuilder
    private func footnote(_ stats: LibraryStats) -> some View {
        HStack(spacing: 4) {
            if let scan = stats.lastScan {
                Text("Scanned \(scan, format: .relative(presentation: .named))")
            }
            if stats.backupCheckFailed {
                Text("·")
                Text("Backup check failed").foregroundStyle(.red)
            } else if let verified = stats.backupsVerifiedAt {
                Text("·")
                Text("Backups verified \(verified, format: .relative(presentation: .named))")
            }
        }
        .font(Menu.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}

/// Icon and title closer than Label's default, as in system captions.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
