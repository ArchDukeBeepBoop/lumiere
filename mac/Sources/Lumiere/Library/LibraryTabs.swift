import SwiftUI
import LumiereKit

/// The tabs across the top of a library, as in the TV app's library: All,
/// Films, Shows, Collections — only those this library has, and none at all
/// where it holds one kind.
enum LibraryTab: String, CaseIterable, Identifiable {
    case all, films, shows, collections
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .films: return "Films"
        case .shows: return "Shows"
        case .collections: return "Collections"
        }
    }

    var types: [JellyfinItem.ItemType] {
        switch self {
        case .all: return LibraryRepository.topLevelTypes
        case .films: return [.movie]
        case .shows: return [.series]
        case .collections: return [.boxSet]
        }
    }
}

struct LibraryTabBar: View {
    let available: [LibraryTab]
    @Binding var selection: LibraryTab

    var body: some View {
        if available.count > 2 {
            HStack(spacing: Theme.Space.sm) {
                ForEach(available) { tab in
                    let current = tab == selection
                    Button { selection = tab } label: {
                        Text(tab.title)
                            .font(.system(size: 14, weight: current ? .semibold : .medium))
                            .foregroundStyle(current ? Theme.Palette.canvas : Theme.Palette.textPrimary)
                            .padding(.horizontal, Theme.Space.md)
                            .padding(.vertical, 7)
                            .background(current ? Theme.Palette.textPrimary : Theme.Palette.surface, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
