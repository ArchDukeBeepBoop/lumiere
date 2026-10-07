import SwiftUI
import LumiereKit

/// The line of facts under the hero's title, and the badges beside it.
///
/// Split from HeroBackdrop.swift for the project's 300-line rule. Both answer the
/// same question — what this title *is*, in the fewest words the artwork will
/// tolerate — and both are pure reads of the entry with no layout of their own.
extension HeroBackdrop {

    var metadataParts: [String] {
        var parts: [String] = []

        if entry.item.itemType == .episode, let code = entry.item.episodeCode() {
            parts.append(code)
            parts.append(entry.item.name)
        } else if let year = entry.item.productionYear {
            parts.append(String(year))
        }

        if let runtime = entry.item.runtimeSeconds {
            let minutes = Int(runtime / 60)
            parts.append(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
        }
        if let rating = entry.item.officialRating {
            parts.append(rating)
        }
        let genres = entry.item.genreList.prefix(2)
        if !genres.isEmpty {
            parts.append(genres.joined(separator: ", "))
        }
        if let community = entry.item.communityRating {
            if let starred = Rating.starred(community) { parts.append(starred) }
        }
        return parts
    }

    /// Phase 4 fills these from the real media source. Until then the hero shows
    /// resolution only, derived from what the list sync already cached.
    var badges: [(String, Badge.Role)] {
        []
    }
}
