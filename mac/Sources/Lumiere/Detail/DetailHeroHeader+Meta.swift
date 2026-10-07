import SwiftUI
import LumiereKit

/// The two lines of type under the hero's logo: what is selected, and what kind of
/// thing it is.
///
/// Split from DetailHeroHeader.swift for the project's 300-line limit.
extension DetailHeroHeader {

    /// The episode's own name, and only an episode's.
    ///
    /// A film or a show already has its name over the backdrop — as logo artwork,
    /// or as the fallback in exactly the same place — so an unconditional title
    /// line printed it twice, at two sizes, one under the other. On a series page
    /// it is the one piece of text the logo cannot carry: the logo is the show's,
    /// and what is selected is one episode of it.
    @ViewBuilder
    var titleLine: some View {
        if hero.item.itemType == .episode {
            Text(FolderTitle.title(
                for: hero, style: titleStyle, folderLibraryIds: folderLibraryIds
            ))
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Palette.onArtworkText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The name the show goes by in its own language.
    ///
    /// Half the anime library is better known by a romaji or Japanese title that
    /// appears nowhere in the display name. Search has always matched it — the
    /// original title is folded into the search key — so typing a romaji name
    /// found the show and then showed a page with no visible reason for the
    /// match. The data was decoded, migrated into its own column and indexed;
    /// the only thing missing was drawing it.
    ///
    /// Under the title rather than beside it, and quieter: this is the second
    /// name, not a competing one.
    @ViewBuilder
    var originalTitleLine: some View {
        if showsOriginalTitle, let original = distinctOriginalTitle {
            Text(original)
                .font(Theme.Font.detailMeta)
                .foregroundStyle(Theme.Palette.onArtworkTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Nil when the original title says nothing the displayed one does not.
    ///
    /// Compared through the search key's own normalisation, so "Kimi no Na wa."
    /// and "Kimi no Na Wa" are one title rather than two — otherwise every show
    /// whose provider punctuates differently would print its name twice.
    var distinctOriginalTitle: String? {
        guard let original = hero.item.originalTitle,
              !original.isEmpty,
              SearchKey.normalize(original) != SearchKey.normalize(hero.item.name)
        else { return nil }
        return original
    }

    /// Where you are, said before anything else.
    ///
    /// A partly-watched series opened on a synopsis you had already read, while
    /// the number of episodes left was a clause between the year and the genres.
    /// This is the review's "dominant fact": the one thing you came back to the
    /// page to find out.
    ///
    /// Drawn in the accent and at metadata size — loud enough to be read first,
    /// quiet enough not to compete with the logo above it. Absent entirely when
    /// there is nothing true to say, because a progress line on something never
    /// started is furniture.
    @ViewBuilder
    var dominantFactLine: some View {
        if leadsWithProgress, let fact = dominantFact {
            Text(fact)
                .font(Theme.Font.detailMeta)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Palette.accentOnArtwork)
                .lineLimit(1)
        }
    }

    var dominantFact: String? {
        if hero.item.itemType == .movie {
            return DominantFact.filmRemaining(
                runtimeSeconds: hero.item.runtimeSeconds,
                resumeSeconds: hero.userData?.resumeSeconds ?? 0
            )
        }
        return DominantFact.seasonProgress(episodes: seasonEpisodes)
    }

    /// One line, always. It is a caption for the logo above it, and a metadata
    /// line that wraps stops reading as one.
    var metadataLine: some View {
        Text(metadataParts.joined(separator: " · "))
            .font(Theme.Font.detailMeta)
            .foregroundStyle(Theme.Palette.onArtworkTextMuted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The TV app's classification line: "TV Show · Thriller · Drama".
    ///
    /// This line used to carry the year, the age rating and the resolution as
    /// well. Those are background details — you read them once, while deciding,
    /// and never again — so they moved to the About block at the foot of the page,
    /// where the TV app keeps its own. What is left is the two things the line is
    /// actually for: what kind of thing you are looking at, and what it is about.
    ///
    /// Genres did *not* move with them, and the About block has no genre row as a
    /// result. That is deliberate rather than an oversight: the TV app's About
    /// block has no genre row either, because this line already carries them, and
    /// listing them twice is exactly the duplication the move was meant to end.
    ///
    /// An episode keeps its own identity here — S1 E4, when it aired, how long it
    /// runs. That is not the same material as the About block below, which
    /// describes the *series*, not whichever episode the strip has selected.
    private var metadataParts: [String] {
        var parts: [String] = [kindLabel]
        if let code = episodeCode { parts.append(code) }
        if hero.item.itemType == .episode {
            if let when = airDateText { parts.append(when) }
            if let runtime = runtimeText { parts.append(runtime) }
        }
        let genres = self.genres.isEmpty ? artEntry.item.genreList : self.genres
        parts.append(contentsOf: genres.prefix(3))
        return parts
    }

    /// Taken from the hero rather than from `artEntry`: on a series page the art
    /// may come from the *season* — that is how a season gets its own backdrop —
    /// and "Season" is not a kind of thing anyone browses for.
    private var kindLabel: String {
        switch hero.item.itemType {
        case .episode, .series, .season: return "TV Show"
        case .movie: return "Film"
        case .boxSet: return "Collection"
        case .trailer: return "Trailer"
        default: return "Video"
        }
    }

    private var episodeCode: String? {
        guard hero.item.itemType == .episode else { return nil }
        return hero.item.episodeCode()
    }

    private var runtimeText: String? {
        guard let seconds = hero.item.runtimeSeconds else { return nil }
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// The full air date, not a bare year: on an episode the day is the thing
    /// worth knowing, and a year on its own says nothing about where in a run you
    /// are. A film's year is in the About block instead.
    private var airDateText: String? {
        guard let date = hero.item.premiereDate else {
            return hero.item.productionYear.map(String.init)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
