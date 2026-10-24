import AppKit
import SwiftUI
import LumiereKit

/// Apple TV's idle screen: after a few minutes on Home with nothing touched,
/// the window fades to the spotlight's backdrops, drifting slowly, one after
/// another, each named in a corner. Any key, click or movement brings Home
/// back. The spotlight's titles, so nothing private appears, and never in the
/// private room.
struct ScreensaverHost: View {
    @Bindable var app: AppModel
    let isOnHome: Bool
    @AppStorage(Preference.screensaverMinutes.name) private var minutes = Preference.screensaverMinutes.defaultValue
    @State private var isShowing = false
    @State private var lastInput = Date()
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            if isShowing, let pipeline = app.imagePipeline, let serverURL = app.serverURL,
               let entries = app.homeModel?.heroEntries, !entries.isEmpty {
                ScreensaverView(entries: entries, pipeline: pipeline, serverURL: serverURL)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.slowFade, value: isShowing)
        .allowsHitTesting(isShowing)
        .onAppear { watchInput() }
        .onDisappear { monitor.map(NSEvent.removeMonitor); monitor = nil }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard minutes > 0, !isShowing, isOnHome, NSApp.isActive,
                      app.nowPlayingItemId == nil, !app.music.isFullscreen,
                      !app.isShowingPrivateLibraries,
                      Date().timeIntervalSince(lastInput) >= Double(minutes) * 60 else { continue }
                isShowing = true
            }
        }
    }

    /// Any input counts as someone there; the first one only wakes the screen.
    private func watchInput() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        ) { event in
            lastInput = Date()
            if isShowing {
                isShowing = false
                return nil
            }
            return event
        }
    }
}

struct ScreensaverView: View {
    let entries: [LibraryEntry]
    let pipeline: ImagePipeline
    let serverURL: URL
    @State private var index = 0
    @State private var drift = false
    @Environment(\.displayScale) private var scale
    /// System Settings › Accessibility › Display › Reduce motion: no drift,
    /// and the pictures change by a cut rather than a crossfade.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let entry = entries[index % entries.count]
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Theme.Palette.videoGround
                RemoteImage(
                    request: .backdrop(for: entry, serverURL: serverURL, width: geometry.size.width,
                                       scale: scale, preferSeriesThumb: true),
                    pipeline: pipeline
                )
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(drift ? 1.12 : 1.0, anchor: index.isMultiple(of: 2) ? .topLeading : .bottomTrailing)
                .clipped()
                .id(entry.id)
                .transition(.opacity)
                Text(entry.item.seriesName ?? entry.item.name)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.onArtworkTextMuted)
                    .shadow(color: .black.opacity(0.7), radius: 8)
                    .padding(Theme.Space.xxl)
            }
        }
        .ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                drift = false
                if !reduceMotion { withAnimation(Theme.Motion.drift) { drift = true } }
                try? await Task.sleep(for: .seconds(10))
                withAnimation(reduceMotion ? nil : Theme.Motion.slowFade) { index += 1 }
            }
        }
    }
}
