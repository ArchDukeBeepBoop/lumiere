import SwiftUI

/// Text that clamps to a few lines with a MORE affordance, as Infuse does.
///
/// The point is honesty about truncation: a synopsis silently cut at three lines
/// looks like the whole synopsis, and there is no way to tell you are missing
/// the ending.
struct ExpandableText: View {
    let text: String
    var collapsedLines: Int = 3

    @State private var isExpanded = false
    @State private var isTruncated = false

    @Environment(\.isOnArtwork) private var isOnArtwork
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.secondaryText(onArtwork: isOnArtwork))
                .lineLimit(isExpanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    // Measures the same text unclamped and offscreen. SwiftUI has
                    // no "did this truncate?" signal, and showing MORE on text
                    // that already fits is its own small lie.
                    Text(text)
                        .font(Theme.Font.body)
                        .lineLimit(collapsedLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { clamped in
                                Text(text)
                                    .font(Theme.Font.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background {
                                        GeometryReader { full in
                                            Color.clear.onAppear {
                                                isTruncated = full.size.height
                                                    > clamped.size.height + 1
                                            }
                                        }
                                    }
                            }
                        }
                        .hidden()
                }

            if isTruncated {
                Button(isExpanded ? "LESS" : "MORE") {
                    withAnimation(Theme.Motion.transition) { isExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(Theme.Font.badge)
                .foregroundStyle(Theme.Palette.accent)
            }
        }
    }
}
