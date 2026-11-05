import SwiftUI
import LumiereKit

/// Split from FavouritesView.swift for the 300-line rule.
extension FavouritesView {
    var empty: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            // Starred people still show when no title is starred.
            FavouritePeopleRow(app: app, serverURL: serverURL, pipeline: pipeline)
                .padding(.top, Theme.Space.xl)
            EmptyStateView(reason: .empty(
                icon: "star",
                title: "No favourite titles yet",
                detail: "Star a title or a person from their page and they appear here, on every "
                      + "device signed into this server."
            ))
        }
    }
}
