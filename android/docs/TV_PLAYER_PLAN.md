# Lumiere TV — player overhaul plan

Target: the Aurzen Boom Air projector (Android 11, about 2 GB of memory, 960 × 540 dp at density 2, Reduce Motion on).
Reference: the Apple TV app's player on tvOS 17/18, and Apple's Human Interface Guidelines for tvOS (playing video, focus, symbols).
Scope: the TV player only. The phone player (`PhoneChrome.kt`, `PhoneSheets.kt`) is not touched; anything shared that would help it is noted for the phone session.
Status: a plan. Nothing here is built yet. It is built in the order of section 9, one shippable step at a time.

---

## 1. The goal in one sentence

While a film plays, the screen shows the film and nothing else. Everything else lives behind one press and is drawn with one set of crisp, monochrome vector symbols, in Apple's layout, sizes and motion.

## 2. The roles behind this plan

Each step is written and checked from these points of view. Each role has a sign-off question.

| Role | Owns | Sign-off question |
|---|---|---|
| **Interaction designer (tvOS)** | States, the remote map, focus paths, what each press does | Can someone who has only used an Apple TV operate it without being told? |
| **Visual and symbol designer** | The symbol set, type, sizes, colour, scrims | Is anything on screen that does not need to be? Is every mark sharp at 3 m? |
| **Motion designer** | Timings and curves for show, hide, scrub and panels; Reduce Motion | Does anything move that does not explain something? |
| **Playback engineer** | Media3, seeking accuracy, trickplay memory, buffering, reporting | Does any change cost frames, memory or a report? |
| **Accessibility reviewer** | Contrast, text size, focus visibility, captions, spoken labels | Can it be used at the back of the room, with captions, half asleep? |
| **QA on the projector** | The check-list in section 10, run by you on the real device | Does it behave the same on the 100th press as on the first? |

At two checkpoints (after steps 3 and 7) I'll run the design-critique and accessibility-review passes against screenshots you take on the projector. Their findings get fixed before the next step.

---

## 3. What exists today, and what changes

| Today (`Controls.kt`, `PlayerScreen.kt`, `InfoPanel.kt`, `TvPlaybackMenu.kt`, `Tracks.kt`) | Problem | Becomes |
|---|---|---|
| A top bar: back arrow, title, subtitles and tune icons | Phone-style. Apple has no back button and no top bar | Removed. The title moves above the progress bar; the icons move to the bar's right end |
| A centre row: −10, Play/Pause (76 dp), +10 | Distracting. tvOS has no on-screen play button | Removed. The remote does it, and the bar shows the state |
| Material `Slider` with a round thumb | Not Apple's bar. The thumb is a phone control | A custom transport bar: a thin bar that thickens when chosen, white fill, a playhead line, the time above it while scrubbing |
| An 84 dp play/pause glyph flashing in the centre | Not Apple's. It covers the picture | Removed. The bar appears briefly with a small state glyph at the playhead |
| Text bubbles: "+10s", "30%", chapter names in the centre | Covers the picture | A small skip mark beside the playhead, fading in 0.6 s |
| Swipe-down panel with tabs (Info, Chapters, Audio & Subtitles…) as pills | Close to Apple's, but pill-styled and full-width | Apple's content tabs below the bar: **Info · Chapters · Episodes**, as text tabs |
| The playback menu (speed, picture, tone…) and the Audio & Subtitles sheet | Two separate places | Two symbol buttons on the bar (Subtitles, Audio) and one "More" (⋯) holding everything else, each opening a tvOS popover menu |
| Up Next card, Skip Intro, Still Watching, end card, resume prompt | Mixed shapes and sizes | One Apple button style; Up Next with a countdown ring |
| Unicode glyphs as icons ("▶", "›", "✓", "★", "✕", "♪", "↕") and Material Icons of mixed weights | Soft or uneven on the projector, inconsistent stroke | One Lumiere vector symbol set (section 6) |

---

## 4. The player's states

The player is always in exactly one of these states. Every press is defined per state in section 5.

1. **Playing, clean.** Only the film. Subtitles, if on, sit 6 % above the bottom. Nothing else is drawn, not even a clock.
2. **Transport.** Shown by OK, Up, Down, Left, Right or Play/Pause. It hides 5 s after the last press while playing, and stays while paused.
   - The scrim is a soft gradient on the bottom 35 % only, 0 → 70 % black.
   - **Title block** (left, above the bar):
     - the show or film name, 20 sp semibold
     - for an episode, a second line "S2 E4 · Episode name", 14 sp at 70 % white
   - **Button row** (right, above the bar, on the title's baseline), round 40 dp buttons with 20 dp symbols:
     - Subtitles (a speech bubble)
     - Audio (a waveform)
     - More (⋯)
     - Next episode (a skip-forward symbol), only for an episode
   - **The bar:**
     - full width minus 56 dp margins; 6 dp thick at rest and 10 dp when chosen
     - fully rounded ends; elapsed part in white, the rest at 30 % white, buffered part at 45 % white
     - chapter marks as 2 dp gaps in the bar
   - **Times** (below the bar, 13 sp tabular figures):
     - elapsed at the left
     - remaining at the right ("−42:10")
     - "Ends at 10:42 PM" beside the remaining time, at 60 % white
3. **Scrubbing.** Left or Right with the bar chosen.
   - The film pauses under a dark veil.
   - A 16:9 trickplay frame (240 × 135 dp, 10 dp corners) rides above the playhead, with the target time and chapter name under it.
   - The playhead becomes a 2 dp white line through the bar.
   - OK plays from there. Back cancels and returns to where it was, as Apple does.
4. **Content tabs.** Down from the bar. The bar slides up by 120 dp and a strip of tabs appears under it:
   - **Info:** the poster, synopsis, year, rating, runtime and badges for 4K, HDR, Dolby Vision, Atmos and CC
   - **Chapters:** only when the file has chapters. A row of 16:9 trickplay cards with names and times
   - **Episodes:** for an episode. The season's episodes as 200 dp cards, the current one marked, with a season switch
   - Up returns to the bar; Back returns to Playing.
5. **Popover menus.** OK on a bar symbol opens a frosted popover above that button, 320 dp wide, as tvOS draws them. Rows have ticks, and sections have small captions.
6. **Paused screen.** Paused for 6 s with no press:
   - the frame dims to 60 %
   - the transport hides
   - the title, episode line, synopsis (two lines) and the clock show at the lower left, as Apple's pause screen does
   - any press brings back the transport.
7. **Interruptions:** each uses one Apple button style (white capsule when chosen, frosted when not). Offers that ride along with the film (Skip Intro, Up Next) sit at the bottom right. Questions that stop it (Resume, Still Watching?, the end card) stay centred, as tvOS alerts are.
   - Resume prompt
   - Skip Intro / Skip Recap
   - Up Next
   - Still Watching?
   - End card
   - Reconnecting
   - Error

---

## 5. The remote map (tvOS behaviour)

| Press | Playing, clean | Transport | Scrubbing | Content tabs | Popover |
|---|---|---|---|---|---|
| OK | Pause and show the transport | Pause/play (bar chosen); open (button chosen) | Play from the target | Open the chosen card | Choose |
| Play/Pause | Pause/play; the transport shows for 2 s | Pause/play | Play from the target | Pause/play | Pause/play |
| Left / Right | −10 s / +10 s, with a small skip mark beside the playhead | Bar chosen: start scrubbing. Button row: move between buttons | Move the target; held, it accelerates 10 → 30 → 60 s per step | Move along cards | — |
| Up | Show the transport | From the bar: to the button row | — | Back to the bar | Up the list |
| Down | Show the transport with the tabs | From the bar: to the tabs | — | Into the tab's cards | Down the list |
| Back | Show the transport (a stray Back never ends the film) | Bar chosen: leave the film. Button row chosen: back to the bar | Cancel the scrub | Back to the bar | Close |
| Hold Back | Leave the player | Leave | Leave | Leave | Leave |
| Menu / Settings key | The More popover | The More popover | — | — | — |
| Fast-forward / Rewind keys | ±30 s | ±30 s | — | — | — |
| Next / Previous, Channel ± | Next / previous chapter | Same | — | — | — |
| 0–9 | Jump to that tenth | Same | — | — | — |

Focus rule: the transport always opens with the **bar** chosen, never a button. So Left and Right always mean time, as on Apple TV.

---

## 6. Vector symbols ("vector mark based")

How I read your request: every mark on screen should be a vector drawn at the screen's real resolution, so it is sharp and visible on the projector, rather than a text character or a picture file that blurs or misaligns. Everything is already sized in dp and sp, so it scales with the screen. What is left to do is the marks themselves.

### 6.1 One symbol set
- **`ui/Symbols.kt`:** a single `object Symbols` of `ImageVector`s in one style, the way Apple's SF Symbols are one family.
  - 24-unit grid, 2-unit stroke, rounded caps and joins, filled versions for the "on" states.
  - Drawn in code, so there are no files to load and nothing to decode on the low-memory projector.
- **Player symbols:**
  - play, pause
  - skip back 10, skip forward 10
  - skip to next
  - subtitles (speech bubble, plus a filled form when on)
  - audio (waveform)
  - more (⋯)
  - chapters, episodes, info
  - speed
  - picture (aspect)
  - sleep (moon)
  - airplay-style "on the phone" (phone remote)
  - check (tick), chevron right, close
  - live
  - lock (private)
- **App symbols** (replacing the Unicode marks found in the code):
  - `▶` → play
  - `›` → chevron
  - `✓` → check
  - `★` / `☆` → star filled / outline
  - `✕` → close
  - `♪` → note
  - `↕` → sort
  - `…` → more
  - `↓` → download

  Sections in the sidebar and Settings keep the monochrome Material set already chosen. It will be swapped to `Symbols` only where a mark is missing or its stroke clashes.
- **Sizes:** symbols use three sizes: 16 dp (inline with text), 20 dp (in buttons), 28 dp (alerts). Symbol weight follows text weight, as SF Symbols do.

### 6.2 Bitmaps that remain
- **`res/drawable-xhdpi/banner.png`:** the Android TV launcher banner. **Kept as a picture.** It is 640 × 360, already sharp at the launcher's 320 × 180 dp, and its lettering would have to be redrawn by hand to become a vector.
- **`res/drawable-nodpi/boot_icon.png`:** stays a bitmap. It was made a bitmap on purpose after the adaptive-icon crash. Swapping it back is not worth that risk.

### 6.3 Text
- All player text uses `TvType` with tabular figures for times, so the time does not jitter as digits change.
- Numbers on the bar use 13 sp at 85 % white, the smallest size readable at 3 m on the projector's 540-line picture.

---

## 7. Menus (everything hidden, nothing lost)

Every setting that exists today is kept; it just moves behind a symbol. The popovers are tvOS's: frosted, 320 dp wide, ticks before the chosen row, captions over sections.

- **Subtitles** (speech bubble):
  - Off · Auto (forced only) · each language, with "SDH" and "Forced" tags
  - a divider, then **Style**, which opens a submenu: Size, Look, Position, Live preview on the paused frame
  - **Find Subtitles…** and **Fix Timing…** (existing)
- **Audio** (waveform):
  - each track, in the form "English · 5.1 · Dolby Digital"
  - a **Sound** section: Full Dynamic Range / Reduce Loud Sounds (today's Night Sound), and Enhance Dialogue (today's Dialogue Boost, Off / +3 / +6 / +9 dB)
- **More** (⋯):
  - Playback Speed
  - Picture (Fit / Fill)
  - Picture Tone
  - Lamp
  - Sleep Timer
  - Phone as Remote
  - **Playback Info** (the statistics view already built)
- **Next episode** (skip symbol): plays the next episode at once. Shown only when there is one.

The old Info panel pill tabs and the separate Audio & Subtitles sheet are retired. Their contents now live in the tabs (section 4.4) and the popovers above.

---

## 8. Motion, memory and resilience

- **Timings:**
  - Transport in: 200 ms fade, plus a 12 dp rise of the bar.
  - Transport out: 300 ms fade.
  - Bar thicken: 150 ms.
  - Tabs: 250 ms slide.
  - Popover: 180 ms scale-from-button plus fade.
  - With Reduce Motion on (as on the projector), every one of these becomes a 0 ms switch; fades stay at 120 ms so nothing pops harshly.
- **Hide timing:** 5 s while playing (Apple's), never while paused, scrubbing, or with a tab or popover open.
- **Memory:**
  - One trickplay sheet held at a time, decoded at 240 dp.
  - Tab cards load only when the tab opens and are dropped when it closes.
  - The image cache is cleared on entry (kept).
- **Accuracy:** a seek on release goes to the nearest keyframe on HDDs over the network; the time shown snaps to where the player actually landed.
- **Reporting:** unchanged. Progress every 10 s, a final report on every exit path.
- **Kept from the last plan:**
  - the resume prompt
  - Loading… % and Try Again
  - Reconnecting to the Mac
  - the film end card
  - the 3-hour Still Watching
  - the Back behaviour

  All of these are restyled into the one button style.

---

## 9. Order of work

Each step is built, tested and published on its own. You check it on the projector before the next.

1. **Symbols:** `ui/Symbols.kt` and a test that every symbol builds. Swap the Unicode glyphs in the player files first, then app-wide. The banner becomes a vector, with a startup test.
2. **Transport bar** (new `player/TransportBar.kt`): the bar, times, "Ends at", the title block and the button row. The top bar, centre row, Material slider and centre glyph are removed from the TV branch of `Controls.kt`. The phone branch is untouched.
3. **Scrubbing:** the trickplay frame over the playhead, the veil, OK to commit and Back to cancel, acceleration on hold.
   - **Checkpoint 1:** design-critique and accessibility-review passes on your screenshots.
4. **Remote map:** section 5 in full, including the Back rules, Play/Pause showing the bar for 2 s, and the skip mark beside the playhead.
5. **Popovers:** Subtitles, Audio and More (section 7), replacing `TvPlaybackMenu` and the TV use of `TrackSheet`. Track names in Apple's form.
6. **Content tabs:** Info, Chapters and Episodes under the bar, replacing the TV `InfoPanel` and `EpisodeStrip` entry points.
7. **Paused screen and interruptions:** the pause screen, then Skip Intro, Up Next with a ring, Still Watching, the end card, Resume and Reconnecting, all in the one button style at the bottom right.
   - **Checkpoint 2:** design-critique and accessibility-review again.
8. **Polish:** the motion timings, Reduce Motion, tabular figures, memory check (Playback Info stays under the old buffer figures), and the app-wide glyph swap finished.

---

## 10. How each step is checked

- **On the Mac:** `./gradlew -q assembleTvRelease testDebugUnitTest` must pass, then a commit and `./Scripts/publish.sh`.
- **Unit tests:**
  - every symbol builds
  - the remote map as a pure state machine (press × state → next state), tested without a screen
  - the Ends-at and remaining-time sums
  - the track names ("English · 5.1 · Dolby Digital")
- **Your checks on the projector** (a short list sent with each step):
  1. While playing, nothing is on screen.
  2. OK pauses and shows the bar. Left and Right then move time, never a button.
  3. Scrub, then Back: you return to where you were.
  4. Up reaches Subtitles, Audio and More. Each opens above its button with the current choice ticked.
  5. Down shows Info, Chapters and Episodes. Back returns to the film.
  6. Paused for 6 s, the pause screen shows. Any press brings the bar back.
  7. A stray Back never ends the film. Holding Back always leaves.
  8. Every mark is sharp. Nothing is blurred, misaligned or a text character.
- **Diagnostics:** any crash or error is sent by the existing diagnostics and read from the server log before the next step.

---

## 11. Decided against
- An on-screen Play button, top bar or Back arrow on the TV: not Apple's, and they distract.
- Coloured progress (gold accent) in the player: Apple's bar is white. The gold stays for progress on cards outside the player.
- Audio sync in ±50 ms steps: still not supported by Media3 (see TV_UX_PLAN §6).
- Profiles: cancelled by you.
