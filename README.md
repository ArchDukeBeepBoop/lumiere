# Lumiere

**Your films, shows, anime and music — from your own disks, on your Mac, phone and TV.**

Lumiere is a local-first media server with native apps, designed to feel like
Apple TV: a floating sidebar, full-bleed spotlights, Up Next, a calm player with
trickplay previews, and nothing between you and your files. No accounts in the
cloud, no tracking, no subscriptions. It runs on one Mac and serves your home
network.

| Folder | What it is | Built with |
|---|---|---|
| [`server/`](server) | The media server: scans your folders, reads every file with ffprobe, fetches posters and details, streams to the apps | Go, SQLite |
| [`control/`](control) | A menu-bar app that carries the server and keeps it running | Swift, AppKit |
| [`mac/`](mac) | The Mac app | Swift, SwiftUI, libmpv |
| [`android/`](android) | The phone and Android TV / projector app | Kotlin, Jetpack Compose, Media3 |

## Highlights

- **Guided first run.** Create your account, add libraries and the folders that feed them, choose your rooms, add a movie-database key, make a few choices. Every step is also in Settings › Your Setup, which lists your libraries, their folders, and every setting you have changed.
- **Libraries the way you keep them.** Films, TV & anime, music (with synced lyrics), home videos, or plain folders. Several folders can feed one library.
- **Two rooms.** A Main Room, and a Private Room for libraries you'd rather keep to yourself — off Home, search and Continue Watching until you open it, with Touch ID, blurred covers and its own settings.
- **Collections that make themselves.** Film series are gathered into collections room by room, with posters and overviews; identify, scan or discover more by hand.
- **A player worth using.** Direct play whenever possible (AVPlayer or libmpv), chapter thumbnails, skip intro and recap, Up Next at the credits, dialogue enhancement, picture in picture, and subtitle search with automatic sync.
- **Live everywhere.** A change feed keeps every device current within a second; watched state and favourites made offline are delivered later.

## Getting started

1. **Build and start the server** (Go 1.27+, `ffmpeg`/`ffprobe` on the path):
   ```bash
   cd server && go build -o lumiered ./cmd/lumiered && ./lumiered
   ```
   It listens on `127.0.0.1:8098` and keeps its database in `~/Library/Application Support/LumiereServer`. Or build `control/` (`./Scripts/bundle.sh release && ./Scripts/install.sh`), which carries the server and starts it at login.
2. **Build the Mac app** (Command Line Tools; `brew install mpv`):
   ```bash
   cd mac && ./Scripts/install.sh
   ```
3. **Open Lumiere.** It finds the server, asks you to create your account, and walks you through adding your libraries.
4. **Phone and TV:** in the Mac app, turn on Settings › Library › Server Schedule › *Share on my home network*, then build the Android app (`cd android && ./gradlew assembleStandardRelease`) and install it. It finds the server on your Wi-Fi, and the same guide runs there.

### Posters and details

Lumiere looks titles up on [The Movie Database](https://www.themoviedb.org). Make a free account, request an API key, and paste the *API Read Access Token* into the setup guide (or Settings). The key is kept on your server only. Without one, everything still works: titles come from filenames and pictures from the videos themselves.

Subtitle search uses [OpenSubtitles](https://www.opensubtitles.com) with your own key, set in Settings › Playback.

### Meta Quest 3

The Quest build is the TV layout in a Horizon OS window, while a full spatial app is planned in [docs/quest/PLAN.md](docs/quest/PLAN.md). With the headset in developer mode and plugged in, one command builds and installs both Quest apps and opens the spatial one: `android/Scripts/install-quest.sh` (pass `2d` or `spatial` for just one). By hand:
```bash
cd android && ./gradlew assembleQuestRelease
adb install -r app/build/outputs/apk/quest/release/app-quest-release.apk
```
It appears under Unknown Sources in the app library. It doesn't update itself; install a newer build the same way.

**In your room (in development):** `:quest` is the spatial app. It turns on passthrough and places Lumiere's window in front of you, curved and movable: pinch its edge, or grip it with a controller. It installs beside the 2D build as *app.lumiere.android.spatial*:
```bash
cd android && ./gradlew :quest:assembleRelease
adb install -r quest/build/outputs/apk/release/quest-release.apk
```
On a Quest the private room asks for Lumiere's own PIN, since the headset has no fingerprint or face to ask for. You choose the PIN the first time you open the room. Five wrong PINs in a row make the pad wait 30 seconds, and the wait doubles each time after that.

## Development

Each folder has its own check script, and all must be green before a commit:

```bash
(cd server && go vet ./... && go test ./...)
(cd mac && ./Scripts/check.sh)
(cd control && ./Scripts/check.sh)
(cd android && ./gradlew :core:testDebugUnitTest :screens:testDebugUnitTest testStandardDebugUnitTest testQuestDebugUnitTest :quest:assembleRelease)
```

`mac/Scripts/ship-all.sh` runs every check, builds both Mac apps, and installs them. Source files are kept under 300 lines.

## Notes

- Lumiere's server speaks a Jellyfin-compatible subset of routes so the apps share one vocabulary, but it is its own server and does not need Jellyfin.
- Subtitle fonts: Lumiere ships with Asap Condensed (SIL Open Font License). Add your own in Settings › Playback › Subtitle Fonts.
- Lumiere does not include, link to or help find any media. Use it with files you have the right to watch.

## License

[GNU General Public License v3.0](LICENSE). Lumiere bundles libmpv (LGPL/GPL) in release builds of the Mac app.
