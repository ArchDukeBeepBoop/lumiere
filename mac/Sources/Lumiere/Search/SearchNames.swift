import SwiftUI
import LumiereKit

/// People and studios a search names, above the titles it found: typing
/// "Bones" or "Hans Zimmer" offers the studio or the composer first, then
/// their work. A person opens their page; a studio opens a wall of its titles.
struct SearchNamesRow: View {
    let term: String
    let repository: LibraryRepository

    @State private var people: [(id: String, name: String, detail: String)] = []
    @State private var studios: [(name: String, count: Int)] = []

    var body: some View {
        Group {
            if !people.isEmpty || !studios.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(studios, id: \.name) { studio in
                            NavigationLink(value: GenreRoute(name: studio.name, isStudio: true)) {
                                chip(studio.name, "\(studio.count) titles", icon: "building.2")
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(people, id: \.id) { person in
                            NavigationLink(value: PersonRoute(id: person.id, name: person.name, imageTag: nil)) {
                                chip(person.name, person.detail, icon: "person")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Space.xxl)
                }
            }
        }
        .task(id: term) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            studios = await repository.studiosMatching(term)
            people = await repository.searchPeople(term)
            // A search that was left standing counts as made. See RecentSearches.
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { RecentSearches.add(term) }
        }
    }

    private func chip(_ title: String, _ detail: String, icon: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: icon).foregroundStyle(Theme.Palette.textMuted)
            Text(title).foregroundStyle(Theme.Palette.textPrimary)
            if !detail.isEmpty { Text(detail).foregroundStyle(Theme.Palette.textMuted) }
        }
        .font(Theme.Font.caption)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Palette.surface, in: Capsule())
    }
}

/// The last few searches, shown when the field is empty. Kept on this Mac.
enum RecentSearches {
    static let key = "recentSearches"
    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        var list = all.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
        list.insert(t, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

struct RecentSearchesList: View {
    let onPick: (String) -> Void
    @State private var items = RecentSearches.all

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text("Recent").font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
                    Spacer()
                    Button("Clear") { RecentSearches.clear(); items = [] }
                        .buttonStyle(.link).font(Theme.Font.caption)
                }
                // Tiles, as on Apple TV, not a list of links.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.sm)],
                          alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(items, id: \.self) { term in
                        Button { onPick(term) } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Space.md)
                                .padding(.vertical, Theme.Space.sm)
                                .background(Theme.Palette.surface, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, Theme.Space.xxl)
        }
    }
}
