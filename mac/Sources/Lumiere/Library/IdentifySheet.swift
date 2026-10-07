import SwiftUI
import LumiereKit

/// Tell the server what a title actually is.
///
/// Defaults to **your server's own providers**. That is the important part: Jellyfin
/// already holds credentials for whatever providers its admin configured, so this
/// works with no API key entered anywhere in this app, and the ids it returns are
/// exactly what the server wants handed back. The earlier version searched only
/// providers whose keys you had pasted into Settings — which meant that with no key
/// entered, Identify could not do anything at all, and nothing it did do involved the
/// server until the very last step.
///
/// The key-based providers stay available as a second option, because for anime the
/// server genuinely does come back empty often enough to matter.
struct IdentifySheet: View {
    let itemId: String
    let initialQuery: String
    let isSeries: Bool
    /// Set when the thing being identified is a *season*: the match is a
    /// show, and this is which season of it. Useful for bundling — a related
    /// title filed as a season of a series folder can name its own show.
    var seasonNumber: Int? = nil
    let client: JellyfinClient
    /// Passes back whether anything changed, so the caller can reload only if needed.
    let onDone: (Bool) -> Void

    /// Which search backend. `nil` means the server's own providers.
    ///
    /// Defaults to TMDB whenever a key for it exists, because the server's own search
    /// is the weaker of the two here and, on Lumiere's own server, is not implemented
    /// at all. With no key stored there is nothing to default to, so it falls back.
    @State private var provider: MetadataProvider? =
        MetadataCredentials.hasKey(for: .tmdb) ? .tmdb : nil
    @State private var query: String = ""
    @State private var serverMatches: [RemoteSearchResult] = []
    @State private var matches: [ProviderMatch] = []
    @State private var isSearching = false
    @State private var applying: String?
    @State private var message: String?
    @State private var chosenSeason = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
                .onAppear { if let seasonNumber { chosenSeason = max(seasonNumber, 0) } }
            searchBar

            if isSearching {
                ProgressView("Searching \(sourceName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message {
                Text(message)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Space.lg)
            } else if isEmpty {
                Text("Search for the correct title. The result you pick is applied on "
                   + "your server, which then fetches the metadata itself.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
        }
        .padding(Theme.Space.lg)
        .frame(width: 640, height: 560)
        .background(Theme.Palette.canvas)
        .onAppear {
            query = initialQuery
            Task { await search() }
        }
    }

    private var isEmpty: Bool {
        provider == nil ? serverMatches.isEmpty : matches.isEmpty
    }

    private var sourceName: String {
        provider?.title ?? "your server"
    }

    private var header: some View {
        HStack {
            Text("Identify")
                .font(Theme.Font.sectionHeader)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            if seasonNumber != nil {
                Stepper("Season \(chosenSeason) of that show", value: $chosenSeason, in: 0...99)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Picker("", selection: $provider) {
                Text("My Server").tag(MetadataProvider?.none)
                ForEach(MetadataProvider.allCases) { Text($0.title).tag(MetadataProvider?.some($0)) }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: provider) { Task { await search() } }
            Button("Cancel") { onDone(false) }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.sm) {
            TextField("Title", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await search() } }
            Button("Search") { Task { await search() } }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var results: some View {
        ScrollView {
            VStack(spacing: Theme.Space.sm) {
                if provider == nil {
                    ForEach(serverMatches) { match in
                        Button { Task { await applyServer(match) } } label: {
                            row(
                                title: match.name ?? "Untitled",
                                subtitle: match.searchProviderName,
                                year: match.productionYear,
                                overview: match.overview,
                                poster: match.posterURL,
                                isApplying: applying == match.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(applying != nil)
                    }
                } else {
                    ForEach(matches) { match in
                        Button { Task { await apply(match) } } label: {
                            row(
                                title: match.title,
                                subtitle: match.originalTitle == match.title ? nil : match.originalTitle,
                                year: match.year,
                                overview: match.overview,
                                poster: match.posterURL,
                                isApplying: applying == match.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(applying != nil)
                    }
                }
            }
        }
    }

    private func row(
        title: String,
        subtitle: String?,
        year: Int?,
        overview: String?,
        poster: URL?,
        isApplying: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            // Straight from the provider URL rather than through ImagePipeline: these
            // are previews of artwork not on the server, with no item id or tag to
            // cache against.
            AsyncImage(url: poster) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Theme.Palette.surface)
                }
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.poster))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text(title)
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let year {
                        Text(String(year))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textMuted)
                    }
                }
                // Which provider found it, when searching the server — several may
                // answer, and knowing whether a match came from TMDB or AniList is
                // how you tell two identically-titled results apart.
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                if let overview, !overview.isEmpty {
                    Text(overview)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textMuted)
                        .lineLimit(3)
                }
            }
            Spacer()
            if isApplying { ProgressView().controlSize(.small) }
        }
        .padding(Theme.Space.sm)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: 8))
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        message = nil
        matches = []
        serverMatches = []
        defer { isSearching = false }

        guard let provider else {
            do {
                serverMatches = try await client.remoteSearch(
                    itemId: itemId, name: term, isSeries: isSeries
                )
                if serverMatches.isEmpty {
                    message = "Your server's providers found nothing for \"\(term)\". "
                            + "Try another spelling, or pick a specific provider above."
                }
            } catch {
                message = ConnectionState.message(for: error)
            }
            return
        }

        do {
            matches = try await ProviderSearch.search(provider, query: term, isSeries: isSeries)
            if matches.isEmpty {
                message = "No matches for \"\(term)\" on \(provider.title)."
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyServer(_ match: RemoteSearchResult) async {
        applying = match.id
        defer { applying = nil }
        do {
            var result = match
            if seasonNumber != nil {
                result = RemoteSearchResult(
                    name: match.name, productionYear: match.productionYear,
                    imageURL: match.imageURL,
                    providerIds: (match.providerIds ?? [:])
                        .merging(["TmdbSeason": String(chosenSeason)]) { _, new in new }
                )
            }
            try await client.applyRemoteSearchResult(itemId: itemId, result: result)
            onDone(true)
        } catch {
            message = ConnectionState.message(for: error)
        }
    }

    private func apply(_ match: ProviderMatch) async {
        applying = match.id
        defer { applying = nil }
        do {
            try await client.applyProviderMatch(
                itemId: itemId,
                providerKey: match.jellyfinProviderKey,
                providerId: match.providerId,
                name: match.title,
                year: match.year,
                posterURL: match.posterURL,
                extraProviderIds: seasonNumber == nil
                    ? [:] : ["TmdbSeason": String(chosenSeason)]
            )
            onDone(true)
        } catch {
            message = ConnectionState.message(for: error)
        }
    }
}
