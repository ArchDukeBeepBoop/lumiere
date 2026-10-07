import Foundation

/// A stretch of an episode the server has labelled — an opening, a recap, credits.
public struct MediaSegment: Decodable, Sendable, Identifiable, Hashable {
    public let id: String?
    public let type: String?
    public let startTicks: Int64?
    public let endTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }

    public var start: Double { Double(startTicks ?? 0) / 10_000_000 }
    public var end: Double { Double(endTicks ?? 0) / 10_000_000 }

    /// Whether this segment describes a real stretch of the file.
    ///
    /// `startTicks` is optional, and a missing one read as zero — so a credits
    /// segment that arrived without a start was a segment covering the whole
    /// episode from its first frame, and "Skip Credits" was offered over the
    /// opening titles. That is the wrong place by the width of an episode.
    ///
    /// An outro is additionally required to start somewhere: credits that begin
    /// at zero are not credits, whatever the server says. An intro or recap
    /// legitimately can, so the rule is applied only where it is true.
    public var isWellFormed: Bool {
        guard endTicks != nil, end > start else { return false }
        if isOutro { return startTicks != nil && start > 0 }
        return startTicks != nil || start == 0
    }

    /// What the skip button should say. Jellyfin's own vocabulary, mapped to the
    /// two labels anyone actually wants to see.
    public var skipLabel: String? {
        switch (type ?? "").lowercased() {
        case "intro": return "Skip Intro"
        case "recap": return "Skip Recap"
        case "preview": return "Skip Preview"
        case "outro", "credits": return "Skip Credits"
        default: return nil
        }
    }

    /// Credits are where "next episode" belongs; everything else is a plain skip.
    public var isOutro: Bool {
        ["outro", "credits"].contains((type ?? "").lowercased())
    }
}

private struct MediaSegmentsResponse: Decodable {
    let items: [MediaSegment]?
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

public extension JellyfinClient {
    /// Labelled segments for an item, when the server has them.
    ///
    /// `MediaSegments` is Jellyfin 10.10's own API, populated by whichever plugin
    /// the admin runs — Intro Skipper being the usual one. A server without it
    /// answers 404, which is why this returns an empty list rather than throwing:
    /// no segments is a perfectly ordinary state and must not read as an error
    /// behind a film that plays fine.
    /// The segment kinds worth a skip button. Sent one parameter each.
    static let segmentTypes = ["Intro", "Outro", "Recap", "Preview", "Commercial"]

    func mediaSegments(itemId: String) async throws -> [MediaSegment] {
        // Repeated parameters, not a comma-joined string. ASP.NET binds an array
        // from `?x=a&x=b`, so joining them handed the server a single value called
        // "Intro,Outro,Recap,Preview,Commercial" — which is not a segment type, so
        // every request 400'd and Skip Intro was dead on every episode in the
        // library. It failed quietly, because no segments is a normal state.
        if let segments = try? await fetchSegments(itemId: itemId, types: Self.segmentTypes) {
            // Logged on success too, and specifically the count. Silence used to
            // mean "worked", which is indistinguishable from "worked and returned
            // nothing" — and those need completely different fixes: one is this
            // app's problem, the other is a server with no segment provider.
            Diagnostics.log("[segments] \(itemId): \(segments.count) "
                          + (segments.isEmpty
                             ? "— the server has no segment data for this item"
                             : segments.map { $0.type ?? "?" }.joined(separator: ", ")))
            return segments
        }

        // Unfiltered retry, for a server whose vocabulary differs from this list —
        // asking for a type it has never heard of fails the whole request, where
        // asking for everything cannot. Anything unrecognised is dropped later by
        // `skipLabel` returning nil, so the filter was never load-bearing.
        if let segments = try? await fetchSegments(itemId: itemId, types: []) {
            Diagnostics.log("[segments] \(itemId) needed the unfiltered request: "
                          + "\(segments.count) found")
            return segments
        }

        Diagnostics.log("[segments] none for \(itemId)")
        return []
    }

    private func fetchSegments(
        itemId: String, types: [String]
    ) async throws -> [MediaSegment] {
        let response = try await send(
            MediaSegmentsResponse.self,
            path: "MediaSegments/\(itemId)",
            query: types.map { URLQueryItem(name: "includeSegmentTypes", value: $0) }
        )
        return response.items ?? []
    }
}
