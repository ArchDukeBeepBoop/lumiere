import SwiftUI
import LumiereKit

/// Reordering the home screen, for the room it is opened in: the private
/// room's rows inside it, everything else outside, each room with its own
/// order.
///
/// Dragged: each row carries a grip, and dropping it on another row puts it
/// there. Up and down buttons came first, for being keyboard-reachable and
/// unambiguous, and were slow work for a list of twenty rows.
struct HomeOrderCard: View {
    let libraries: [LibraryRecord]
    /// Called after every change, so the lists that are *not* rebuilt from this
    /// preference on each draw — the sidebar, the poster row — pick the new order
    /// up immediately rather than at the next launch.
    var onChange: () -> Void = {}

    @AppStorage(HomeOrder.storageKey) private var storedOrder = ""
    @AppStorage(HomeOrder.hiddenKey) private var storedHidden = ""
    /// The row a drag is over, drawn highlighted.
    @State private var dropTarget: String?

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

            Image(systemName: "line.3.horizontal")
                .font(Theme.Glyph.sm(.semibold))
                .foregroundStyle(Theme.Palette.textMuted)
                .frame(width: 22, height: 20)
                .labelledHelp("Drag to move")
        }
        .padding(.vertical, Theme.Space.xxs)
        .background(dropTarget == section.id ? Theme.Palette.accentMuted : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .draggable(section.id) {
            Text(section.title(libraryName: name(for:)))
                .font(Theme.Font.body)
                .padding(Theme.Space.sm)
                .background(Theme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let from = order.firstIndex(where: { $0.id == id }),
                  let to = order.firstIndex(of: section), from != to else { return false }
            storedOrder = HomeOrder.encode(HomeOrder.moved(order[from], by: to - from, in: order))
            onChange()
            return true
        } isTargeted: { over in
            dropTarget = over ? section.id : (dropTarget == section.id ? nil : dropTarget)
        }
        .animation(Theme.Motion.hover, value: dropTarget)
    }
}
