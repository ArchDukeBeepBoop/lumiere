import SwiftUI
import LumiereKit

struct RootView: View {
    @Bindable var app: AppModel
    let bridge: PlayerBridge
    @State private var signIn = SignInModel()
    /// The window's backing. Stored rather than derived so it survives a restart,
    /// and defaulted on because it is what was asked for — the flat canvas is still
    /// one switch away in Settings for anyone reading subtitles over a busy desktop.
    @AppStorage("glassBackground") private var isGlass = true
    /// How much canvas sits over the blur. Below about a third the wallpaper starts
    /// competing with poster art, which is the failure mode of every translucent
    /// media app.
    @AppStorage("glassOpacity") private var glassOpacity = 0.62
    /// Standard or Paper. See `PaperTheme`.
    @AppStorage(PaperTheme.storageKey) private var theme = "standard"

    var body: some View {
        Group {
            if app.isRestoring {
                // Not the sign-in form: the session may well be there, and showing
                // "sign in" for the moment it takes to read the stored session is
                // a lie, even a brief one.
                //
                // The same launch screen the shell shows, rather than the bare
                // spinner that used to be here. Startup is one continuous thing to
                // watch, and it was two: a naked spinner on the window's glass for
                // the first few seconds, then a completely different screen with the
                // icon and a status line once the shell appeared. Reading the
                // Keychain is also where a launch can stop dead on a password
                // prompt, which is exactly when saying what is happening earns most.
                LaunchView(status: "Unlocking your account")
            } else if app.isSignedIn {
                // Rebuilt on a theme change: the palette resolves colours when
                // drawn, and a view that is not redrawn keeps the old ones.
                ShellView(app: app, bridge: bridge).id(theme)
            } else {
                SignInView(model: signIn)
            }
        }
        // The grain sits over the page colour and under everything else: this
        // background is layered above the one glassBackground adds below it.
        .background { PaperGrainLayer().ignoresSafeArea() }
        // Paper is opaque stock: no desktop showing through it.
        .glassBackground(isGlass && theme != PaperTheme.paper, opacity: glassOpacity)
        .preferredColorScheme(theme == PaperTheme.paper ? .light : nil)
        .onAppear {
            signIn.onSignedIn = { client in
                Task { await app.signedIn(client) }
            }
        }
        .task {
            await app.restoreSession()
            // Not awaited. Probing libmpv is `mpv_create` + `mpv_initialize` +
            // destroy, and the first core init in a process costs 0.57s — measured
            // against this very dylib, with the second and third probes at 0.026s,
            // so it is one-time ffmpeg and option-table setup rather than anything
            // this app controls. Awaiting it put that 0.57s between the saved
            // session and the first query, with nothing else in flight and the
            // launch screen up. Nothing on the home path reads the result: the
            // first readers are the player and the settings screen, minutes later.
            app.mpvProbe = Task { await app.probeMPV() }
            // LUMIERE_DEMO=1 seeds a synthetic library so the UI can be built and
            // measured without a server. Does nothing otherwise.
            if DemoFixtures.isEnabled {
                await app.enterDemoMode()
            } else {
                await app.start()
            }
        }
    }
}
