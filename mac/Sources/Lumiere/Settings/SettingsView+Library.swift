import SwiftUI
import LumiereKit

/// The Library, Home and Privacy panes. Split from SettingsView.swift for the
/// 300-line rule, and grouped by the question each answers rather than by the
/// part of the app a setting happens to touch.
extension SettingsView {

    /// Library: the server, what it knows, and keeping it in order.
    @ViewBuilder
    var libraryForm: some View {
        LibraryOverviewCard(app: app)
        if let repository = app.repository {
            LibraryLanguageDefaults(repository: repository, libraries: app.libraries)

            LibraryHealthCard(app: app)
            ServerScheduleCard(app: app)
            RemovedItemsCard(app: app)
        }

        metadataForm


        LocalFoldersCard(app: app)

        SettingsCard(title: "Server", icon: "server.rack") {
            if let session = app.client?.session {
                LabeledContent("Server", value: session.serverName)
                LabeledContent("Signed in as", value: session.userName)
                LabeledContent("Address", value: session.serverURL.absoluteString)
            } else {
                Text("Not connected.")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Button("Sign out") { isConfirmingSignOut = true }
                .foregroundStyle(Theme.Palette.danger)
                .confirmationDialog(
                    "Sign out of this server?",
                    isPresented: $isConfirmingSignOut,
                    titleVisibility: .visible
                ) {
                    Button("Sign Out", role: .destructive) { app.signOut() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    // Says the part that is not obvious. Forgetting *hidden items'*
                    // watch history is confirmed three sections down; this drops the
                    // entire local cache and was one misclick with no dialog at all.
                    Text("Clears the local cache — every synced item, and the artwork "
                       + "for it. Nothing on the server changes, including watch "
                       + "history, but signing back in re-syncs the whole library.")
                }
        }
    }


    /// Home: how it is laid out, what is on it, and in what order — all of it
    /// in one place. It was split between Look and Library, so changing what a
    /// shelf showed meant knowing which of two panes the rule lived in.
    @ViewBuilder
    var homeSettings: some View {
        homeForm
        if app.repository != nil {
            TopShelvesCard(libraries: app.libraries, app: app)
            RecentlyAddedCard(app: app)
            ShelfRulesCard(app: app)
        }
    }

    /// Privacy: which libraries are private, the room they open into, and
    /// what of them is shown or sent anywhere. It was in Advanced, as if
    /// keeping a library out of sight were a cache setting.
    @ViewBuilder
    var privacySettings: some View {
        PrivateLibrariesCard(app: app)
        if app.repository != nil {
            DiscreetArtCard(app: app)
        }
    }
}
