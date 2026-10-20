import WidgetKit
import SwiftUI

/// Continue Watching on the desktop and in Notification Center.
///
/// Built outside SwiftPM by `Scripts/bundle.sh`, as an app extension inside
/// Lumiere.app. Sandboxed, as every widget is, so it cannot read the app's
/// sign-in: it reads the server's loopback-only widget feed, which never
/// lists a private library and can be switched off in Settings.
@main
struct LumiereWidgets: WidgetBundle {
    var body: some Widget { ContinueWatchingWidget() }
}

struct Tile: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let progress: Double
    let image: NSImage?
}

struct Entry: TimelineEntry {
    let date: Date
    let tiles: [Tile]
    let reachable: Bool
}

struct Provider: TimelineProvider {
    static let server = URL(string: "http://127.0.0.1:8098")!

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, tiles: [Tile(id: "", title: "Continue Watching", subtitle: "Episode", progress: 0.4, image: nil)],
              reachable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let entry = await load()
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    private struct Feed: Decodable {
        struct Item: Decodable {
            let Id: String
            let Title: String
            let Subtitle: String
            let Progress: Double
        }
        let Items: [Item]
    }

    private func load() async -> Entry {
        guard let (data, _) = try? await URLSession.shared.data(from: Self.server.appending(path: "Lumiere/Widget")),
              let feed = try? JSONDecoder().decode(Feed.self, from: data)
        else { return Entry(date: .now, tiles: [], reachable: false) }
        var tiles: [Tile] = []
        for item in feed.Items {
            var url = Self.server.appending(path: "Lumiere/Widget/Items/\(item.Id)/Images/Primary")
            url.append(queryItems: [URLQueryItem(name: "maxWidth", value: "480")])
            let image = (try? await URLSession.shared.data(from: url)).flatMap { NSImage(data: $0.0) }
            tiles.append(Tile(id: item.Id, title: item.Title, subtitle: item.Subtitle,
                              progress: item.Progress, image: image))
        }
        return Entry(date: .now, tiles: tiles, reachable: true)
    }
}

struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueWatching", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off in Lumiere.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.tiles.isEmpty {
                empty
            } else if family == .systemSmall {
                hero(entry.tiles[0])
            } else {
                list
            }
        }
        .containerBackground(for: .widget) { Color(red: 0.08, green: 0.08, blue: 0.09) }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: entry.reachable ? "play.rectangle" : "server.rack").font(.title2)
            Text(entry.reachable ? "Nothing to resume" : "Lumiere's server isn't running")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }

    private func hero(_ tile: Tile) -> some View {
        ZStack(alignment: .bottomLeading) {
            art(tile)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(tile.title).font(.headline).lineLimit(2)
                if !tile.subtitle.isEmpty { Text(tile.subtitle).font(.caption2).lineLimit(1).opacity(0.8) }
                bar(tile.progress)
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .widgetURL(URL(string: "lumiere://item/\(tile.id)"))
        .padding(-16)
    }

    private var list: some View {
        let count = family == .systemLarge ? 4 : 2
        return VStack(alignment: .leading, spacing: 8) {
            Label("Continue Watching", systemImage: "play.fill").font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.79, green: 0.64, blue: 0.15))
            ForEach(entry.tiles.prefix(count)) { tile in
                Link(destination: URL(string: "lumiere://item/\(tile.id)")!) {
                    HStack(spacing: 10) {
                        art(tile).frame(width: family == .systemLarge ? 110 : 96, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if !tile.subtitle.isEmpty {
                                Text(tile.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            bar(tile.progress)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func art(_ tile: Tile) -> some View {
        if let image = tile.image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName: "film").foregroundStyle(.secondary))
        }
    }

    private func bar(_ progress: Double) -> some View {
        GeometryReader { g in
            Capsule().fill(.white.opacity(0.25))
                .overlay(alignment: .leading) {
                    Capsule().fill(Color(red: 0.79, green: 0.64, blue: 0.15))
                        .frame(width: g.size.width * min(1, max(0, progress)))
                }
        }
        .frame(height: 3)
    }
}
