import SwiftUI
import LumiereKit

/// The first-run guide: from an empty server to something to watch.
///
/// Opens by itself on a new server (no libraries, or an account just made),
/// and again from Settings › Your Setup. Every step writes the same settings
/// Settings shows, so nothing set here is hidden anywhere afterwards — and
/// every step can be skipped.
struct SetupGuide: View {
    @Bindable var app: AppModel
    @State var step: Step = .welcome

    /// Whether the guide has been finished or dismissed on this Mac.
    static let doneKey = "setupGuideDone"

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, libraries, rooms, details, yours, ready
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .libraries: return "Libraries"
            case .rooms: return "Rooms"
            case .details: return "Posters & Details"
            case .yours: return "Make It Yours"
            case .ready: return "Ready"
            }
        }

        var icon: String {
            switch self {
            case .welcome: return "sparkles"
            case .libraries: return "books.vertical"
            case .rooms: return "door.left.hand.open"
            case .details: return "photo.on.rectangle"
            case .yours: return "slider.horizontal.3"
            case .ready: return "play.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    page.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.xxl)
                }
                Divider()
                footer.padding(Theme.Space.lg)
            }
        }
        .frame(width: 820, height: 600)
        .background(Theme.Palette.canvas)
        .animation(Theme.Motion.transition, value: step)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 44, height: 44)
                .padding(.bottom, Theme.Space.md)
            ForEach(Step.allCases) { item in
                Button { step = item } label: {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: item.rawValue < step.rawValue ? "checkmark.circle.fill" : item.icon)
                            .frame(width: 20)
                        Text(item.title).font(Theme.Font.body.weight(item == step ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Space.sm).padding(.vertical, 7)
                    .foregroundStyle(item == step ? Theme.Palette.canvas : Theme.Palette.textPrimary)
                    .background { if item == step { Capsule().fill(Theme.Palette.textPrimary) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(Theme.Space.lg)
        .frame(width: 210)
        .background(Theme.Palette.chrome.opacity(0.5))
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
            }
            Spacer()
            if step != .ready {
                Button("Finish Later") { finish() }.buttonStyle(.link)
            }
            Button(step == .ready ? "Start Watching" : step == .welcome ? "Get Started" : "Continue") {
                if let next = Step(rawValue: step.rawValue + 1) { step = next } else { finish() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcomePage
        case .libraries: librariesPage
        case .rooms: roomsPage
        case .details: SetupDetailsPage(app: app)
        case .yours: SetupPreferencesPage()
        case .ready: SetupReadyPage(app: app)
        }
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        app.isShowingSetupGuide = false
    }
}

/// A step's heading and the sentence under it.
struct SetupHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(Theme.Font.title).foregroundStyle(Theme.Palette.textPrimary)
            Text(detail).font(Theme.Font.body).foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, Theme.Space.lg)
    }
}
