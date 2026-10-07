import SwiftUI
import LumiereKit

/// How a show or season says it has episodes left.
///
/// The folded corner is small, and on warm artwork — orange on an orange
/// poster — it all but vanishes, so a season ticked unwatched looked like
/// nothing had happened. The count says how many are left rather than only
/// that some are, and sits on its own dark ground so no poster can hide it.
/// Films and episodes keep the corner either way: one thing is either watched
/// or not, and a "1" says nothing the corner does not.
enum UnwatchedMarker: String, CaseIterable, Identifiable {
    case corner, count

    static let storageKey = "unwatchedMarker"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .corner: return "Corner"
        case .count: return "Episodes left"
        }
    }
}

/// The count, as a small pill.
struct UnwatchedCountBadge: View {
    let count: Int
    let isLarge: Bool

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: isLarge ? 13 : 11, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, isLarge ? 8 : 6)
            .padding(.vertical, isLarge ? 3 : 2)
            .background(Theme.Palette.unwatched, in: Capsule())
            .overlay { Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 1) }
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .padding(isLarge ? 8 : 6)
            .accessibilityLabel("\(count) unwatched")
    }
}

/// The Settings rows: whether to mark unwatched things at all, and how.
struct UnwatchedMarkerSettings: View {
    @AppStorage("showsUnwatchedBadges") private var showsUnwatchedBadges = true
    @AppStorage(UnwatchedMarker.storageKey) private var marker = UnwatchedMarker.corner

    var body: some View {
        Toggle("Unwatched indicators", isOn: $showsUnwatchedBadges)
        if showsUnwatchedBadges {
            Picker("On shows and seasons", selection: $marker) {
                ForEach(UnwatchedMarker.allCases) { Text($0.title).tag($0) }
            }
            Text("Episodes left shows how many are unwatched, on a dark edge "
               + "that stays visible on any poster. Films and episodes keep the corner.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
