import SwiftUI

/// A card with its Top 10 rank set beside it, as the TV app's rows are: a
/// tall, faint numeral the card overlaps a little, so the row reads as a
/// countdown before any title is read.
struct RankedCard<Card: View>: View {
    let rank: Int
    @ViewBuilder let card: Card

    var body: some View {
        HStack(alignment: .bottom, spacing: -Theme.Art.rankOverlap) {
            Text("\(rank)")
                .font(Theme.Font.rankNumeral)
                .foregroundStyle(Theme.Palette.rankNumeral)
                .lineLimit(1)
                // "10" is two digits in the room of one; it narrows rather
                // than pushing its poster out of line with the rest.
                .minimumScaleFactor(0.55)
                .frame(width: Theme.Art.rankNumeralWidth, alignment: .trailing)
                .accessibilityHidden(true)
            card
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Number \(rank)")
    }

    /// The width a ranked card takes in a row: its numeral, less the overlap,
    /// and the card.
    static func width(card: CGFloat) -> CGFloat {
        Theme.Art.rankNumeralWidth - Theme.Art.rankOverlap + card
    }
}
