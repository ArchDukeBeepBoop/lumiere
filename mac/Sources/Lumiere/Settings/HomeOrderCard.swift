import SwiftUI
import LumiereKit

/// Reordering the home screen.
///
/// Up and down buttons rather than drag-and-drop, and that is a deliberate choice
/// rather than the easy one. A settings pane is already a scrolling column; a list
/// inside it that also takes drags fights the scroll on a trackpad, and the target
/// for "one place up" is then a gesture rather than a button. Two buttons per row
/// are unambiguous, keyboard-reachable, and can say when they do nothing by being
/// disabled at the ends.
struct HomeOrderCard: View {
    let libraries: [LibraryRecord]
    /// Called after every change, so the lists that are *not* rebuilt from this
    /// preference on each draw — the sidebar, the poster row — pick the new order
    /// up immediately rather than at the next launch.
    var onChange: () -> Void = {}

    @AppStorage(HomeOrder.storageKey) private var storedOrder = ""
    @AppStorage(HomeOrder.hiddenKey) private var storedHidden = ""

    private var hidden: Set<String> { HomeOrder.hidden(from: storedHidden) }

    private var order: [HomeSection] {
        HomeOrder.resolve(stored: storedOrder, libraryIds: libraries.map(\.id))
    }

    private func name(for libraryId: String) -> String? {
        libraries.first { $0.id == libraryId }?.name
    }

    var body: some View {
        SettingsCard(
            title: "Home Screen Order",
            icon: "list.bullet.indent",
            subtitle: "What appears first, and what comes after it",
            accessory: {
                if !storedOrder.isEmpty {
                    Button("Reset") { storedOrder = ""; onChange() }
                        .font(Theme.Font.caption)
                }
            }
        ) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, section in
                row(section, at: index)
                if index < order.count - 1 {
                    Divider().opacity(0.35)
                }
            }

            SettingsNote(
                "Untick a row to keep it off the home screen. A private library's "
                + "Latest row is the usual case: its newest titles still appear "
                + "here for you, and nowhere in the row that mixes every library "
                + "together — see Recently Added under Library."
            )

            SettingsNote(
                "Applies to the Classic and Hero layouts, which draw all of these. "
                + "A row with nothing in it — Next Up before you have started a "
                + "series — takes no space wherever you put it. Recently Added is "
                + "drawn by the Hero layout only; Classic says the same thing one "
                + "library at a time with its Latest rows."
            )
        }
    }

    private func row(_ section: HomeSection, at index: Int) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text("\(index + 1)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: 22, alignment: .trailing)
                .monospacedDigit()

            // On or off, per row. The furniture — spotlight, quick links, the
            // library posters — cannot be switched off from here; those are
            // the home screen, not things on it.
            if section.isShelf {
                Toggle(isOn: Binding(
                    get: { !hidden.contains(section.id) },
                    set: { on in
                        var ids = hidden
                        if on { ids.remove(section.id) } else { ids.insert(section.id) }
                        storedHidden = HomeOrder.encodeHidden(ids)
                        onChange()
                    }
                )) {
                    Text(section.title(libraryName: name(for:)))
                        .font(Theme.Font.body)
                        .foregroundStyle(
                            hidden.contains(section.id)
                                ? Theme.Palette.textMuted : Theme.Palette.textPrimary
                        )
                }
                .toggleStyle(.checkbox)
            } else {
                Text(section.title(libraryName: name(for:)))
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            Spacer(minLength: Theme.Space.md)

            move(section, by: -1, icon: "chevron.up", enabled: index > 0)
            move(section, by: 1, icon: "chevron.down", enabled: index < order.count - 1)
        }
    }

    private func move(
        _ section: HomeSection, by offset: Int, icon: String, enabled: Bool
    ) -> some View {
        Button {
            storedOrder = HomeOrder.encode(
                HomeOrder.moved(section, by: offset, in: order)
            )
            onChange()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Theme.Palette.accent : Theme.Palette.textMuted)
        .labelledHelp(offset < 0 ? "Move up" : "Move down")
    }
}
