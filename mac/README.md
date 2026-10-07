# Lumiere for Mac

The Mac app: a cinematic library, playback that never makes the server
transcode when it can avoid it, and a memory footprint small enough that
leaving it open costs nothing. It talks to Lumiere's own server (`../server`);
see the [top-level README](../README.md) for the whole picture.

## Requirements

- macOS 14 or later
- Homebrew's mpv to build (`brew install mpv`); the bundled app carries its own copy

## Building

This repo builds with SwiftPM and the Command Line Tools; it does not need Xcode.

```bash
./Scripts/check.sh
```

```bash
./Scripts/bundle.sh release
```

To install it where you can actually launch it:

```bash
./Scripts/install.sh
```

That builds a release bundle and `ditto`s it to `/Applications/Lumiere.app`. `ditto`
rather than `cp -R`, which quietly breaks a bundle's signature; and it refuses to
overwrite a copy that is currently running, since swapping dylibs under a live
process crashes it for reasons that look unrelated an hour later.

The icon is drawn by a script rather than maintained as a binary:

```bash
./Scripts/make-icon.py
```

`Scripts/make-icon.py` draws it from geometric primitives in the same two colours
as the app — ink `#0D0F12` and the gold `#C9A227` — and runs `iconutil` to produce
`Resources/Lumiere.icns`. The script is the source of truth, so a change to the icon
is a readable diff; the generated `.icns` is committed as well so that bundling
never depends on Pillow. This matters more than usual here — no Xcode means no
asset catalog to hold the icon for us.

`bundle.sh` assembles `build/Lumiere.app` by hand — layout, `Info.plist`, dylib
relocation and ad-hoc signing — because without Xcode there is no `xcodebuild` to do it.
The `release` argument additionally runs `Scripts/vendor-dylibs.sh`, which copies libmpv
and every Homebrew library it transitively links into `Contents/Frameworks` and rewrites
the install names to `@rpath`.

Building from source does require Homebrew's mpv (`brew install mpv`), since the headers
are read from `/usr/local/opt/mpv/include`. Running the bundled app does not.

## Playback

Every file goes through one pure function, `PlaybackPlanner.decide`, which picks the
cheapest path that will actually work:

| Plan | When | Engine |
|---|---|---|
| `.directPlayAV` | mp4/m4v/mov, H.264 or HEVC, AAC/AC3/EAC3, no rendered subtitles | AVPlayer |
| `.directPlayMPV` | Everything AVPlayer refuses — MKV, DTS/TrueHD/FLAC/Opus, PGS/VobSub/ASS | libmpv |
| `.remux` | Streams are fine, container isn't, and mpv is unavailable | Lumiere server |
| `.transcode` | The codec genuinely can't be decoded here, or bandwidth is capped | Lumiere server |

The decision is made from `/Items/{id}/PlaybackInfo` plus a hardware capability probe
(`VTIsHardwareDecodeSupported`), never from assumptions about the machine. On this Intel
Mac the probe reports no AV1 and no HEVC-in-hardware beyond 8-bit, and the engine plans
around that rather than pretending otherwise.

`decide` does no I/O and is unit-tested against a table of real-world source shapes.

## Memory

The budget from the plan is **≤180 MB browsing** and **≤400 MB in playback**, measured as
`phys_footprint` — the number Activity Monitor shows and the one the memory-pressure
system acts on. RSS is not used here: it counts shared, clean framework pages that are not
this app's cost, and on Lumiere it overstates the footprint by roughly 70 MB.

Reproduce any of these with:

```bash
./Scripts/measure-memory.sh library
```

Measured on the development machine — a 2018 Intel i7-8750H, macOS 14, release build,
against the demo library (real SQLite rows and real generated JPEGs, no server):

| Scenario | Peak `phys_footprint` | Budget | |
|---|---|---|---|
| Home shelves idle | 118 MB | 180 MB | pass, 62 MB spare |
| **1000-item library, full grid open** | **105 MB** | 180 MB | pass, 75 MB spare |
| Sustained 4K HEVC HDR10 playback, 10 min | 323 MB | 400 MB | pass, 77 MB spare |

The playback figure rises from 289 MB to 323 MB over the first few minutes and then
holds flat, which is cache fill rather than a leak.

The 1000-item grid costs *less* than the home screen, and holds at 105 MB without
moving — home renders several shelves at different poster sizes plus a hero backdrop,
while the grid renders one viewport. That the number does not scale with library size
is the point of rule 4 below; a 1000-item library and a 180-item one cost the same.

One honest caveat: generating the demo library's 1000 posters on first launch peaks at
207 MB. That is the test harness creating JPEGs, not a path a real user takes — against
a server, artwork is downloaded and decoded at display size.

### What the audit found

Both playback numbers started out far worse, and both bugs were invisible until the
measurement got honest. The stock fixtures are 6–8 seconds long, so every earlier
"playback" measurement was really measuring start-up. Against a loop-muxed 12-minute
4K file:

1. **~700 MB.** `cache=yes` turned mpv's demuxer cache on for local files, where the
   OS page cache already does the job, with a 150 MiB readahead sized for a slow
   internet stream. Now `cache=auto` with a 32 MiB readahead and an explicitly named
   16 MiB back buffer — unnamed, the back buffer quietly adds its own 50 MiB. → 488 MB.
2. **488 MB.** Still over, so rather than guess again the categories got read:
   `MALLOC_MEDIUM` held 143 MB across 12 regions of 12 MB each — exactly one 4K NV12
   frame — while `IOSurface` sat at 416 KB. That is `hwdec=videotoolbox-copy` doing
   what it says and reading every decoded frame back into system memory. Zero-copy
   `videotoolbox` leaves them on the GPU. → 323 MB.

Because mpv will accept a file and report playback while never drawing a picture —
a failure with no visible symptom on a machine being driven headlessly —
`MPVVideoView` counts frames actually drawn and logs the count under
`LUMIERE_MPV_TRACE=1`. That counter is what proves the zero-copy path renders rather
than silently going blank.



### Leaks

`leaks` against a live process, browsing and during playback:

| State | Result |
|---|---|
| 1000-item library, browsing | 1 leak, 16 bytes — an AppKit `Clipboard` internal |
| 4K playback | 12–13 leaks, 208–640 bytes |

The playback figure is a fixed handful of small allocations, not a per-frame leak: two
passes minutes apart, thousands of rendered frames apart, returned the same ~12 count.
Nothing in Lumiere's own object graph is retained — the player removes its time and
end-of-item observers explicitly, and the mpv render context is torn down from
`stop()` rather than from a `deinit` that would race the render callback.

### Where the discipline lives

The numbers above are a consequence of five rules, all in `LumiereKit/Images` and
`LumiereKit/Library`:

1. **Nothing decodes at full resolution.** Artwork loads through
   `CGImageSourceCreateThumbnailAtIndex` with the maximum pixel size set to the on-screen
   size × scale. A 2000×3000 poster shown at 160×240 decodes to 320×480 — about 19× less
   memory than decoding it whole.
2. **Both caches are bounded by cost, not count.** An `NSCache<NSString, CGImage>` with a
   `totalCostLimit` in bytes for decoded thumbnails, and an LRU disk cache for the
   original JPEG bytes.
3. **Loads cancel on scroll-off.** Every cell owns its `Task` and cancels it in
   `onDisappear`.
4. **The library is never fully materialized.** `LibraryRepository.entries` takes a
   mandatory `limit`; there is deliberately no "fetch everything" call, because that is
   the call that would blow the budget.
5. **Memory pressure is handled.** A `DispatchSource` pressure handler drops the thumbnail
   cache on `.warning`.

## Verification status

What has been proven on this machine, and what has not:

| Claim | Status |
|---|---|
| Memory budgets | Measured, numbers above |
| No unbounded growth in playback | Two `leaks` passes, thousands of frames apart |
| Footprint independent of library size | Measured at 180 and 1000 items |
| Decision engine correctness | Unit-tested against a source-shape table |
| mpv plays 4K HEVC HDR10 MKV | Verified against fixtures |
| AVPlayer path plays mp4/H.264 | Verified against fixtures |
| Bundle runs without Homebrew | Verified — no `/usr/local` references remain in any binary |
| Playback menus enable during playback | Verified — 25/17/3/1 items enable, 0 with nothing playing |
| Offline banner and empty states | Verified on screen, light and dark |
| **Direct Play against a real server** | **Verified** — SPY×FAMILY HEVC/AAC MKV direct-played from Jellyfin 10.11.11, no ffmpeg process on the server |
| Trickplay previews end to end | Not verified — needs a server with trickplay generated |
| Dolby Vision profile 5 tone-mapping | Not verified — no DV file available here |
| Playback menu items enabling | Known broken, see below |

## Known issues

None outstanding.

The Playback/Video/Audio/Subtitles menus were dead through three phases and are fixed.
The diagnosis was wrong for most of that time: the player's publish loop was blamed, and
it had been running correctly all along. The actual cause is that SwiftUI re-evaluates
`Commands` only when a *focused value* changes — state written into scene `@State`, no
matter how faithfully, is not a reason for it to rebuild a menu bar. They are AppKit
`NSMenu`s now, which inverts the flow: `validateMenuItem` and `menuNeedsUpdate` are asked
for enablement when a menu opens, so nothing needs publishing and there is no stale-state
failure mode. Checkmarks are real `NSMenuItem.state` marks rather than bullets in the
title, and bare-key shortcuts stay with the player rather than becoming menu key
equivalents, which would have fired app-wide and toggled playback while typing in search.

## Layout

```
Sources/
  LumiereKit/      no UI — Jellyfin client, GRDB cache, image pipeline, decision engine
  LumierePlayer/   AVPlayer and libmpv engines behind one PlayerEngine protocol
  Lumiere/         the SwiftUI app
  CMPV/            C shim exposing libmpv's client and render APIs to Swift
  TestKit/         a minimal test harness, because XCTest is unavailable without Xcode
```

## Launch hooks

Driving clicks needs Accessibility permission that a build shell does not have, so the app
takes environment overrides for verification and measurement:

| Variable | Effect |
|---|---|
| `LUMIERE_DEMO=1` | Seed a local demo library — real SQLite rows, real JPEGs, no server |
| `LUMIERE_DEMO_MOVIES=n` | Scale that library, for the memory audit |
| `LUMIERE_FIXTURES=path` | Where the demo library's media lives |
| `LUMIERE_OPEN=id` | Open straight to an item's detail page |
| `LUMIERE_PLAY=id` | Open straight into the player |
| `LUMIERE_ROUTE=settings\|search\|library:id` | Open straight to a section |
| `LUMIERE_MPV_TRACE=1` | Log mpv's diagnostics, including frames actually drawn |
| `LUMIERE_DUMP_MENUS=1` | Make the app validate its own menu bar and log enablement |
| `LUMIERE_FORCE_OFFLINE=1` | Pretend the server is unreachable, to see the offline states |
