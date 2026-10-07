import Foundation
import LumiereKit

/// Skip prompts and episode-to-episode movement.
///
/// Both exist for the same reason: a season is watched in a sitting, and anything
/// that makes you leave the player between episodes — or sit through ninety seconds
/// of the same opening — is friction the player itself should absorb.
extension PlayerModel {

    /// What the player should be offering right now, if anything.
    enum Prompt: Hashable {
        case skip(label: String, to: Double)
        case nextEpisode(title: String)
        /// "Resuming from 42:15 — Start Over".
        ///
        /// Playback that begins in the middle needs to say so. Every other
        /// player does — it is the difference between trusting the resume and
        /// scrubbing backwards to check whether you missed something — and
        /// without it the only signal is a scrubber that is already part-full.
        case resumed(from: Double)
    }

    /// Loads the labelled segments and the surrounding episodes.
    ///
    /// Both are best-effort. A server with no segment plugin, or a film with no
    /// siblings, simply yields no prompts — none of this is load-bearing for
    /// playback and none of it should be able to fail a session.
    func loadEpisodeContext() async {
        // The markers come from the server; everything below comes from this
        // Mac's cache. Asked for side by side, so Next and Previous no longer
        // wait on a round trip they do not need.
        let client = self.client, itemId = self.itemId
        let markers = Task { (try? await client.mediaSegments(itemId: itemId)) ?? [] }
        defer { Task { @MainActor in self.segments = await markers.value } }

        guard let entry = try? await repository.entry(id: itemId),
              entry.item.itemType == .episode,
              let seriesId = entry.item.seriesId
        else { return }

        // Learned per season: a show's opening usually changes with the season,
        // and a skip learned on season one's landed mid-song on season two's.
        // A show learned before this keeps its answer as the fallback.
        introSeriesId = entry.item.seasonId ?? seriesId
        learnedIntro = try? await repository.learnedIntro(seriesId: introSeriesId ?? seriesId)
        if learnedIntro == nil {
            learnedIntro = try? await repository.learnedIntro(seriesId: seriesId)
        }

        let siblings = (try? await repository.episodes(
            seriesId: seriesId, seasonId: entry.item.seasonId
        )) ?? []
        guard let index = siblings.firstIndex(where: { $0.id == itemId }) else { return }

        queue = siblings
        queueIndex = index
        previousEpisode = index > 0 ? siblings[index - 1] : nil
        nextEpisode = index + 1 < siblings.count ? siblings[index + 1] : nil

        // At either end of the season, the neighbouring season's first or
        // last episode — so the last episode of season one offers season two.
        guard Preference.continuesAcrossSeasons.value,
              previousEpisode == nil || nextEpisode == nil,
              let seasons = try? await repository.seasons(seriesId: seriesId)
        else { return }
        let specials = Preference.includesSpecialsInOrder.value
        if nextEpisode == nil,
           let season = SeasonNeighbours.following(entry.item.seasonId, in: seasons, includesSpecials: specials) {
            nextEpisode = try? await repository.episodes(seriesId: seriesId, seasonId: season.id).first
        }
        if previousEpisode == nil,
           let season = SeasonNeighbours.preceding(entry.item.seasonId, in: seasons, includesSpecials: specials) {
            previousEpisode = try? await repository.episodes(seriesId: seriesId, seasonId: season.id).last
        }
    }

    /// The prompts for the current position, in the order they are drawn.
    ///
    /// Both, where both apply — they used to compete for one corner and the skip
    /// always won, on the reasoning that "Skip Credits gets you to the next episode
    /// anyway". It does not: skipping the credits leaves you at the end of the file
    /// you have finished, and the offer to start the next one is the thing you
    /// actually wanted. Over the last stretch of an episode both are true at once and
    /// both are useful, so both are offered, side by side in one row.
    var activePrompts: [Prompt] {
        var prompts: [Prompt] = []
        // First, and briefly. It answers a question you have in the first few
        // seconds and nowhere else, so it retires on its own rather than waiting
        // to be dismissed — unlike the other two, which retire when the moment
        // they belong to passes.
        if let from = resumedFrom, position < from + Self.resumeNoticeSeconds {
            prompts.append(.resumed(from: from))
        }
        if let segment = segments.first(where: {
            // `isWellFormed` first: a segment with no start read as starting at
            // frame zero, which offered Skip Credits over the opening titles.
            // And credits only where credits could be — see `SegmentTrust` for
            // the fourteen hundred that began five minutes early.
            $0.isWellFormed && $0.skipLabel != nil
                && (Preference.offersRecapSkip.value
                    || !["recap", "preview"].contains(($0.type ?? "").lowercased()))
                && (!$0.isOutro || SegmentTrust.isPlausibleOutro(
                    start: $0.start, end: $0.end, duration: duration,
                    floorMinutes: Preference.creditsWindowMinutes.value))
                && position >= $0.start && position < $0.end - 1
        }), let label = segment.skipLabel {
            prompts.append(.skip(label: label, to: segment.end))
        }

        // A learned intro, where the server offered no segment for this moment.
        // Second in the list so a real segment always wins the corner: the
        // server's answer is authoritative and this one is inferred.
        if prompts.isEmpty || !prompts.contains(where: { if case .skip = $0 { true } else { false } }),
           IntroLearning.shouldOffer(learnedIntro, at: position),
           let intro = learnedIntro {
            prompts.append(.skip(label: "Skip Intro", to: intro.end))
        }

        // No labelled outro: fall back to the last stretch of the file. Most servers
        // have no segment plugin at all, and "next episode near the end" is the part
        // of this that everyone expects to work regardless.
        // From the start of believable credits, or the last 45 seconds where
        // there are none: an anime ending runs ninety seconds, and the offer
        // used to arrive halfway through it.
        let creditsStart = segments
            .filter { $0.isOutro && $0.isWellFormed && SegmentTrust.isPlausibleOutro(
                start: $0.start, end: $0.end, duration: duration,
                floorMinutes: Preference.creditsWindowMinutes.value) }
            .map(\.start).min() ?? .infinity
        if let next = nextEpisode, duration > 0, position > min(duration - 45, creditsStart) {
            prompts.append(.nextEpisode(title: next.item.name))
        }
        return prompts
    }

    /// How long the resume notice stays offered.
    ///
    /// Eight seconds of *playback*, not wall clock: pausing to read it should
    /// not spend the time it is offered for.
    static let resumeNoticeSeconds: Double = 8

    /// Jumps past a segment, and offers to put it back.
    ///
    /// - Parameter label: the prompt's own words — "Skip Intro", "Skip Recap",
    ///   "Skip Preview", "Skip Credits". Passed in rather than assumed: this was
    ///   hardcoded to "Skipped intro", so skipping the credits announced that
    ///   the intro had been skipped.
    func skip(to seconds: Double, label: String = "Skip Intro", automatic: Bool = false) async {
        let from = position
        // A skip asked for counts towards skipping it automatically. See AutoSkip.
        if !automatic, label == "Skip Intro", let key = introSeriesId { AutoSkip.record(key) }
        await seek(to: seconds)
        // Only a real jump is worth offering to undo. Nudging past a few seconds
        // of a recap is not something anybody needs a notice about.
        guard seconds - from > 20 else { return }
        // "Skip Intro" -> "Skipped intro". The undo is here because the button
        // is small, sits under the cursor mid-film, and a mis-click costs you
        // your place — not because the player skipped anything on its own. It
        // never does; every jump here is one somebody asked for.
        let what = label.replacingOccurrences(of: "Skip ", with: "").lowercased()
        lastAction = PlayerAction(text: "Skipped \(what)", returnTo: from)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.lastAction?.returnTo == from else { return }
            self.lastAction = nil
        }
    }

    /// Puts back what the player did on its own.
    func undoLastAction() async {
        guard let action = lastAction else { return }
        lastAction = nil
        await seek(to: action.returnTo)
    }

    /// Starts the file again from the top, and retires the notice.
    func startOver() async {
        resumedFrom = nil
        await seek(to: 0)
    }
}
