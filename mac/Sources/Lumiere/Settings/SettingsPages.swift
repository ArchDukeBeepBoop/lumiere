import SwiftUI

/// Long sections on pages of their own, as System Settings does.
///
/// A pane was every section's rows and explanations in one long scroll. Now a
/// section taller than `pageThreshold` shows on its pane as a single row —
/// icon, title, subtitle, chevron — and opens on its own page; a short one,
/// a switch or two, stays where it is, so the simple things cost no click.
/// Each section measures itself, so no list has to be kept of which is which.
enum SettingsPages {
    static let pageThreshold: CGFloat = 230
    /// Heights seen, by section title, so a long section shows as a row from
    /// the first frame once it has been measured.
    @MainActor static var heights: [String: CGFloat] = [:]

    @MainActor static func isPage(_ title: String) -> Bool {
        (heights[title] ?? 0) > pageThreshold
    }
}

private struct SettingsOpenCardKey: EnvironmentKey {
    static let defaultValue: Binding<String?> = .constant(nil)
}

extension EnvironmentValues {
    /// The section open on its own page, if any. Set by `SettingsView`.
    var settingsOpenCard: Binding<String?> {
        get { self[SettingsOpenCardKey.self] }
        set { self[SettingsOpenCardKey.self] = newValue }
    }
}

/// A long section's row on its pane.
struct SettingsPageRow: View {
    let title: String
    let icon: String?
    let subtitle: String?
    let open: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Space.sm) {
                if let icon { SettingsIconChip(icon) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.Font.body.weight(.medium))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textMuted)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm + 2)
            .background(isHovering ? Theme.Palette.surfaceRaised : Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .id(title)
    }
}
