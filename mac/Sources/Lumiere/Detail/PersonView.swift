import SwiftUI
import LumiereKit

/// Where a cast or crew member goes.
///
/// A value on the shared navigation stack, like `GenreRoute` and for the same
/// reason: clicking a face should push on top of the page you were reading with a
/// back button, not replace the section you were in.
///
/// The name and image tag ride along rather than being fetched. Everything the
/// header draws is already in the `Person` on the page that was clicked, and
/// carrying it means the person page has a title and a face the instant it opens —
/// the same "never open onto a spinner" property the detail header has. It also
/// keeps this off `/Persons/{name}`, an endpoint that is keyed by name and
/// therefore ambiguous in exactly the libraries where it matters.
struct PersonRoute: Hashable {
    let id: String
    let name: String
    let imageTag: String?

    /// Nil for a credit the server gave no id for, which is the whole test of
    /// whether the cell should be a link at all: without an id there is no
    /// `PersonIds` query to run and the page would open onto nothing.
    static func forPerson(_ person: Person) -> PersonRoute? {
        guard let id = person.id, !id.isEmpty else { return nil }
        return PersonRoute(
            id: id,
            name: person.name ?? "Unknown",
            imageTag: person.primaryImageTag
        )
    }
}

/// Everything in the library one person appears in.
///
/// Its own screen rather than a reuse of `GenreBrowseView` for the reason that
/// view is not a reuse of the library grid: a filmography is two shapes at once —
/// a wall of titles and a strip of episodes per show — and a single grid can only
/// be one of them. What it does borrow is the paging: a window that grows, never
/// "fetch it all".
struct PersonView: View {
    let route: PersonRoute
    let repository: LibraryRepository
    let pipeline: ImagePipeline
    let serverURL: URL

    // Not private: PersonView+Sections.swift draws the header portrait with it,
    // and Swift's `private` is file-scoped.
    @Environment(\.displayScale) var scale
    @State private var model: PersonModel?
    /// The shared right-click menu. See `EntryActionState`.
    @State var entryActions = EntryActionState()
    @Environment(AppModel.self) var app: AppModel?

    /// Not private: PersonView+Sections.swift builds the menus, and Swift's `private`
    /// is file-scoped.
    func actionContext(_ model: PersonModel) -> EntryActionContext {
        EntryActionContext(app: app, repository: repository) { id in
            await model.refreshRow(id: id)
        }
    }

    var body: some View {
        ScrollView {
            // `shelfGap`, the rhythm the detail pages and Home both use between
            // rows. No horizontal inset on the column: each section applies the
            // page margin itself so a shelf's scroll view can still run to the
            // window edge.
            LazyVStack(alignment: .leading, spacing: Theme.Space.shelfGap) {
                header(model)
                content(for: model)
            }
            .padding(.vertical, Theme.Space.xl)
            .padding(.bottom, Theme.Space.xxxl)
        }
        // Deliberately no canvas fill: the root supplies the background — glass or
        // flat — and repainting it here is what hid it.
        .discreetNavigationTitle(route.name)
        .entryActions(entryActions, in: EntryActionContext(
            app: app, repository: repository,
            refreshRow: { id in await model?.refreshRow(id: id) }
        ))
        .task {
            let model = model ?? PersonModel(personId: route.id, repository: repository)
            self.model = model
            await model.load()
        }
        // Row only: who was in a film is not something a tick can change.
        .onLibraryChange { change in
            guard let id = change.itemId else { return }
            await model?.refreshRow(id: id)
        }
    }

    @ViewBuilder
    private func content(for model: PersonModel?) -> some View {
        if let model {
            if model.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    empty(model)
                }
            } else {
                if !model.titles.isEmpty {
                    titlesSection(model)
                }
                ForEach(model.episodeGroups) { group in
                    episodeShelf(model, group)
                }
                if model.hasMoreEpisodes {
                    moreEpisodes(model)
                }
            }
        }
    }
}
