import SwiftUI
import LumiereKit

/// Split from FavouritesView.swift for the 300-line rule.
extension FavouritesView {
    var empty: some View {
        EmptyStateView(reason: .empty(
            icon: "star",
            title: "No favourites yet",
            detail: "Star something from its page and it will appear here, on every "
                  + "device signed into this server."
        ))
    }
}
