# Lumiere API Spec — what a replacement server must implement

**Phase 0 handoff.** Produced 2026-09-06. No server code is written here; this
document plus `capture/` is the whole output.

---

## 0. How this was produced

**Both halves now exist: the client's source, and a capture of real traffic.**

The endpoint list and the request shapes come from reading Lumiere's own source,
which makes them exhaustive — all 38 endpoints it can call, not only the ones a
session happened to exercise. The response shapes and everything about the
streaming paths come from a capture of 960 requests against Jellyfin 10.11.11,
taken 2026-09-06 through a logging reverse proxy (`capture/proxy.mjs`,
`capture/capture.jsonl`).

Where they disagreed, the capture won. §12 holds the measured results in full;
the corrections worth knowing before you read anything else are these, because
each is something reading the client could not have told you:

1. **`/Videos/{id}/hls1/main/{n}.ts` exists and is load-bearing** (§12.9.2). The
   client never builds those URLs — the HLS player follows them out of the
   playlist — so no amount of reading the client reveals them.
2. **`/UserItems/Resume` and `/Items/Latest` are never called** (§12.1). Both were
   listed as load-bearing from the source. Across every run neither appears once:
   those shelves are served from the client's own cache.
3. **An episode's `ParentId` is its `SeasonId`, always** (§5.2, §12.10) — 67,946
   objects, no exceptions. Getting this wrong empties a season page while every
   count matches.
4. **Artwork is not all JPEG** (§7.1, §12.11). Re-encoding everything to one
   format destroys a logo's transparency.
5. **Jellyfin gzips its JSON** (§10.3), which the first capture attempt stored as
   mojibake and had to be re-taken to fix.

Ground-truth precedence for anything still unresolved: the capture > this
document > Jellyfin's published API docs.

---

## 1. Version pins

| | |
|---|---|
| Lumiere | `0.1.0` (CFBundleVersion `1`), commit `b391448`, 2026-09-05 |
| Client identity sent | `Client="Lumiere"`, `Version="0.1.0"` |
| Jellyfin captured against | **10.11.11** (`/System/Info/Public`, live, 2026-09-06) |
| Host | macOS 15.8, Intel i7-8750H, 32 GB RAM |
| Jellyfin reachable at | `http://127.0.0.1:8096` (plain HTTP, same machine) |
| Toolchain present | Go 1.27.1, Node 24.16.0 |

Lumiere's version string is *only* sent in the auth header; nothing branches on
it. The server may ignore it. Jellyfin's version, by contrast, is load-bearing in
one place: `/System/Info/Public` must return a non-null `Id`, or sign-in refuses
the address as "not a Jellyfin server" (§3.1).

### 1.1 Resource baseline (measured, same machine)

| process | RSS | note |
|---|---|---|
| `jellyfin` | **1,955 MB** | the thing being replaced |
| Transmission | 227 MB | |
| YACReaderLibrary | 477 MB | also serving on :8080 |
| load average | 2.03 | 3-day uptime |

The brief names a Sonarr/Prowlarr/qBittorrent stack; **none of those were
running** at measurement time — Transmission is the torrent client present.
Worth confirming before sizing anything around them.

The number that matters: Jellyfin holds ~1.9 GB resident to serve one client. A
replacement that stays under ~150 MB idle is not an optimisation target, it is
most of the point of the project.

---

## 2. The shape of the problem

Lumiere is **not** a thin Jellyfin UI. Three facts change what the server has to
do, and all three reduce its work:

1. **The client decides how to play, not the server.** Lumiere sends a device
   profile that claims direct play for essentially every container and codec
   (§6.2), then ignores what the server says it supports and runs its own
   decision function (`PlaybackPlanner`, §6.4). The server's job is to report
   accurate stream metadata and then serve whatever URL it is asked for.

2. **Lumiere holds its own SQLite cache of the whole library.** It syncs pages of
   `/Items` and reads from the cache thereafter. Nearly every read endpoint is
   therefore *sync-shaped* — big, paged, sorted, `Fields`-controlled — rather
   than per-screen.

3. **mpv is the primary engine.** It plays what AVFoundation cannot, which is why
   the transcode path should almost never be taken. The realistic v1 target is a
   server that never transcodes at all (§6.7).

---

## 3. Auth handshake

### 3.1 Reaching a server

```
GET /System/Info/Public
Accept: application/json
```
No auth. Response fields Lumiere reads:

| field | required | used for |
|---|---|---|
| `Id` | **yes** | non-null is the test for "this is a Jellyfin server". Null ⇒ address rejected |
| `ServerName` | no | display; falls back to the host name |
| `Version` | no | display only |
| `LocalAddress` | no | ignored |
| `StartupWizardCompleted` | no | ignored |

Lumiere probes several candidate URLs derived from what the user typed
(`ServerURLNormalizer`) and takes the first that answers this shape, with a
6-second timeout per candidate.

### 3.2 Password sign-in — the only path that must work

```
POST /Users/AuthenticateByName
Content-Type: application/json
Accept: application/json
Authorization:        MediaBrowser Client="Lumiere", Device="<mac name>", DeviceId="<uuid>", Version="0.1.0"
X-Emby-Authorization: <identical value>

{"Username": "...", "Pw": "..."}
```

Response — **all three fields are load-bearing**:

```json
{ "User": { "Id": "...", "Name": "..." }, "AccessToken": "...", "ServerId": "..." }
```

`User.Id` becomes `userId` in every later request; `AccessToken` becomes the
token; `ServerId` is stored. `User.PrimaryImageTag` and `HasPassword` are decoded
but unused.

**Header details that have already broken sign-in once and will again:**

- Both `Authorization` **and** `X-Emby-Authorization` are sent, always, with the
  same value. Accept either.
- The value is `MediaBrowser ` + comma-separated `Key="Value"` pairs, in the
  order `Client, Device, DeviceId, Version[, Token]`.
- Before sign-in the `Token` pair is **absent entirely** (not empty).
- Lumiere sanitises its own values to printable ASCII minus `"`, `,` and `\`
  before sending. A server parsing this must not assume the values are otherwise
  constrained.
- `DeviceId` is a UUID generated once and kept in `UserDefaults`. It is stable
  across launches and is what a server would key a device/session record on.

### 3.3 Authenticated requests

Every subsequent request carries the same header with `Token="<AccessToken>"`
appended, in **both** header names, plus `Accept: application/json`. There is no
cookie, no refresh, no expiry handling anywhere in the client: **a token is valid
until the server rejects it.** A 401 or 403 on any request throws
`unauthorized`, which the app surfaces as signed-out.

**The media engines are the exception.** AVPlayer and mpv fetch outside the
client's URLSession and send only:

```
X-Emby-Token: <AccessToken>
```

The `MediaBrowser` scheme cannot be used there — mpv's `--http-header-fields` is
itself comma-separated, so the header arrives split into four and the server 400s.
**A replacement server must accept `X-Emby-Token` as an equivalent credential on
every streaming, subtitle and trickplay URL**, or nothing plays. Note that
Lumiere never puts the token in a query string, by design.

### 3.4 Quick Connect (optional)

`GET /QuickConnect/Enabled` → the literal `true`/`false`. Returning `false` (or
404, which Lumiere treats as false) disables the whole flow and the app falls
back to password sign-in with no visible loss. **Stub it as `false` in v1.**
If ever implemented: `POST|GET /QuickConnect/Initiate` → `{Secret, Code}`,
`GET /QuickConnect/Connect?secret=` → `{Secret, Code, Authenticated}` polled
every 3s for up to 5 minutes, then `POST /Users/AuthenticateWithQuickConnect`
with `{"Secret": …}` returning the same `AuthenticationResult` as §3.2.

`GET /Users/Public` → array of `{Id, Name, PrimaryImageTag, HasPassword}`, used
only to show avatars on the sign-in screen. Returning `[]` is fine — the live
server already does.

### 3.5 Discovery (optional)

Lumiere broadcasts a UDP datagram on **port 7359** to every interface broadcast
address and expects a JSON reply with `Id`, `Name`, `Address`. Purely a
convenience on the sign-in screen; typing the address works without it.
**Out of scope for v1.**

---

## 4. Endpoint contract

38 distinct endpoints. "Load-bearing" means Lumiere is broken or badly degraded
without it; "cosmetic" means a 404 degrades gracefully by design.

### 4.1 Auth & system

| Method | Path | Load-bearing | Notes |
|---|---|---|---|
| GET | `/System/Info/Public` | **yes** | `Id` must be non-null (§3.1) |
| POST | `/Users/AuthenticateByName` | **yes** | §3.2 |
| GET | `/Users/Public` | cosmetic | `[]` is fine |
| GET | `/QuickConnect/Enabled` | cosmetic | return `false` |
| POST/GET | `/QuickConnect/Initiate` | cosmetic | omit if Enabled is false |
| GET | `/QuickConnect/Connect?secret=` | cosmetic | " |
| POST | `/Users/AuthenticateWithQuickConnect` | cosmetic | " |

### 4.2 Library reads — the sync path

| Method | Path | Load-bearing | Notes |
|---|---|---|---|
| GET | `/UserViews?userId=` | **yes** | the library list. Returns `ItemsResponse` of `CollectionFolder`/`UserView` items; `CollectionType` drives folder-vs-scraped behaviour app-wide (see §5.4) |
| GET | `/Items` | **yes** | the workhorse — full param list below |
| GET | `/Users/{userId}/Items/{id}` | **yes** | single item, `Fields=<detail>`. Legacy path; Lumiere uses it, not `/Items/{id}` |
| GET | `/Items/Latest?userId=&ParentId=&Limit=&Fields=` | **yes** | **returns a bare JSON array, not an `ItemsResponse`** |
| GET | `/UserItems/Resume?userId=&Limit=&Recursive=true&MediaTypes=Video&Fields=` | **yes** | Continue Watching |
| GET | `/Shows/NextUp?userId=&Limit=&Fields=[&SeriesId=]` | **yes** | Next Up |
| GET | `/Shows/{seriesId}/Seasons?userId=&Fields=` | **yes** | |
| GET | `/Shows/{seriesId}/Episodes?userId=&Fields=[&seasonId=]` | **yes** | |
| GET | `/Items/{id}/Similar?userId=&Limit=&Fields=` | cosmetic | empty array is fine |
| GET | `/Users/{userId}/Items/{id}/SpecialFeatures` | cosmetic | bare array; extras |
| GET | `/Artists?…` | cosmetic | music only |

`/Items` parameters Lumiere sends, all as query string:

```
userId, Recursive=true|false, SortBy=<comma list>, SortOrder=Ascending|Descending,
StartIndex, Limit, Fields=<comma list>, EnableTotalRecordCount=true,
EnableImageTypes=Primary,Backdrop,Thumb,Logo,
ParentId, IncludeItemTypes=<comma list>, SearchTerm,
Filters=<comma list>, Genres=<PIPE-separated>, Years=<comma list>,
PersonIds=<comma list>, ArtistIds
```

Note the separator inconsistency, which is Jellyfin's and must be matched:
**`Genres` is pipe-separated** (names contain commas), everything else is
comma-separated. `SortBy` values seen: `SortName`, `DateCreated`,
`PremiereDate,SortName`. Sync pages at `Limit=200` and halves on retry
(200→100→50→25) when a page times out, so the server must tolerate large pages
and be honest about `TotalRecordCount` — paging is driven by it.

### 4.3 Watch state & user data

| Method | Path | Load-bearing | Notes |
|---|---|---|---|
| POST | `/UserPlayedItems/{itemId}?userId=` | **yes** | mark watched |
| DELETE | `/UserPlayedItems/{itemId}?userId=` | **yes** | mark unwatched. **Must also zero `PlaybackPositionTicks`** — this is how Lumiere resets a resume position |
| POST | `/UserFavoriteItems/{itemId}?userId=` | **yes** | |
| DELETE | `/UserFavoriteItems/{itemId}?userId=` | **yes** | |

All four return 204 or a `UserItemData`; Lumiere ignores the body.

### 4.4 Playback

| Method | Path | Load-bearing | Notes |
|---|---|---|---|
| POST | `/Items/{id}/PlaybackInfo?userId=` | **yes** | §6.1 |
| GET | `/Videos/{id}/stream?static=true&mediaSourceId=&playSessionId=` | **yes** | direct play; **must honour HTTP Range** |
| GET | `/Videos/{id}/stream.mp4?static=false&videoCodec=copy&audioCodec=copy&…` | **yes** | remux |
| GET | `/Videos/{id}/main.m3u8?videoCodec=h264&audioCodec=aac&transcodingContainer=ts&transcodingProtocol=hls&…` | see §6.7 | transcode |
| GET | `/Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.srt` | **yes** for external subs | format from the URL extension |
| POST | `/Sessions/Playing` | **yes** | start |
| POST | `/Sessions/Playing/Progress` | **yes** | every tick |
| POST | `/Sessions/Playing/Stopped` | **yes** | **this is what writes the resume position** |
| GET | `/Audio/{id}/universal?container=…&audioCodec=aac&deviceId=` | music only | |

### 4.5 Images

| Method | Path | Load-bearing | Notes |
|---|---|---|---|
| GET | `/Items/{id}/Images/{Primary\|Backdrop\|Thumb\|Logo\|Banner}[/{index}]?tag=&maxWidth=&quality=90` | **yes** | see §7.1 |
| GET | `/Videos/{id}/Trickplay/{width}/{index}.jpg[?mediaSourceId=]` | cosmetic | scrub preview |
| GET | `/MediaSegments/{id}?includeSegmentTypes=Intro&includeSegmentTypes=Outro…` | cosmetic | skip buttons; 404 ⇒ no buttons |

### 4.6 Writes and management — all cosmetic for v1

| Method | Path | Notes |
|---|---|---|
| POST | `/Items/{id}` | full-DTO replace; see §5.5 — the dangerous one |
| POST | `/Items/{id}/Refresh?metadataRefreshMode=FullRefresh&…` | re-scrape |
| GET | `/Items/{id}/RemoteImages?type=&includeAllLanguages=true` | artwork picker |
| POST | `/Items/{id}/RemoteImages/Download?type=&imageUrl=` | |
| POST | `/Items/{id}/Images/{type}` (raw body) | upload artwork |
| DELETE | `/Items/{id}/Images/{type}` | |
| POST | `/Items/RemoteSearch/{Movie\|Series}` | identify |
| POST | `/Items/RemoteSearch/Apply/{id}?replaceAllImages=true` | |
| DELETE | `/Items?ids=` | delete item |
| POST/DELETE | `/Collections`, `/Collections/{id}/Items?Ids=` | |
| POST/DELETE | `/Playlists`, `/Playlists/{id}/Items?Ids=\|EntryIds=` | |
| GET | `/Playlists/{id}/Items?userId=&StartIndex=&Limit=&…` | |
| GET/POST | `/ScheduledTasks`, `/ScheduledTasks/Running/{id}` | `{Id,Name,Key,State,CurrentProgressPercentage}` |
| POST | `/Library/Refresh` | |
| GET/POST | `/Audio/{id}/Lyrics` | |

These back the metadata editor, artwork picker, collection/playlist authoring and
the server-maintenance panel. Every one of them fails soft in the UI. **Stub them
as 404 in v1 and the app remains fully usable for browsing and playback** — but
see §9 for which ones will be missed first.

---

## 5. Response shapes — exactly what Lumiere decodes

Lumiere decodes ~45 of `BaseItemDto`'s hundred-plus fields and **ignores the
rest**. Anything not listed here can be omitted from the server's responses
entirely. Field names are Jellyfin's PascalCase JSON keys.

### 5.1 `ItemsResponse` — the envelope

```json
{ "Items": [ … ], "TotalRecordCount": 1234, "StartIndex": 0 }
```
`TotalRecordCount` drives paging and is **required**. `StartIndex` is optional.
`/Items/Latest` and `/SpecialFeatures` return a bare array instead — a difference
the server must reproduce.

### 5.2 `JellyfinItem`

| Field | Type | Required | What it drives |
|---|---|---|---|
| `Id` | string | **yes** | primary key everywhere |
| `Name` | string | **yes** | every label |
| `Type` | string | **yes** | `Movie`, `Series`, `Season`, `Episode`, `BoxSet`, `CollectionFolder`, `Folder`, `UserView`, `Video`, `Audio`, `MusicAlbum`, `MusicArtist`, `Person`, `Trailer`. Unknown values decode as `.unknown` and are dropped from grids — they do not fail a page |
| `ServerId` | string? | no | stored, unused |
| `ParentId` | string? | **yes** for folder libraries | see §5.4 |
| `SeriesId`, `SeriesName`, `SeasonId`, `SeasonName` | string? | **yes** for episodes | episode cards lead with the series name |
| `IndexNumber`, `ParentIndexNumber` | int? | **yes** for episodes | "S1 E4", and episode ordering |
| `ExtraType` | string? | no | non-null marks an extra and hides it from shelves |
| `OriginalTitle` | string? | no | search matching (romaji titles) + metadata editor |
| `SortName` | string? | no | requested only on detail; editor shows it |
| `Overview` | string? | no | synopsis. Requested in the **list** field set on purpose |
| `ProductionYear` | int? | no | subtitle line |
| `PremiereDate`, `DateCreated` | ISO-8601? | **yes** (`DateCreated`) | every "Latest" shelf sorts on `DateCreated`; null makes those shelves alphabetical |
| `OfficialRating` | string? | no | badge |
| `CommunityRating`, `CriticRating` | double? | no | Top 10 ranking uses `CommunityRating` |
| `Genres` | [string]? | no | genre browsing is empty without it |
| `Tags`, `Taglines` | [string]? | no | franchise grouping, hero tagline |
| `Studios`, `People` | `[{Id,Name}]`, `[{Id,Name,Role,Type,PrimaryImageTag}]` | no | detail page credits |
| `RunTimeTicks` | int64? | **yes** | 100-ns ticks. Duration, progress %, "30m left", and the end-of-file resume rule |
| `ImageTags` | `{String: String}` | **yes** | keys read: `Primary`, `Thumb`, `Logo`. The *value* is the cache-busting tag |
| `BackdropImageTags` | [string]? | **yes** | first element only |
| `ParentBackdropItemId`, `ParentBackdropImageTags` | | no | episode falls back to series art |
| `SeriesPrimaryImageTag` | string? | no | episode poster fallback |
| `Album`, `AlbumArtist`, `Artists`, `AlbumId` | | music only | returned by default, no `Fields` gate |
| `MediaSources` | [MediaSource]? | **yes** on detail & PlaybackInfo | §5.3 |
| `MediaStreams` | [MediaStream]? | no | decoded but the source's copy is used |
| `Container`, `Path` | string? | **yes** | `Path` drives the "original filename" title style and the whole folder-browser tree (§5.4) |
| `Chapters` | `[{StartPositionTicks,Name,ImageTag}]` | no | chapter skip |
| `UserData` | UserItemData | **yes** | §5.3 |
| `ChildCount`, `RecursiveItemCount` | int? | no | counts on cards |
| `IsFolder` | bool? | **yes** | folder-vs-file in the browser |
| `CollectionType` | string? | **yes** on `/UserViews` | §5.4 |
| `PlaylistItemId` | string? | playlists only | identity of a *row*, not the track |

Dates: Jellyfin emits three shapes and Lumiere parses all three — fractional
seconds, whole seconds, and no timezone designator (assumed UTC). **Emit RFC-3339
with `Z`** and none of that matters.

### 5.3 `MediaSource`, `MediaStream`, `UserItemData`

`MediaSource` — the object the playback decision is made from:

| Field | Required | Notes |
|---|---|---|
| `Id` | **yes** | passed back as `mediaSourceId` on every stream URL and progress report |
| `Name` | no | version picker label |
| `Path` | no | shown in the About panel |
| `Container` | **yes** | **decisive**: lowercased and matched against `mp4, m4v, mov, qt` |
| `Size` | no | About panel |
| `Bitrate` | **yes if a bitrate cap is set** | bits/sec; the only trigger for a server transcode in practice (§6.5) |
| `RunTimeTicks` | no | |
| `MediaStreams` | **yes** | below |
| `SupportsDirectPlay`, `SupportsDirectStream`, `SupportsTranscoding`, `TranscodingUrl`, `TranscodingSubProtocol` | **no — decoded and ignored** | Lumiere builds its own URLs and makes its own decision. **A replacement server need not compute any of these.** |

`MediaStream` — `Index` and `Type` are required; `Type` ∈ `Video, Audio,
Subtitle, EmbeddedImage` (unknown → `.unknown`, harmless).

| Field | Decisive for | Notes |
|---|---|---|
| `Codec` | **the entire routing decision** | lowercased. Video: `h264/avc` → AVPlayer; `hevc/h265`, `vp9` → always mpv; `av1` → mpv unless hardware AV1. Audio: `aac, ac3, eac3, alac, mp3, pcm, pcm_s16le, pcm_s24le, lpcm` → AVPlayer, anything else → mpv. Subtitle: `pgssub, pgs, dvdsub, vobsub, dvbsub, ass, ssa` → mpv |
| `Width` | **yes** | over the machine's max decode width ⇒ **server transcode** |
| `Height`, `BitDepth`, `Profile` | display | `Profile` decodes as int *or* string |
| `VideoRange`, `VideoRangeType`, `VideoDoViTitle`, `DvProfile`, `DvLevel` | **yes** | Dolby Vision detection: `DvProfile` non-null, or the range string containing `DOVI`/`DOLBY` |
| `Language`, `Title`, `DisplayTitle` | yes | track picker labels; `DisplayTitle` is what the menu shows |
| `IsDefault` | **yes** | picks the default audio stream, which is what the decision reasons over |
| `IsForced`, `IsExternal` | yes | external subtitles are fetched over HTTP instead of being in-band |
| `AverageFrameRate`, `RealFrameRate`, `Channels`, `SampleRate`, `ChannelLayout`, `BitRate` | display | statistics HUD |

`UserItemData`:

| Field | Required | Notes |
|---|---|---|
| `PlaybackPositionTicks` | **yes** | resume position, 100-ns ticks |
| `Played` | **yes** | |
| `IsFavorite` | **yes** | |
| `PlayCount` | no | |
| `UnplayedItemCount` | **yes** for series/season | drives the unwatched badge and "is this show watched" |
| `PlayedPercentage` | no | Lumiere computes its own from ticks ÷ runtime |
| `LastPlayedDate` | **yes** | Continue Watching is ordered by it |

### 5.4 The folder-library contract — read this one twice

Libraries with **`CollectionType == null`** on `/UserViews` are treated
completely differently: no scraped posters, filenames as labels, a folder browser
instead of a poster wall, and `MediaSources` requested during sync. Two Jellyfin
behaviours have already cost days here and a replacement server should decide
deliberately whether to reproduce them:

1. **`ParentId` is not the containing folder.** On the live library, fifteen rows
   had a parent whose path was not their directory — Jellyfin collapses a folder
   holding a single video into a Movie item, and the video's parent becomes that
   item. Lumiere therefore builds the folder tree **from `Path` string prefixes**,
   not from `ParentId`. A server that reports honest parentage would let Lumiere
   keep working (it prefers `Path` and would simply agree), and would make the
   whole `FolderTree` synthesis redundant.

2. **Several files in one folder merge into one item.** `Clips/Compilations/…`
   returned one item for nine files; only their alternate `MediaSources` revealed
   the rest. Lumiere works around this by requesting `Fields=…,MediaSources` for
   folder libraries and reconstructing the missing files. **A replacement server
   that simply returns one item per file makes an entire subsystem unnecessary.**

`Path` must therefore be an absolute filesystem path, present on every item in a
folder library, and stable — it is a key, not decoration.

### 5.5 `POST /Items/{id}` is destructive by design

The metadata editor does: `GET /Users/{userId}/Items/{id}?Fields=<detail>` →
mutate a few keys in the **raw JSON** → `POST /Items/{id}` with the whole object.
Jellyfin replaces the DTO rather than patching it, so any field absent from the
GET is cleared by the POST. Lumiere's `detail` field set exists partly to prevent
that (it asks for `ProviderIds`, `Tags`, `Settings`, `CustomRating`… purely so
they survive a save).

**A replacement server should implement this as a merge-patch instead** — same
URL, same body, but only the keys present are written. That is strictly safer and
Lumiere cannot tell the difference. Keys it may send: `Name`, `OriginalTitle`,
`SortName`, `ForcedSortName`, `Overview`, `ProductionYear`, `Album`,
`AlbumArtist`, `AlbumArtists`, `Artists`, `IndexNumber`, `ParentIndexNumber`,
`Genres`, `LockedFields`, `LockData`.

---

## 6. Playback negotiation — the whole contract

### 6.1 `POST /Items/{itemId}/PlaybackInfo?userId={userId}`

Body (verbatim, every call):

```json
{
  "UserId": "<userId>",
  "DeviceProfile": { … §6.2 … },
  "EnableDirectPlay": true,
  "EnableDirectStream": true,
  "EnableTranscoding": true,
  "AllowVideoStreamCopy": true,
  "AllowAudioStreamCopy": true,
  "AutoOpenLiveStream": true,
  "MediaSourceId": "<optional — set when a version was picked>",
  "MaxStreamingBitrate": 0
}
```

Response, and this is the entire contract:

```json
{ "MediaSources": [ … ], "PlaySessionId": "…", "ErrorCode": null }
```

- `MediaSources` — **load-bearing.** Must carry `Id`, `Container`, `Bitrate`,
  and complete `MediaStreams`. Everything downstream is decided from these.
- `PlaySessionId` — optional in the type but **send one**: it is echoed on every
  stream URL and every progress report, and it is how a server correlates them.
- `ErrorCode` — decoded, never inspected. Report failures as HTTP status.

Lumiere calls this **once per playback session**, at start. It has a 4-second
timeout, and on timeout falls back to the cached `MediaSources` from the item's
detail record — so a slow `PlaybackInfo` degrades to playing from stale metadata
rather than failing.

### 6.2 The device profile, and why you can ignore it

Lumiere sends a profile claiming direct play for
`mp4,m4v,mkv,mov,avi,ts,m2ts,webm,flv,wmv,ogv,3gp` ×
`h264,hevc,av1,vp8,vp9,mpeg2video,vc1,mpeg4,theora` ×
`aac,ac3,eac3,dts,dtshd,truehd,flac,alac,mp3,opus,vorbis,pcm`, with a single
transcoding profile (`ts`/`h264`/`aac`/`hls`) and `MaxStreamingBitrate`
400 Mbit/s. This is honest — mpv really can play all of it.

**A replacement server may ignore `DeviceProfile` entirely.** It exists so
Jellyfin does not volunteer a transcode; a server that never volunteers one has
no use for it. It should still be *accepted* without erroring.

### 6.3 The three stream URLs

Built by the client, never taken from `TranscodingUrl`:

| Route | URL | Server must |
|---|---|---|
| **Direct play** | `GET /Videos/{id}/stream?static=true&mediaSourceId={sourceId}[&playSessionId=]` | serve the original file bytes with **full HTTP Range support** — this is ~100% of real traffic |
| **Remux** | `GET /Videos/{id}/stream.mp4?static=false&mediaSourceId=&videoCodec=copy&audioCodec=copy[&audioStreamIndex=][&playSessionId=]` | repackage into MP4 copying both streams; no re-encode |
| **Transcode** | `GET /Videos/{id}/main.m3u8?mediaSourceId=&videoCodec=h264&audioCodec=aac&transcodingContainer=ts&transcodingProtocol=hls[&maxStreamingBitrate=&videoBitRate=][&audioStreamIndex=][&subtitleStreamIndex=&subtitleMethod=Encode][&playSessionId=]` | HLS, H.264/AAC in MPEG-TS segments; burn in subtitles when asked |

Auth on all three is the `X-Emby-Token` header (§3.3). No credential in the URL.

External subtitles: `GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/Stream.srt`
— extension names the format; `srt` is the default and the only one requested by
default.

### 6.4 Which route Lumiere picks — the real decision table

Evaluated in order; the first match wins. `capabilities` is the local Mac's.

| # | Condition | Route | Engine |
|---|---|---|---|
| 1 | user forced a transcode | **transcode** | AVPlayer |
| 2 | `MediaSource.Bitrate` > user's bitrate cap | **transcode** | AVPlayer |
| 3 | video `Width` > machine's max decode width | **transcode** | AVPlayer |
| 4 | Dolby Vision the display can't present | direct play | mpv (tone-maps) |
| 5 | selected subtitle is `pgssub/pgs/dvdsub/vobsub/dvbsub/ass/ssa` | direct play | mpv |
| 6 | container not in `mp4, m4v, mov, qt` | direct play | mpv |
| 7 | video codec not `h264/avc` (HEVC, VP9 always; AV1 unless hardware) | direct play | mpv |
| 8 | audio codec outside `aac, ac3, eac3, alac, mp3, pcm*, lpcm` | direct play | mpv |
| 9 | otherwise | direct play | AVPlayer |

Rows 4–8 are the mpv escape hatch: **they are still direct play** — the server is
asked for the original bytes and does no work. Only rows 1–3 ever reach the
server as a transcode, and only if libmpv failed to load do rows 4–8 fall back to
one.

**The remux route is never selected by this function.** `StreamBuilder` can build
the URL and `PlaybackDecision.Route.remux` exists, but no branch returns it.
Treat `/Videos/{id}/stream.mp4` as dead in v1 unless the capture proves otherwise.

### 6.5 How to force a transcode when capturing

There is **no force-transcode toggle in the shipping UI** (`forceTranscode`
exists in the planner but nothing in the app sets it). The only reachable trigger
is row 2:

> **Settings → Playback → Maximum bitrate**, set below the file's own bitrate.

Row 3 needs a file wider than the Mac's decode limit; row 1 is unreachable
without a code change. Use the bitrate cap.

### 6.6 Progress reporting

Three POSTs, all `application/json`, all expecting 204:

```
POST /Sessions/Playing            {ItemId, MediaSourceId, PositionTicks, IsPaused:false, IsMuted:false, CanSeek:true, PlayMethod:"DirectPlay", RepeatMode:"RepeatNone", PlaySessionId?}
POST /Sessions/Playing/Progress   { …same…, IsPaused: <bool>, EventName: "timeupdate" | "pause" | "unpause" }
POST /Sessions/Playing/Stopped    {ItemId, MediaSourceId, PositionTicks, PlaySessionId?}
```

- `PositionTicks` is seconds × 10,000,000.
- **`PlayMethod` is hardcoded to `"DirectPlay"`** whatever route was chosen. A
  server must not infer the route from it.
- `/Stopped` is what persists the resume position; it fires on stop, window close
  and app quit. **If only one of the three is implemented, implement this one.**
- Lumiere queues these locally when the server is unreachable and replays them on
  reconnect, so out-of-order and late arrivals must be tolerated — last write
  wins by position, not by arrival.

### 6.7 What this means for the server build

The realistic v1: **serve files with Range support, report accurate ffprobe
metadata, record watch state.** No encoder at all.

- Rows 4–8 — the hard formats — never touch the server's CPU.
- Row 2 only fires if the Director sets a bitrate cap, which on a LAN they have
  no reason to.
- Row 3 only fires above the machine's decode ceiling.

Ship v1 with `/Videos/{id}/main.m3u8` returning **503 with a clear body**, and
watch whether it is ever hit. That is a smaller, more honest promise than a
half-working VideoToolbox pipeline, and the capture will confirm the shape before
you build it. VideoToolbox HLS output remains the design for v2 — Marquee's
presets are the starting point.

---

## 7. Images, trickplay, segments

### 7.1 Images — load-bearing, and the one place performance is visible

```
GET /Items/{id}/Images/{kind}[/{index}]?tag={tag}&maxWidth={px}&quality=90
```

`kind` ∈ `Primary, Backdrop, Thumb, Logo, Banner`. `index` is sent only for
indexed backdrops.

- **`maxWidth` must resize server-side.** It is most of the app's memory story: a
  300 px poster is ~30 KB against ~800 KB unresized, and a home screen realises
  hundreds of tiles.
- **`tag` is a content address, not a cache key you may ignore.** Lumiere caches
  on `itemId|kind|tag|maxWidth` forever. Changed artwork must mean a changed tag,
  or clients keep the old picture indefinitely.
- Widths requested are a small ladder (rounded up), not arbitrary — precompute or
  cache aggressively.
- `quality=90` is always sent.
- **[capture] The response is not always JPEG.** Jellyfin serves `image/jpeg`
  *and* `image/png` from this one endpoint, and the difference is load-bearing:
  a logo is a wordmark on transparency, and JPEG has no alpha channel. Re-encoding
  every variant to JPEG does not drop the transparency, it fills it — with black,
  in Go's encoder — so the logo arrives in a black box. Keep the source's format
  whenever it can carry alpha. See §12.11.

### 7.2 Trickplay — cosmetic

`GET /Users/{userId}/Items/{id}?Fields=Trickplay` returns
`{"Trickplay": {"<mediaSourceId>": {"<width>": {…}}}}`; sheets come from
`GET /Videos/{id}/Trickplay/{width}/{index}.jpg`. Absent ⇒ plain scrub bar.

### 7.3 Media segments — cosmetic

`GET /MediaSegments/{id}?includeSegmentTypes=Intro&includeSegmentTypes=Outro&…`
(**repeated parameters, not a comma-joined list** — joining them 400s, which
silently killed Skip Intro across the whole library once). Returns
`{"Items":[{Id,Type,StartTicks,EndTicks}]}`. `Type` ∈ `Intro, Outro, Recap,
Preview, Commercial`; anything else is ignored. 404 ⇒ no skip buttons, no error.

---

## 8. Explicitly out of scope for v1

Nothing here is called by Lumiere at all, or is called and fails soft:

**Never called — do not implement:** Live TV, SyncPlay, DLNA, plugins and the
plugin catalogue, the Jellyfin web dashboard, user management, WebSocket
`/socket` (Lumiere polls; it never opens one), `/Sessions` beyond the three
`Playing` posts, DisplayPreferences, Branding, subtitle *search*/download,
`/Items/{id}/Download`, transcode-throttling endpoints, `/Users/{id}/Views`
(Lumiere uses `/UserViews`).

**Called, degrades gracefully — stub as 404:** Quick Connect (§3.4), UDP
discovery (§3.5), `/Users/Public`, `/Items/{id}/Similar`, `/SpecialFeatures`,
trickplay, media segments, all of §4.6 (metadata editing, artwork picker,
identify, collections, playlists, scheduled tasks, lyrics).

**Called and load-bearing — the actual v1 surface, 21 endpoints:**

```
GET  /System/Info/Public
POST /Users/AuthenticateByName
GET  /UserViews
GET  /Items
GET  /Users/{userId}/Items/{id}
GET  /Items/Latest
GET  /UserItems/Resume
GET  /Shows/NextUp
GET  /Shows/{seriesId}/Seasons
GET  /Shows/{seriesId}/Episodes
POST|DELETE /UserPlayedItems/{id}
POST|DELETE /UserFavoriteItems/{id}
POST /Items/{id}/PlaybackInfo
GET  /Videos/{id}/stream                     (Range)
GET  /Videos/{id}/{sourceId}/Subtitles/{i}/Stream.srt
POST /Sessions/Playing
POST /Sessions/Playing/Progress
POST /Sessions/Playing/Stopped
GET  /Items/{id}/Images/{kind}
```

That is the whole server. Everything else is optional.

---

## 9. Open questions for the build session

1. **Response bodies are unverified.** Field *names* and *types* here come from
   Lumiere's decoders and are exact; what Jellyfin actually emits — null-vs-absent,
   `Profile` as int or string, tick precision, the `Trickplay` nesting — is not.
   Run §10 before implementing `PlaybackInfo` or `/Items`.
2. **Which `SortBy` values must really work?** The capture shows **only
   `SortBy=SortName&SortOrder=Ascending`, `Limit=200`** across 123 sync pages —
   the full-sync path. The incremental path (`DateCreated` descending) never ran
   because the cache was warm, so it is still unverified. Implement both.
3. **`Filters` values are unenumerated.** The parameter is plumbed through; the
   set Lumiere actually sends is not visible from the call sites. Capture it.
4. **`/Items/Latest` semantics.** Jellyfin's "latest" collapses a season of
   episodes into one row; Lumiere re-implements that collapse locally as well.
   Decide which side owns it — doing it in both is how a shelf ends up short.
5. **Does anything depend on Jellyfin's id format?** Lumiere treats ids as opaque
   strings (a synthetic folder's id is its *path*, and starts with `/`, which is
   how it is told apart from a server id). A new server may use any format that
   never begins with `/`.
6. **`UnplayedItemCount`** is emitted on `Series`, `Season` and `Folder` (100% of
   each) and **absent on `Episode` and `Movie`** — §12.5. It must be maintained
   server-side or every show carries an unwatched badge forever.
7. ~~Does deleting `/UserPlayedItems/{id}` zero the position?~~ **Answered: yes**
   — it zeroes `PlaybackPositionTicks` *and* `PlayCount`, and drops
   `LastPlayedDate` entirely. See §12.5.
8. **Multi-user.** Everything is `userId`-scoped in the API. If the server is
   single-user, decide whether to accept and ignore `userId` or to honour it —
   ignoring it is fine for Lumiere and cheaper.
9. **The `Sonarr/Prowlarr/qBittorrent` baseline in the brief did not match what is
   running** (§1.1). Re-measure before sizing.

---

## 10. Capture harness — how to close the gap

`capture/proxy.mjs`, self-tested against the live server. Zero dependencies, no
certificate, no sudo: it is a plain-HTTP reverse proxy that logs both sides.

### 10.1 Run it

```bash
node "capture/proxy.mjs"
```

Listens on `127.0.0.1:8097`, forwards to `127.0.0.1:8096`, appends to
`capture/capture.jsonl`, and prints one line per request as it goes.

### 10.2 Drive Lumiere through it

1. In Lumiere: sign out, then sign in to **`http://127.0.0.1:8097`**. (Signing in
   again is unavoidable — a token is bound to the server URL it was issued for.)
2. Exercise, in this order, letting each settle:
   home screen → a scraped library (Movies) → a TV library → **a folder library
   (3D or My Videos)** → open a series → open an episode detail → search →
   **play an episode and let it run ~30s** → pause → seek → resume → stop →
   mark something watched → favourite something → sign out.
3. **The transcode case:** Settings → Playback → Maximum bitrate, set it *below*
   the bitrate of a file you then play (§6.5). This is the only reachable trigger.
   Capture the whole playback, then set the cap back to Unlimited.
4. Stop the proxy (Ctrl-C) and sign Lumiere back in to `http://127.0.0.1:8096`.

The folder library is not optional — §5.4 is the part of the contract most likely
to be got wrong, and it only shows up there.

### 10.3 What is in the log, and what is not

One JSON object per request/response pair: method, path, headers, request body,
response status, headers, content type, byte count, and the response body when it
is JSON/text under 4 MB. Video and image bodies are recorded by type and size
only — the point is the contract, not the bytes.

Credentials are removed on the way in, and this was verified against the live
server before shipping the harness:

- `Authorization` / `X-Emby-Authorization` keep `Client`, `Device`, `DeviceId`
  and `Version` — which *are* the contract — and the token becomes a stable
  8-hex fingerprint (`Token="tok:a3b9da08"`), so two requests can be shown to
  carry the same token without the token being written down.
- `X-Emby-Token` → the same fingerprint.
- `Pw`, `Password`, `Secret` in an auth body → `<redacted>`.
- `AccessToken` in an auth response → fingerprint.
- `api_key` / `ApiKey` in a query string → fingerprint.

Still: the log contains **titles, paths and watch history**, which are private.
Keep it local; hand it to the build session as a file, not as chat context.

### 10.4 Reading it back

```bash
# every distinct endpoint, by frequency
python3 -c "
import json,re,collections
c=collections.Counter()
for l in open('capture/capture.jsonl'):
    e=json.loads(l)
    p=re.sub(r'/[0-9a-f]{32}','/{id}',e['request']['path'].split('?')[0])
    c[(e['request']['method'],p)]+=1
for (m,p),n in c.most_common(): print(f'{n:5}  {m:6} {p}')
"
```

---

## 11. Handoff to the build session

Give the next session:

1. **This file.**
2. `capture/capture.jsonl` — after §10 has been run. **Do not start implementing
   `PlaybackInfo` or `/Items` without it**; §9.1 is the reason.
3. `capture/proxy.mjs` — so it can re-capture when something disagrees.
4. A pointer to Marquee's transcode presets (`MARQUEE_BUILD_PLAN.md` §8 and
   `server/` in that repo) — for v2 only, per §6.7.
5. Lumiere's source at commit `b391448`, which is the executable version of this
   document: `Sources/LumiereKit/Jellyfin/` for requests, `Sources/LumiereKit/Media/`
   for the playback decision.

### 11.1 Recommended stack — **Go**

On the criterion the brief set (library ecosystem for HTTP + media probing), not
preference:

- **`net/http`'s `ServeContent` implements Range, If-Range, 206 and multipart
  ranges correctly, from the standard library.** That is the single most
  load-bearing behaviour in the entire spec (§6.3) and the easiest to get subtly
  wrong by hand; Node has no equivalent and every popular wrapper reimplements it.
- ffprobe is a subprocess in both languages — no ecosystem advantage either way.
- SQLite: `modernc.org/sqlite` is pure Go (no cgo, no build friction).
- One static binary, no runtime to install, and an idle footprint measured in
  tens of MB against Node's baseline — which matters given §1.1's 1.9 GB
  incumbent on a shared machine.

Node's advantage — fluent JSON — is worth little here: the response shapes are
fixed and few, and Go's structs give compile-time checking against a spec that
Lumiere will reject at runtime if it drifts.

### 11.2 Build order that gets to "it works" soonest

1. `/System/Info/Public` + `/Users/AuthenticateByName` — nothing else runs until
   sign-in does (§3).
2. `/UserViews` + `/Items` with `Fields`, paging and `TotalRecordCount` — this is
   the whole library sync, and it is most of the app.
3. `/Items/{id}/Images/{kind}` with `maxWidth` — without it the app looks broken
   even though it works.
4. `PlaybackInfo` + `/Videos/{id}/stream` with Range — first playback.
5. The three `/Sessions/Playing` posts — resume positions stop being lost.
6. Watch state, then the shelf endpoints (`Resume`, `NextUp`, `Latest`, `Shows/*`).
7. Everything in §8's stub list, as 404s, from day one — not at the end.

**Do not begin implementation in the session that produced this document.**

---

## 12. Capture results — verified behaviour

Two runs, 2026-09-06, against Jellyfin 10.11.11 through `capture/proxy.mjs`.
Everything below is measured, not inferred.

### 12.1 Coverage

Observed across both runs (25 endpoints). Counts are run 2 unless noted.

| n | endpoint | status |
|---|---|---|
| 116 | `GET /Items` | 200 |
| 25 | `GET /Items/{id}/Images/Primary` | 200 |
| 18 | `GET /Users/{id}/Items/{id}` | 200 |
| 10 | `POST /Sessions/Playing/Progress` | 204 |
| 10 | `GET /Shows/NextUp` | 200 |
| 9 | `GET /Shows/{id}/Episodes` | 200 |
| 4 | `GET /Videos/{id}/stream` | **206** |
| 3 | `GET /Shows/{id}/Seasons` · `/SpecialFeatures` · `/Items/{id}/Similar` | 200 |
| 3+3 | `POST` / `DELETE /UserPlayedItems/{id}` | 200 |
| 2 | `POST /Sessions/Playing/Stopped` · `GET /ScheduledTasks` | 204 / 200 |
| 1 | `POST /Items/{id}/PlaybackInfo` · `GET /MediaSegments/{id}` · `POST /Sessions/Playing` | 200/200/204 |
| run 1 | `GET /UserViews` · `POST /Users/AuthenticateByName` · `GET /Users/Public` · `GET /QuickConnect/Enabled` · `GET /Artists` · `POST /UserFavoriteItems/{id}` · `GET /Audio/{id}/universal` (206) | |

**Never called in either run** — despite being in the client's source:
`/Items/Latest`, `/UserItems/Resume`, `/Videos/{id}/stream.mp4` (remux),
`/Videos/{id}/main.m3u8` (transcode), `/Videos/.../Subtitles/...`, trickplay
sheets, and every §4.6 write endpoint.

`/Items/Latest` and `/UserItems/Resume` are the interesting ones: the "Latest"
shelves and Continue Watching are served **entirely from Lumiere's local cache**,
never from these endpoints. Treat both as **not load-bearing** — a correction to
§4.2, which called them so on the strength of the client having the code.

### 12.2 `POST /Items/{id}/PlaybackInfo` — verified

```json
{ "MediaSources": [ … 1 source, 32 keys … ], "PlaySessionId": "<32 hex>" }
```

- **`ErrorCode` is absent entirely**, not null. Do not emit it on success.
- **`MediaSources[0].Id == the item id`** for a single-file item. Lumiere passes
  it back as `mediaSourceId` on every stream URL and progress report, so a server
  may legitimately use the item id as the source id.
- `TranscodingUrl` **absent** when direct play is possible;
  `TranscodingSubProtocol: "http"` present regardless.
- `SupportsDirectPlay`/`DirectStream`/`Transcoding` all `true` — computed from
  the profile Lumiere sends, and **ignored by Lumiere** (§5.3). A replacement
  server can hardcode them or omit them.

`MediaStreams` on the observed file (H.264 in **MKV**, AAC, SubRip):

| observed | consequence |
|---|---|
| `Profile` is a **string** on video and audio, **null** on subtitle | Lumiere's int-or-string decoder is load-bearing. Emit a string |
| `DvProfile` **absent** on non-DV content | absent ≠ null; the DV check tolerates both |
| `VideoRange: "SDR"` on video, **`"Unknown"`** on audio and subtitle | not null. The DV test uppercases and looks for `DOVI`/`DOLBY`, so `"Unknown"` is safe |
| `Width: 0` on the subtitle stream | not null |
| `IsDefault: true` on video, **`false` on the only audio stream** | Lumiere falls back to `audioStreams.first`, so this is survivable — but a server that marks no audio default is relying on that fallback |

This file is the decision table's row 6 in the wild: H.264 would suit AVPlayer,
but `Container: "mkv"` is outside `mp4/m4v/mov/qt`, so it went to **mpv as a
direct play** — no server work at all.

### 12.3 `GET /Videos/{id}/stream` — the range contract

Four requests for one playback, and their shape is the most important
implementation detail in this document:

```
bytes=37895286-     -> 206  bytes 37895286-314913633/314913634
bytes=314879532-    -> 206  bytes 314879532-314913633/314913634   ← last 33 KB
bytes=0-            -> 206  bytes 0-314913633/314913634
bytes=41170-        -> 206  bytes 41170-314913633/314913634
```

- **Every request is open-ended** (`bytes=N-`), never a bounded range.
- One reads the **last 33 KB of the file** — that is mpv fetching the Matroska
  cues at the tail before it will play. A server that streams only forward from
  an offset, or that mishandles a range near EOF, will hang here with no error.
- The seek at `37895286` is the resume position; playback then re-opens from `0`
  and `41170`. Expect **several concurrent open-ended readers on one file**.
- Response: `206`, `Accept-Ranges: bytes`, `Content-Range`, and a real
  container MIME (`video/x-matroska`).
- Auth is **`X-Emby-Token`** on every one of them — confirming §3.3. No token in
  the query string.
- Run 1 additionally shows an opening `bytes=0-1` two-byte probe on
  `/Audio/{id}/universal`. Handle a trivially small first range correctly.

### 12.4 `GET /Items` — envelope and what is really emitted

Envelope: `{"Items": [...], "StartIndex": n, "TotalRecordCount": n}` — all three
present on every page.

Paging observed: **`SortBy=SortName&SortOrder=Ascending&Limit=200`, 123 pages**,
~24,000 items. `EnableTotalRecordCount=true` and
`EnableImageTypes=Primary,Backdrop,Thumb,Logo` on every call.

Across 4,050 sampled items, emitted at:

- **100%**: `Id`, `Name`, `Type`, `ServerId`, `ParentId`, `IsFolder`, `UserData`,
  `DateCreated`, `Genres`, `IndexNumber`, `ImageTags`, `BackdropImageTags`,
  `SeriesId`, `SeriesName`, `SeriesPrimaryImageTag`, `PrimaryImageAspectRatio`,
  `LocationType`, `MediaType`, `ImageBlurHashes`, `GenreItems`, `ChannelId` (null)
- **98–99%**: `Path`, `ProductionYear`, `PremiereDate`, `Container`,
  `ParentIndexNumber`, `SeasonId`, `SeasonName`, `RunTimeTicks`, `VideoType`
- **92–96%**: `ParentBackdropItemId`, `ParentBackdropImageTags`, `HasSubtitles`,
  `Overview`, `ParentLogoItemId`, `ParentLogoImageTag`
- **72%**: `CommunityRating` — **float on 1,828 items, int on 1,102**. A server
  must be free to emit either; Lumiere decodes `Double` and takes both
- **36%**: `OfficialRating`; **13%**: `ParentThumbItemId`, `ParentThumbImageTag`

Emitted but **never decoded by Lumiere** — omit them and save the bytes:
`ImageBlurHashes` (large), `GenreItems`, `ChannelId`, `LocationType`,
`MediaType`, `VideoType`, `HasSubtitles`, `ParentLogoItemId`,
`ParentLogoImageTag`, `ParentThumbItemId`, `ParentThumbImageTag`,
`PrimaryImageAspectRatio` (requested in `Fields` but absent from the model).

No item in any list response carried `MediaSources` — the `listWithVersions`
field set (§5.4) did not run, its backfill marker already being set.

### 12.5 `UserData` — differs by item type

| Type | keys emitted |
|---|---|
| `Episode`, `Movie` | `ItemId, Key, Played, PlayCount, PlaybackPositionTicks, IsFavorite` (+`LastPlayedDate` on 3% — only what has been played; +`PlayedPercentage` on 1% — only what is in progress) |
| `Series`, `Season`, `Folder` | the same **plus `UnplayedItemCount` at 100%** |

`LastPlayedDate` and `PlayedPercentage` are **absent** rather than null when they
do not apply. Lumiere orders Continue Watching by `LastPlayedDate`, so a server
that never emits it silently reorders that shelf.

`POST /UserPlayedItems/{id}` → **200** with the full `UserData` object:
`Played: true`, `PlayCount` incremented, `PlaybackPositionTicks: 0`,
`LastPlayedDate` set.

`DELETE /UserPlayedItems/{id}` → **200**, `Played: false`, **`PlaybackPositionTicks: 0`**,
`PlayCount: 0`, `LastPlayedDate` absent. This resolves §9.7: the delete **is**
Lumiere's resume reset, and a server that leaves the position intact will make
watched episodes resume at the end — the exact bug fixed on the client this week.

### 12.6 `GET /MediaSegments/{id}` — the server has segment data

Repeated `includeSegmentTypes` parameters, as §7.3 requires. Response is the
standard envelope, not a bare list:

```json
{"Items":[{"Id":"…","ItemId":"…","Type":"Outro","StartTicks":…,"EndTicks":…}],
 "StartIndex":0,"TotalRecordCount":1}
```

`ItemId` is present on each segment (Lumiere ignores it). One `Outro` returned
for the episode tested.

### 12.7 Detail fetch

`GET /Users/{id}/Items/{id}?Fields=<detail>` returns **65 keys**, including
`MediaSources`, `MediaStreams`, `Chapters`, `People`, `Studios`, `Genres`,
`ProviderIds`, `Tags`, `LockedFields`, `SortName`, `Overview`. This confirms §5.5:
the editor's read-modify-write really does carry `ProviderIds` and `LockedFields`
through, and a server implementing `POST /Items/{id}` as a **merge-patch** avoids
the whole hazard.

Three distinct `Fields=` values were seen, exactly matching the three field sets
in the client: the `list` set, the `detail` set, and a bare `Trickplay`.

### 12.8 What is still unmeasured

1. **The remux path** (`stream.mp4`) — never requested, consistent with §6.4's
   finding that no branch selects it. Reasonable to omit from v1 entirely.
2. **The incremental sync** (`SortBy=DateCreated` descending) — never ran; the
   cache was warm and the observed sync was the full `SortName` pass.
3. **External subtitle fetches** — no `/Subtitles/.../Stream.srt` request. The
   files tested had embedded tracks, which mpv renders itself.
4. **`/Items/Latest` and `/UserItems/Resume`** — see §12.1. Not called at all.
5. **Trickplay sheets** — `Fields=Trickplay` was requested, but no
   `/Videos/{id}/Trickplay/...` sheet was fetched.

### 12.9 The transcode path — verified

Reached by capping the bitrate below the file's own. Note that on this library
**the shipping UI could not reach it**: the picker floored at 4 Mbps against a
~2.7 Mbps average, so no cap on offer could ever bite. Two lower options (2 and
1 Mbps) were added to make the capture possible; they are also the caps that mean
anything away from a LAN.

Volume: 4 × `main.m3u8`, 119 × segment 200s, **5 × segment 500s**.

#### 12.9.1 `GET /Videos/{id}/main.m3u8`

Request carries exactly what §6.3 says — `mediaSourceId`, `videoCodec=h264`,
`audioCodec=aac`, `transcodingContainer=ts`, `transcodingProtocol=hls`,
`playSessionId` — and **nothing else** (see 12.9.3).

Response: `200`, `Content-Type: application/vnd.apple.mpegurl`, and a **complete
VOD media playlist — not a master playlist**:

```
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:3
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:3.000000, nodesc
hls1/main/0.ts?mediaSourceId=…&videoCodec=h264&audioCodec=aac&…
… ~860 segments, 1,732 lines …
```

Three things a replacement server must copy, and one freedom it gains:

- **One media playlist, no variants.** AVPlayer is handed this directly. There is
  no master playlist and no bandwidth ladder.
- **Every segment listed up front**, 3 seconds each, for the whole runtime —
  `PLAYLIST-TYPE:VOD`, so the client may seek anywhere in it immediately.
- Segment URIs are **relative** and repeat the full query string.
- **The segment URL scheme is the server's to choose.** Lumiere builds only the
  `main.m3u8` URL; every segment URL comes out of the playlist. `hls1/main/{n}.ts`
  is Jellyfin's convention, not a contract.

#### 12.9.2 `GET /Videos/{id}/hls1/main/{n}.ts`

`Content-Type: video/mp2t`, ~1.9 MB per 3-second segment. Query carries the
transcoding parameters plus `playSessionId`, `runtimeTicks` and
`actualSegmentLengthTicks`. Auth is **`X-Emby-Token`**, as everywhere else.

**Five segments returned `500 Error processing request.`** (`text/plain`, 25
bytes) — segment 326 of ~860 among them. Jellyfin's transcode is a live ffmpeg
process with a moving window, and a segment requested far outside it fails. The
client did not surface an error, so playback survived it. A replacement server
must decide deliberately what happens when a segment far from the current
encoding position is requested: encode on demand, redirect, or fail — but fail
*predictably*, because the client will not tell the user.

#### 12.9.3 Client bug found by this capture

**The bitrate cap never reaches the server.** `PlayerModel.playbackRequest` calls
`StreamBuilder.stream(…)` without `maxBitrate`, `audioStreamIndex` or
`subtitleStreamIndex`, so all three default to nil — and `playbackInfo(itemId:)`
is likewise called without `maxBitrate`. Confirmed in the traffic: **no
`PlaybackInfo` request carried `MaxStreamingBitrate`, and no `main.m3u8` request
carried `maxStreamingBitrate` or `videoBitRate`.**

So the cap decides *whether* to transcode and says nothing about *to what*. The
server re-encodes at its own default — the segments measured ~5 Mbps against a
1 Mbps cap. Someone who sets a cap to protect a slow connection gets a transcode
that ignores it.

**Fixed and re-captured** (Lumiere `b15820e`, verification log
`capture/capture-verify-bitrate.jsonl`, 125 exchanges). The cap now has one
definition read by all three places that need it, and the traffic confirms it end
to end — not merely that the parameters appear, but that the encode changed:

| | before | after |
|---|---|---|
| `PlaybackInfo` body | no `MaxStreamingBitrate` | `1000000` |
| `main.m3u8` query | neither parameter | `maxStreamingBitrate=1000000`, `videoBitRate=1000000` |
| segment size (3 s) | ~1.9 MB | **0.47 MB** |
| effective bitrate | ~5 Mbps | **~1.2 Mbps** |

Consequences for the server build:

- **`MaxStreamingBitrate` on `PlaybackInfo` and `maxStreamingBitrate`/`videoBitRate`
  on the HLS URL are both live and must be honoured.** Jellyfin honours them
  closely — 1.2 Mbps delivered against a 1 Mbps request — and a replacement that
  ignores them silently defeats the client's only bandwidth control.
- **`audioStreamIndex` is live too** (Lumiere `PreferredTracks`, verification log
  `capture/capture-verify-tracks.jsonl`): a capped session now sends
  `audioStreamIndex=2&maxStreamingBitrate=1000000&videoBitRate=1000000`, and the
  index is Jellyfin's own `MediaStream.Index` — **not the position in the stream
  array**. A server that treats it as an array offset will transcode the wrong
  language.
- `subtitleStreamIndex` and `subtitleMethod=Encode` are sent by the same code path
  but were absent from this capture, correctly: the stored preference had
  subtitles off, and "off" is a choice the client honours by sending nothing. The
  branch is covered by unit tests rather than by traffic. **A server must still
  implement burn-in** — it becomes reachable the moment a user enables subtitles
  on a transcoded file.

#### 12.9.4 `PlayMethod` during a transcode

`/Sessions/Playing` and `/Sessions/Playing/Progress` report
**`PlayMethod: "DirectPlay"` while the server is transcoding** — §6.6's warning,
now observed on the transcode path itself. `/Sessions/Playing/Stopped` omits
`PlayMethod` entirely. **A server must never infer the route from these reports.**

### 12.10 `ParentId` is a *logical* parent, not the row's

Measured across every list response in the capture:

| objects | invariant | exceptions |
|---|---|---|
| 67,946 `Episode` | `ParentId == SeasonId` | **0** |
| 5,026 `Season` | `ParentId == SeriesId` | **0** |

Jellyfin never reports the physically containing folder as an episode's parent,
whatever its own database holds. This is not cosmetic: **Lumiere lists a season's
episodes by `ParentId`**, so an episode reported with its folder as parent does
not appear under its season at all.

The failure is invisible from every direction except the screen. The rows sync,
the item counts match exactly, the episodes are in the client's cache — and the
season page is empty. It cost a bug report reading "some series episodes are not
being displayed", where the real symptom was 1,928 of 2,026 episodes in one
library carrying a parent the client would never ask for.

Related: §5.4 records the *opposite* quirk for folder libraries, where `ParentId`
is unreliable and Lumiere keys on `Path` instead. Both are the same underlying
fact — Jellyfin's `ParentId` is a computed answer, not a column.

### 12.11 Artwork formats

`GET /Items/{id}/Images/{kind}` returned **both `image/jpeg` and `image/png`** in
the capture. A replacement server that normalises everything to JPEG for the
resize path will look correct on posters and backdrops — which are photographic
and opaque — and will put a black rectangle behind every logo it had to resize.

Two details that make it hard to spot:

- An image narrower than the requested `maxWidth` is served untouched, so only
  logos wide enough to need resizing are damaged. It reads as intermittent.
- The client caches on `tag` + width and never revalidates (§7.1), so a bad
  variant persists until its artwork tag changes or the cache is cleared.
