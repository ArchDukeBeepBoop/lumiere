import SwiftUI
import Observation
import LumiereKit

/// The cast and crew you have starred, kept on the server like every other
/// favourite so they follow you to every device — the Favourites page's Cast
/// & Crew row, and the star on a person's page.
@MainActor
@Observable
final class FavouritePeople {
    static let shared = FavouritePeople()

    struct Person: Identifiable, Hashable {
        let id: String
        let name: String
        let imageTag: String?
        let credits: String?
    }

    private(set) var people: [Person] = []
    private(set) var ids: Set<String> = []
    var failure: String?

    func load(client: JellyfinClient?) async {
        guard let client else { return }
        do {
            people = try await client.favouritePeople().map {
                Person(id: $0.id, name: $0.name, imageTag: $0.imageTags?["Primary"], credits: $0.overview)
            }
            ids = Set(people.map(\.id))
            failure = nil
        } catch {
            failure = ConnectionState.message(for: error)
        }
    }

    /// Stars or unstars someone; the star changes on the click, the server's
    /// list is the truth after it.
    func toggle(_ route: PersonRoute, client: JellyfinClient?) async {
        guard let client else { return }
        let starring = !ids.contains(route.id)
        if starring { ids.insert(route.id) } else { ids.remove(route.id) }
        do {
            try await client.markFavorite(itemId: route.id, favorite: starring)
        } catch {
            failure = ConnectionState.message(for: error)
        }
        await load(client: client)
    }
}

/// The star on a person's page.
struct FavouritePersonButton: View {
    let route: PersonRoute
    let app: AppModel?
    private var store: FavouritePeople { .shared }

    var body: some View {
        let starred = store.ids.contains(route.id)
        Button { Task { await store.toggle(route, client: app?.client) } } label: {
            Label(starred ? "Favourite" : "Add to Favourites", systemImage: starred ? "star.fill" : "star")
                .font(Theme.Font.body.weight(.semibold))
                .foregroundStyle(starred ? Theme.Palette.accent : Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(Theme.Palette.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(app?.client == nil)
        .labelledHelp(starred ? "Remove \(route.name) from Favourites" : "Add \(route.name) to Favourites")
        .task { if store.people.isEmpty { await store.load(client: app?.client) } }
    }
}

/// Cast & Crew at the head of the Favourites page: round photos, each opening
/// the person's page.
struct FavouritePeopleRow: View {
    let app: AppModel?
    let serverURL: URL
    let pipeline: ImagePipeline
    @Environment(\.displayScale) private var scale
    private var store: FavouritePeople { .shared }
    private let photo: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if !store.people.isEmpty {
                ShelfTitleCard(title: "Cast & Crew", subtitle: "\(store.people.count) starred")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.Space.tileGap) {
                        ForEach(store.people) { person in
                            NavigationLink(value: PersonRoute(id: person.id, name: person.name, imageTag: person.imageTag)) {
                                cell(person)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove from Favourites") {
                                    Task { await store.toggle(PersonRoute(id: person.id, name: person.name, imageTag: person.imageTag),
                                                              client: app?.client) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.xl)
                }
            }
        }
        .task { await store.load(client: app?.client) }
    }

    private func cell(_ person: FavouritePeople.Person) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Group {
                if let tag = person.imageTag {
                    RemoteImage(request: ImageRequest(serverURL: serverURL, itemId: person.id, kind: .primary, tag: tag,
                                                      displayWidth: photo, aspectRatio: 1, screenScale: scale),
                                pipeline: pipeline)
                } else {
                    Circle().fill(Theme.Palette.surfaceRaised)
                        .overlay { Image(systemName: "person.fill").foregroundStyle(Theme.Palette.textDisabled) }
                }
            }
            .frame(width: photo, height: photo)
            .clipShape(Circle())
            Text(person.name)
                .font(Theme.Font.cardTitle).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
            if let credits = person.credits {
                Text(credits).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textMuted)
            }
        }
        .frame(width: photo + Theme.Space.lg)
    }
}
