import SwiftUI
import LumiereKit

/// The Info tab: what is playing, in a few lines — Apple TV's swipe-down
/// panel, opened here with I. The title and its line, the year, rating and
/// length, and the synopsis.
struct PlayerInfoRows: View {
    let model: PlayerModel
    @State private var item: ItemRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(model.title)
                .font(Theme.Font.playerTitle)
                .foregroundStyle(Theme.Palette.onPlayerChrome)
            if let line = model.subtitleLine {
                Text(line)
                    .font(Theme.Font.playerSubtitle)
                    .foregroundStyle(Theme.Palette.onPlayerChrome.opacity(0.75))
            }
            if !facts.isEmpty {
                Text(facts.joined(separator: "  ·  "))
                    .font(Theme.Font.playerRow)
                    .foregroundStyle(Theme.Palette.onPlayerChrome.opacity(0.75))
            }
            if let overview = item?.overview, !overview.isEmpty {
                Text(overview)
                    .font(Theme.Font.playerRow)
                    .foregroundStyle(Theme.Palette.onPlayerChrome.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .task(id: model.itemId) {
            item = try? await model.repository.entry(id: model.itemId)?.item
        }
    }

    private var facts: [String] {
        guard let item else { return [] }
        var out: [String] = []
        if let year = item.productionYear { out.append(String(year)) }
        if let rating = item.officialRating { out.append(rating) }
        if let ticks = item.runTimeTicks, ticks > 0 {
            let minutes = Int(ticks / 600_000_000)
            out.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
        if let stars = item.communityRating { out.append(String(format: "★ %.1f", stars)) }
        return out
    }
}
