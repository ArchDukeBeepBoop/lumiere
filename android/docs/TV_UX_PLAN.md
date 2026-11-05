# Lumiere TV — UI/UX plan (Home, other pages, player)

Target: the Aurzen Boom Air projector (Android 11, ~2 GB, 960×540 dp, Reduce Motion on).
Reference: Apple TV app (tvOS 17/18) for sizing and type; the Lumiere Mac app for the sidebar.
Nothing in this plan is built yet. It goes in the order of section 5, one shippable step at a time.

---

## 0. Principles (the rules every screen follows)

1. **One type scale, Apple-sized for a 10-foot screen** (dp at 960×540):
   | Role | Size / weight | Used for |
   |---|---|---|
   | Display | 40 / Bold | banner title when there is no logo |
   | Title | 22 / Semibold | page titles |
   | Row title | 17 / Semibold | every row label |
   | Body | 13.5 / Regular, line 19 | synopsis, descriptions |
   | Meta | 12.5 / Medium, 70 % white | "TV Show · Drama · 2021" |
   | Badge | 10 / Semibold, outlined | rating, 4K, HDR, CC |
   | Caption | 12 / Regular | card titles under focus |
2. **One spacing grid**: page margin 56, card gap 24 (down from 32, so more cards and rows fit), row gap 20, section gap 32.
3. **One focus language**: cards scale 1.08 with a white ring and a soft shadow; capsules turn white with black text; nothing else glows.
4. **One scroll model** (built already, kept): the page steers its own scroll; the chosen row lands at a fixed line; along a row the chosen card is pinned at the margin.
5. **Always show what comes next**: the chosen row plus at least half of the next row must be on screen at all times.
6. **Monochrome symbols**: white or grey symbols, no coloured tiles. Colour is kept for meaning (red = destructive, gold = progress or accent).
7. **Low-memory first**: backdrops decoded at the screen size, one backdrop in memory at a time, no infinite animations on the projector.

---

## 1. Home

### 1.1 Problems today
- The banner is too tall (82 % of the screen) and its type too big: a 130 dp logo, 50 sp title, three lines of 16 sp story and a 17 sp Play.
- The information area under the banner takes 42 % of the screen. With rows about 52 % tall, the next row has about 6 % left, so the coming posters don't show while scrolling down.
- The row title, card and caption stack is taller than it needs to be.

### 1.2 Banner (Apple TV-sized)
- **Height:** 62 % of the screen. The picture stays full-bleed, darkening from 55 % of the height into the ground. The first row's title and the top third of its cards show at the bottom.
- **Logo:** at most 72 dp high and 300 dp wide. The fallback title is 40 sp bold.
- **Meta line:** 12.5 sp at 70 % white, with outlined badges (10 sp) for the rating, 4K or HD, HDR or Dolby Vision when the file has it, and CC.
- **Synopsis:** 2 lines, 13.5 sp, line height 19, at most 380 dp wide (about 40 % of the screen). It is never wider than the logo block.
- **Buttons:** 40 dp high. A white Play capsule with 15 sp semibold text, then round frosted + and ⓘ at 40 dp.
- **Page dots:** 6 dp, lower right, lined up with the buttons.
- **Timing (suggestion 3):** the banner turns every 8 s and holds still while the remote is on Play or ⓘ.

### 1.3 Rows
- **Information area:** replaced by a compact title strip of 24 % of the screen: the picture at the right and fading, the title at 20 sp, the meta at 12.5 sp, and one line of synopsis. This is Apple TV-sized and quieter than Google TV's.
- **Landing line:** the chosen row lands at 26 % of the screen, just under the strip.
- **Row height targets:**
  - poster rows: about 40 % of the screen (title 17 + gap 8 + card + 12 caption space)
  - wide rows: about 30 %
- **What shows beneath:** at least half of the next row, and usually all of it on wide rows, so the coming posters are always in view.
- **Posters:** six across, gap 24. That makes each poster about 124 dp wide and 186 dp tall, so the row is smaller in height than today because the padding is cut.
- **Captions:** only under the focused card. Continue Watching and Up Next keep theirs.
- **Last row:** bottom padding equal to the landing line, so it can still reach the line.

### 1.4 Sidebar
- No change in behaviour. Icons stay monochrome. The row position text ("Row 3 of 9") stays.

---

## 2. Other pages

| Page | Plan |
|---|---|
| **Title (show or film)** | Same banner sizing as Home: a 72 dp logo, 2-line synopsis, 40 dp buttons and a 62 % top. Seasons capsule pills at 13 sp. Episode cards at 240 dp wide (16:9) with 12 sp captions. Episode strip at 24 % (the compact strip from 1.3). The landing line for episodes moves to 26 %. |
| **Library** | Featured banner reduced to 160 dp tall. The compact strip instead of the 38 % information area. Posters six across, gap 24. Capsule tabs at 13 sp. |
| **Music** | Same as the Library: the compact strip, covers six across, gap 24. Album page: cover 260 dp, track list rows 44 dp with 14 sp titles. |
| **Settings** | Section symbols become monochrome white glyphs (no coloured tiles), as Apple's tvOS Settings. Sections and options stay in their capsules. Option rows are 52 dp with 15 sp titles; explanations show only on the chosen row (kept). |
| **Person (suggestion 1)** | A round photo (120 dp), the name at 22 sp, the bio in 2 lines of 13.5 sp, with a MORE sheet. Rows Known For, Movies, TV Shows with pinned cards, and the compact strip while browsing them. |
| **Genre (suggestion 1)** | The banner as Home's (62 %, logo, 2 lines), then rows Top Rated, Recently Added, All (grid). The compact strip while browsing. |
| **Search (suggestion 2)** | The letter line at the top. Under it a Top Result in Apple's layout: a wide card 300 dp, with the title, meta and a Play capsule beside it. Then pinned rows: Movies, Shows, Episodes, People (round). The compact strip while browsing the rows. |
| **Settings symbols (suggestion 4)** | A small monochrome symbol beside every section in the capsule, matching the large one above. |
| **Folders, collections, playlists, downloads** | The same grid metrics (six across, gap 24), the compact strip, capsule headers. |

---

## 3. Player (industry practice: Apple TV, Netflix, Plex, Infuse)

### 3.1 What exists
- **Transport and scrubbing:** a tvOS transport bar (title above it, white bar, time left), a trickplay strip and chapter marks.
- **Panels:** the info panel with tabs (Info, Chapters, Audio and Subtitles, Episodes, Speed and Picture), the tvOS playback menu with ticks, and Audio and Subtitles with Find and Fix Timing.
- **Episodes and endings:** skip intro and credits, the Up Next card, the credits shrink, "Still watching?" and the sleep timer.
- **Sound and picture:** per-show track memory, per-show subtitle size and fit, night sound and dialogue boost.
- **Resilience:** crash and error guards.

### 3.2 Additions and changes

**A. Start and resume**
1. **Resume prompt:** for a title started before and not near its start, an Apple-style choice when Play is pressed: **Resume from 42:10** (focused) or **Start from Beginning**. This is skipped when Play came from a Resume button or Up Next.
2. **Instant first frame:** keep the veil, and add the title card (logo or name, plus S2 E4) for the first 2 s while the stream buffers, like Netflix's ident.
3. **Buffering:** a small ring at the centre, which after 4 s also shows "Loading… 62 %" (the buffered share), and after 15 s offers **Try Again** and **Lower Quality**. Lower Quality asks the Mac to convert the video.

**B. Transport**
4. **Seeking:**
   - A single Left or Right press jumps 10 s and shows a "−10" or "+10" bubble.
   - Holding steps 10, 30 and 60 s and accelerates (the hold already exists; the tap bubble and the step labels are added).
   - While scrubbing, the trickplay strip and the time at the thumb stay visible.
5. **"Ends at 10:42 PM"** under the time left, as Apple shows it.
6. **Auto-hide:** the controls hide after 4 s while playing and stay while paused. Any key brings them back without acting, except Play/Pause and Left/Right.
7. **Play/Pause feedback:** a large ▶ or ❚❚ glyph flashes in the centre for 0.5 s. When paused, a dimmed frame shows the title, the episode and the clock (tvOS pause screen).
8. **Chapters:** a long press of Down opens Chapters directly. The chapter name shows on the bar.

**C. Info and options**
9. **Swipe-down panel:** the tabs become **Info**, **Episodes**, **Audio**, **Subtitles** and **Speed & Picture**, with Audio and Subtitles split as tvOS does, each a list with ticks.
10. **Subtitle appearance** in place: the size and look rows show a live preview line over the paused frame.
11. **Audio sync:** ±50 ms steps, remembered per file, for a projector connected to a soundbar.
12. **Stats for nerds:** a hidden "Playback Info" row at the bottom of Speed & Picture. It shows the resolution, codec, bitrate, dropped frames, buffer, whether the audio is direct or converted, and the HDR state. It's useful for diagnostics.

**D. Endings and continuity**
13. **Credits:**
    - With a next episode: the existing Up Next card at the bottom right, counting from 10.
    - For a film: a **"Watch Again / Back to Lumiere"** end card with a "More Like This" row.
14. **Auto-play limits:** "Still watching?" after 3 episodes or 3 hours, whichever comes first (the hour limit is new).
15. **Back during playback:** the first press shows the controls, the second leaves (Apple TV's behaviour), so a stray Back doesn't end the film.
16. **Leaving:** return to the title page with the progress updated and the remote on the next episode.

**E. Resilience and performance**
17. **Network drop:** pause, show "Reconnecting to the Mac…", resume at the same frame when the Mac answers, and offer the downloaded copy if one exists.
18. **Decoder failure:** fall back automatically to the Mac's conversion (audio already does this; extend it to video for HEVC 10-bit failures seen in the logs).
19. **Memory:**
    - Clear the image cache on entry (kept).
    - Hold one trickplay sheet in memory at a time.
    - Tune the buffer by link (kept).
20. **Reporting:** progress every 10 s (kept), and a final report on every exit path, including a crash.

---

## 4. Out of scope / decided against
- Tabs across the top as an option (suggestion 5): declined by the user.
- Coloured settings tiles: removed, per the user.
- Infinite banner drift on the projector: kept off (memory and Reduce Motion).

---

## 5. Order of work (each step is built, tested and published on its own)
1. **The type scale and spacing tokens:** a `TvType` and `TvSpace` object in `ui/`. Home, Hero and InfoArea are moved onto them.
2. **Home:** the banner resize, the compact strip (24 %), the landing line at 26 %, tighter rows, and the banner timing. Check: the next row shows at every scroll step.
3. **Settings:** monochrome symbols, and symbols beside each section.
4. **Title pages:** the sizing from section 2, the episode strip, and the landing line.
5. **Library and Music:** the compact strip and the grid metrics.
6. **Person, Genre and Search:** the layouts from section 2.
7. **Player A and B:** the resume prompt, title card, buffering, tap-seek bubble, "Ends at", auto-hide, and play/pause feedback.
8. **Player C:** the panel tabs, subtitle preview, audio sync, and stats.
9. **Player D and E:** end cards, auto-play limits, Back behaviour, network and decoder recovery.

Each step ends with assembleTvRelease and the full unit tests green, then a publish. The projector check is the user's (no device here).

---

## 6. Where the build differs from the plan (steps 8–9)
- **Audio and Subtitles stay one sheet** (the existing one with Find and Fix Timing), reached from the playback menu. Splitting it gained little on a remote.
- **Subtitle preview:** the playback menu sits beside the picture, so a size or look change shows on the live subtitles at once. No separate preview line.
- **Audio sync (±50 ms):** not built. Media3 has no supported audio offset, and faking one risks drift.
- **Decoder fallback to the Mac's conversion:** not built. It needs a server route for video conversion first.
- **Network drop:** the TV waits for the Mac (checking every 5 s), then carries on from the same moment. Offering the downloaded copy is not built yet.
