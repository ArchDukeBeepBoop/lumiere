# Lumiere for Meta Quest 3 — Plan

Status: **approved 2026-10-07, no code yet.** Decisions in §2 and answers in §11 are settled; Order changed (plan A, 2026-10-07): v0.5 ships first as a build variant of the existing app, and the module split moves to just before the spatial shell.

## 1. Goal

A Quest 3 app that feels like Lumiere on Apple Vision Pro would: the same calm
library, spotlights and player as the Mac and TV apps, carried into space with
visionOS manners — glass windows that float in your room, a theatre you can
step into, and nothing between you and your files. It talks to the same
`server/` as every other Lumiere app, with no server changes required for the
first release.

### Non-goals (v1)
- Store distribution (sideload / Horizon "App Lab"-style unlisted builds only, same as the Android app today).
- Social co-watching or multiple users — the app is single-user (decided, not deferred).
- Hand-tracked keyboards beyond the system one, game-engine content.
- Any new server feature that the Mac/TV apps can't also use.

## 2. Key decisions (approved)

| # | Decision | Recommendation | Why |
|---|---|---|---|
| D1 | Engine | **Meta Spatial SDK (Kotlin, native Android)** — not Unity/Unreal | Horizon OS *is* Android. The existing app is Kotlin + Compose + Media3; Spatial SDK hosts Compose panels and ExoPlayer surfaces directly, so `api/`, `player/`, `cache/`, `downloads/` and most of `ui/` carry over. Unity would mean rewriting the client in C# and losing parity forever. |
| D2 | Code layout | Split `android/` into Gradle modules: `:core` (api, models, cache, downloads, prefs, playback logic), `:screens` (every screen, player and music), `:app` (phone/TV), `:quest` (new) | One client, three shells — the same rule the Mac follows with `LumiereKit` / `LumierePlayer` / `Lumiere`. Phone/TV behaviour must not change; the split is a pure move with green tests. |
| D3 | Release path | **Two steps.** v0.5 = the existing TV/phone UI as a 2D Horizon OS panel (`:quest` flavor, ~1 week). v1.0 = full spatial shell. | You get something watchable on the headset almost at once; every later phase is additive. |
| D4 | Input | Hands first (pinch, poke, hover-lift), controllers fully supported, gaze never required | Mirrors visionOS "look and pinch" with Quest's reliable ray + pinch; tvOS focus engine maps cleanly to ray hover. |
| D5 | Aesthetic source of truth | The Mac `Design/` folder (`Theme*`, `LiquidGlass`, `TVLift`, `GlassBackground`, `RoomTheme`) and Android `ui/Theme.kt` palette, value for value | No new palette. Spatial-only tokens (depth, glass thickness, ornament offsets) are added alongside, not instead. |

## 3. The team (roles and what each owns)

| Role | Owns | Key deliverable |
|---|---|---|
| **Product lead** | Scope, phase gates, parity matrix vs Mac/TV | §5 feature matrix, go/no-go per phase |
| **Spatial interaction designer** (visionOS HIG + Meta Horizon OS UX) | Window placement, ornaments, hover/pinch states, comfort | Interaction spec, comfort budget (§6.4) |
| **Visual designer** (Apple Liquid Glass / tvOS) | Glass materials, typography scale in degrees not points, motion | Spatial token sheet, Figma/HTML mocks of every screen |
| **Android architect** | Module split, shared state, build | `:core` extraction with zero behaviour change |
| **Spatial SDK engineer** | Scene graph, panels, environments, passthrough, anchors | Shell, theatre, window manager |
| **Media/playback engineer** | ExoPlayer → spatial surface, codecs, HDR, 3D/180/360 layouts, spatial audio | Player matrix (§6.3) |
| **Performance engineer** (XR) | 72/90/120 Hz frame budget, foveation, thermal, memory | Perf gates (§8), OVR Metrics dashboards |
| **Accessibility lead** | Reduce Motion, captions placement, one-handed + seated use, contrast on passthrough | A11y checklist per phase |
| **QA / test engineer** | Unit, screenshot baselines, on-device scripted runs | Test plan (§9) |
| **Critic** (independent) | Reviews every phase against this plan | Phase sign-off notes |

## 4. Architecture

```
server/ (unchanged, Jellyfin-compatible routes, change feed)
   │  HTTP + change feed, discovery on LAN
android/
 ├─ :core      api/ cache/ downloads/ Prefs Room Device AppBuild     (no screens)       ✅ done
 ├─ :screens   ui/ tv/ player/ music/ remote/ widget/ AppState …     (every screen)     ✅ done
 ├─ :app       manifest + Application; flavors standard + quest (2D)
 └─ :quest     Spatial SDK app (Phase 2, started) — LumiereSpace hosts :screens' MainActivity as a curved panel
      ├─ shell/       SpatialActivity, window manager, ornaments, environment switcher
      ├─ panels/      Compose panels hosting :screens
      ├─ theatre/     environments (glTF), screen entity, dimming, light spill
      ├─ player/      ExoPlayer → Spatial video panel, stereo/projection layouts
      └─ input/       hover-lift, pinch-drag, controller mapping, scrub gestures
```

- **State:** `AppState`, `Room`, change feed, outbox are shared from `:core`, so watched state, favourites and the Private Room behave exactly as on phone/TV.
- **Discovery/sign-in:** reuse `api/Discovery.kt` and `SignInScreen`/`SetupScreen` as panels. QR sign-in from the Mac app is a later nice-to-have.
- **Private Room:** Android `USE_BIOMETRIC` isn't available on Quest, so it unlocks with **Lumiere's own PIN**. ✅ Done, with these changes from the original sketch:
  - It's the app's existing device PIN (already used by the projector), not a third secret.
  - It's four digits, on the existing pad. 4–6 digits can follow if wanted.
  - It's stored on every device as a salted PBKDF2 hash, not as digits. A PIN saved by an earlier version is sealed the first time it's read. It never leaves the device.
  - After 5 wrong PINs in a row the pad waits 30 s, doubling each time. The count survives a restart.
  - On a Quest with no PIN yet, opening the room asks you to choose one.
  - The room closes on leaving the app, as on other devices, following Settings › Lock after. Whether taking the headset off counts as leaving still has to be checked on the device.
  - Forgetting the PIN: Settings is behind it too, so for now the way out is clearing the app's data. A recovery path (for example, signing in to the server again) is an open item.
- **Constraints carried over:** files under 300 lines; check scripts must stay green; `android/` tests run for `:core` unchanged.

## 5. Experience design (Apple aesthetic, in space)

### 5.1 Spaces
1. **Room mode (default, passthrough):** a single glass **main window** (~1.6 m wide at 1.8 m, curved slightly) with the tvOS-style floating sidebar as a left **ornament** (Home, Search, Libraries, Settings). Detail pages open in the same window; the player can detach into its own window.
2. **Theatre mode:** choose an environment — *Lumiere Cinema* (dark auditorium, warm gold accent lights from the palette), *Night Room* (dim apartment), *Void* (pure black). Screen size Small/Medium/Large/IMAX, distance and height adjustable; the world dims to 10% on play, light from the film spills onto the environment (sampled ambient colour, like `Ambient.colour` today).
3. **Immersive playback:** 180°/360° and 3D SBS/OU titles open in the matching projection automatically.

### 5.2 Visual language
- **Glass:** the Mac `LiquidGlass` recipe — translucent fill (Palette.surface @ 0.72), 1 px light edge (white @ 0.08–0.14), real blur of passthrough/environment behind panels (Spatial SDK panel compositor layer), specular rim that brightens on hover.
- **Depth, not shadow:** hovered cards lift 12–20 mm toward the user (the `TVLift` motion, translated to Z) with a parallax tilt of ≤4°.
- **Type in angular size:** body ≥ 0.9° visual angle (≈ 22–24 dp at panel density); titles follow the Mac scale. SF-like geometry via the existing font stack.
- **Colour:** Palette from `ui/Theme.kt`; Private Room keeps `RoomTheme.map` greying, plus covers blurred.
- **Motion:** spring curves matched to Mac/TV; Reduce Motion removes parallax, lifts, environment transitions.
- **Spotlight:** full-bleed hero art becomes a curved, wider-than-window backdrop that bleeds softly past the window edges — the Vision Pro "Apple TV" hero.

### 5.3 Screen parity
| Screen | Source to reuse | Spatial changes |
|---|---|---|
| Home (Spotlight, Up Next, shelves) | `TvHome`, `Featured`, `Cards` | Curved shelves, Z-lift hover |
| Library / grid / folders / genre | `TvLibrary*`, `TvFolders`, `TvGenre` | Alphabet rail as ornament |
| Detail (film/series/person) | `TvDetail`, `TvPerson` | Backdrop extends behind window |
| Search | `TvSearch` | System keyboard + voice dictation |
| Music + lyrics | `music/`, `TvNowPlaying` | Mini-player window that stays when you leave |
| Settings / Your Setup / Diagnostics | `TvSettings`, `YourSetup` | Separate small window |
| Player | `player/*` | §6.3 |
| First-run guide / sign-in | `SetupScreen`, `SignInScreen` | Unchanged panels |
| Downloads / offline | `downloads/`, `Offline` | Must work on plane mode — headset as travel cinema |

## 6. Engineering detail

### 6.1 Phase 1 — module split (no user-visible change, before the spatial shell)
- Create `:core` and `:screens`; move files with `git mv`. (`TvLook.on` → `Look.mode` moves to Phase 2, where the spatial look needs it.)
- **Done (2026-10-07).** Rather than untangle `ui/` ↔ `tv/`, the screens moved together into one `:screens` library, which is all a Quest shell needs. The design-system-only split (`:ui-shared`) is dropped as unnecessary.
- `:app` keeps only `MainActivity`, its manifest and the launcher art. Shared code reads the build through `AppBuild` (set in `onCreate`) and opens the activity through `Launch.intent`.
- Verified: both flavors build in release, and all 11 tests pass across `:core`, `:screens` and `:app`. The release APKs' manifests, resource tables and file lists are identical to the pre-split build.
- Needs a real Gradle build: `dl.google.com` must be allowed in the session's network policy so the Android SDK can be installed.
- Gate: unit tests green for both flavors, phone + TV behaviourally identical, existing tests untouched.

### 6.2 Phase 0 — 2D panel app (v0.5) — done as a `quest` flavor
- A `quest` product flavor of `:app` (id `app.lumiere.android.quest`), which forces the TV layout. Its manifest overlay sets `com.oculus.supportedDevices=quest3|quest3s`, landscape, a 1280×800 dp default window, no VR category (it's a 2D app), and drops the install-packages permission.
- The in-app updater is off: the Mac publishes the phone build only. The Quest build is installed with `adb install -r`.
- Controller ray = d-pad focus (TV focus code already handles it); hands work as touch.
- Gate: browse, play (direct play + transcoding fallback), resume, watched sync, downloads.

### 6.3 Phase 3 — Player (the heart)
| Need | Approach |
|---|---|
| Decode | Media3 ExoPlayer (shared from `:core`); Quest 3 XR2 Gen 2 HW decode: H.264, HEVC 10-bit, VP9, AV1 — verify each on device |
| Surface | ExoPlayer → Spatial SDK video panel (`SurfaceTexture`/compositor layer, not a Compose texture) for sharpness and no double sampling |
| 3D | Stereo layouts SBS / half-SBS / OU from filename tags first (`.3D.SBS.`, `HSBS`, `HOU`); later a server field (Jellyfin `Video3DFormat`, populated from ffprobe `stereo3d` side data) — see §7 |
| 180/360 | Equirect & 180 projection meshes; auto from filename / metadata, manual override in the info panel |
| HDR | Quest 3 panel is SDR: tone-map HDR10/HLG in shader; Dolby Vision profile 5 → server transcode fallback (`Compatibility.kt`) |
| Subtitles | ASS via `ass-media` (already used) rendered into a separate panel layer *in front* of the screen at comfortable depth; never in-video for 3D (depth conflict) |
| Controls | tvOS-style transport as a glass ornament under the screen; appears on hover/pinch, hides after 3 s; trickplay thumbnails while scrubbing; skip intro/recap, Up Next, chapters — all reused from `player/` |
| Gestures | Pinch-drag on the bar to scrub; controller thumbstick ±10 s; double-pinch to play/pause |
| Audio | Stereo → head-locked by default; optional “screen-anchored” spatial audio (Spatial SDK audio source at screen) for theatre mode; 5.1/7.1 downmix |
| PiP equivalent | Detach player into a free window while browsing |

### 6.4 Comfort & placement rules
- Windows spawn 1.5–2.0 m away, top edge at eye level −10°; recenter on long-press Meta button.
- Never head-lock content except captions in immersive 360.
- Theatre screen distance ≥ 3 m; no camera motion is ever applied to the user.
- Seated, standing and lying-down (screen tilts to ceiling) presets.

### 6.5 Performance budget
- 90 Hz in menus, 72/90 Hz matched to content frame rate in playback (24p → 72 Hz removes judder).
- Fixed foveated rendering High in theatre, Medium in menus; artwork via existing `Device.artWidth` + Coil cache, capped to keep app < 1.5 GB RSS.
- Perf gate: no frame drops in OVR Metrics over a 2-hour 4K HEVC film; headset surface < 42 °C.

## 7. Server impact
- **v1: none.** Everything works with today's routes.
- **v1.1 (optional, benefits every client):** expose `Video3DFormat` and a projection field on items, filled by the scanner from ffprobe side data and filename tags. Mac and Android would gain a “3D” badge for free.

## 8. Phases and gates

| Phase | Scope | Exit gate (Critic signs off) |
|---|---|---|
| 0 | 2D panel app on Quest (v0.5), as a build flavor | Watch a film end to end on headset; sync verified |
| 1 | Module split | All existing checks green; no behaviour change |
| 2 | Spatial shell: glass window, sidebar ornament, hover-lift, settings window, Private Room unlock. **Built, awaiting the headset:**
  - the curved, movable window in passthrough
  - the glass sidebar ornament (tabs plus the room), carried with the window
  - pointing focuses cards and buttons, so they get the TV's lift, ring and shine
  - the room PIN

  Two changes to the original scope:
  - The main window stays opaque Lumiere ground. Glass is for chrome, as in visionOS's own TV app.
  - Settings opens in the main window, not a window of its own. A second window would mean a second copy of the app's state. | Design review vs mocks; a11y pass |
| 3 | Player: spatial surface, transport ornament, subtitles layer, theatre environments, 24p→72 Hz | Codec matrix passes; 2-h perf run clean | **Cinema mode started:** passthrough dims to 12% while playing (45% paused) with a faint spill of the film's colour, and the window grows 1.35× with the sidebar hidden (`quest/spatial/Cinema.kt`).
| 4 | 3D + 180/360 (all in scope), spatial audio, downloads offline. **3D SBS/OU started early:** the existing player asks Horizon OS to split its surface per eye (`metavr.view.SurfaceViewExt`, learnt from DeadEasy Player, MIT), with layout from title tags and the picture framed at one eye's shape. | Sample library of each format plays correctly |
| 5 | Polish: motion tuning, environment art, onboarding tour (`TvTour` analogue), icons/banner | Final critic review; release build |

## 9. Testing
- `:core` keeps all JVM unit tests; add tests for stereo/projection detection and refresh-rate selection.
- Screenshot baselines for spatial panels (Paparazzi/Compose) like the Mac `Tests/Baselines/`.
- On-device scripted runs via `adb` + Spatial SDK test hooks: launch, browse, play, seek, Up Next, offline.
- Codec/format matrix spreadsheet signed per release.

## 10. Risks
| Risk | Mitigation |
|---|---|
| Spatial SDK API churn | Pin version; wrap SDK calls in `:quest/shell` only |
| No passthrough blur on some panel types → glass looks flat | Fallback “frost” = translucency + light edge, exactly as `Frosted.kt` does on Android 11 |
| HDR/Dolby Vision quality on SDR panel | Tone-map + server transcode fallback; label honestly in info panel |
| Module split breaks phone/TV | Phase 0 is a pure move behind green tests, merged on its own |
| Biometric lock unavailable | Lumiere PIN (§4) |

## 11. Answers (2026-10-07)
1. **Engine and release path:** approved. Meta Spatial SDK, with a 2D panel app (v0.5) first.
2. **Private Room unlock:** a separate Lumiere PIN (see §4).
3. **3D, 180° and 360° files:** yes, all three. Phase 4 is fully in scope, and test files of each format go into the codec matrix (§9).
4. **Users:** single-user only. No co-watching or second-user mode is planned.

## 12. Headset lessons (2026-10-10)
Learnt on the Quest 3S, and kept as tests where a test can hold them:
- **Built-in meshes need their shape component.** A `mesh://box` without a `Box` makes the SDK's mesh system throw on the next frame, outside any guard, and the app stops. This crashed every start until the cinema's floor and stage got one (`MeshShapesTest`).
- **Never `Scale` a panel.** On the headset a scaled cylinder panel looked no bigger, while the pointer aimed as if it were: dead buttons, a cinema that couldn't be worked. Sizes are now real: `PanelSceneObject.reshape` gives the panel its width, height and curve in metres, then the Transform is written again so ISDK re-reads them (`Cinema.resize`, `Cinema.settle`). Flat is a 60 m curve, on the same proven path.
- **A hidden panel is also parked out of reach**, in case it still catches the pointer.
- **Crashes leave a report** in Downloads › Lumiere on the headset (`CrashLog`), readable from the Files app or SideQuest without a Terminal. After two failed starts in a row, the next one opens with just the window and sidebar (`StartGuard`).
- **The ornament** is one glass strip under the screen, as on visionOS: Up Next in the credits, the film's frames while scrubbing, the song and its sung line while music plays (`Floating`).
- **Sound from the screen** (`ScreenAudio`, `ScreenSound`): a Media3 audio processor leans the soundtrack toward the screen's direction in your head's frame, every frame; 5.1/7.1 are folded to two ears. Identity when facing the screen; never above unity gain.
- **180° and 360°** (`Surround`, `SurroundSphere`): explicit tags (VR180, 360°, 180x180) or a bare 180/360 beside an eye tag or on an equirect-shaped picture; a film merely called "360" stays flat. The player's video goes to a `VideoSurfacePanelRegistration` sphere with the film's stereo mode, made only while it plays.
- **Poster wall** (`PosterWall`): the library as a 155° curved wall, three posters high, loaded as they come into view and filtered by the Private Room like everywhere else. While it is up every controller and gesture key is the wall's, so nothing reaches the hidden window (`Remote.deliver`).

## 13. Spatial-first redesign (2026-10-10)
The headset verdict: sizes, curve and anchor felt stuck; the cinema screen too small with no environment; the sidebar fixed in place; poster covers blank and the wall too low; holding the Meta button didn't bring things back. Root cause: Lumiere on Quest was a TV screen in a box. Spatial features were bolted on as sidebar buttons, and the film was trapped inside the TV interface's window. The redesign keeps the TV app as the browsing window and builds everything spatial on Quest-native mechanics.

**Principles**
1. Native mechanics before buttons: Horizon OS grab bars, corner resize, Meta-button recentre, ray and pinch. Nothing you can grab gets a size button.
2. The picture leaves the window: films play on their own screen, a video layer that is sharp at any size, curved or flat, true 3D, shaped to the film.
3. Places, not modes: Room (your room, dimmed), Cinema (a lit theatre that takes the film's light), Void (black, for OLED-like contrast).
4. Controls come to you: a transport bar near your hands that appears when you need it, and captions placed for reading. The tab bar is yours to move.
5. Comfort and performance are budgets: screens near the eye line, nothing head-locked, a few draw calls per environment, and no per-frame work that isn't needed.

**By facet**
| Facet | Now | Redesign |
|---|---|---|
| Recentre | Ignored | `onRecenter`: window, tab bar, screen and controls come back in front of you; in the cinema, you're re-seated |
| Browse window | Curved, size buttons, Scale/reshape that didn't show | Flat Horizon window: ISDK grab bar and corner resize (`IsdkPanelResize`, Relayout: the content reflows at the same text size) |
| Tab bar | Glued to the window's edge | Its own panel with a grab bar; starts beside the window; recentre docks it again |
| Anchor | A lock that felt stuck | Gone: windows stay where you put them, as on Horizon OS |
| Watching | The film inside the TV interface's window | The Theater: a video panel (`VideoSurfacePanelRegistration`, quad or cylinder) sized from the film's own shape; 3D via the panel's stereo mode; 180°/360° on the same path |
| Transport | The TV interface's overlay, in the window | A floating bar under your gaze: play/pause, ±10 s, scrubber, screen size, curve, place, exit. Auto-hides; any button or pinch brings it back |
| Captions | In the window's subtitle view | Their own panel in front of the screen, from the player's cues (libass gives way to Media3's own SSA parser in the Theater) |
| Screen size | Presets that didn't render | Five sizes by angle (40°–90°), applied by remaking the video panel at its real size, the one path proven on the headset |
| Environments | An unlit near-black void | Room (passthrough, dimmed); Cinema (walls, raked rows of seats, stage, aisle lights, lit by the scene's lighting, which takes the film's colour); Void |
| Poster wall | Blank covers, too low | The app's signed-in image loader is shared with every panel; the wall is raised to just above your eyes |
| Sound | Steered toward the window | Steered toward the Theater screen |

**Phases**
- **A1 (done, 542c8bf):** recentre; flat window with grab bar and corner resize; free tab bar; anchor and size buttons removed; poster wall images and height.
- **A2 (done):** the Theater: video screen, transport, captions, environments, film light, sizes by angle, curve. Also: every panel faces you wherever you carry it (FACE); the Theater's screen can be carried in your room and the dark; floating panels have near-opaque glass (the screen showed through the tab bar like a reflection); the Private Room explains itself when empty.
- **Lesson:** `Scale` never rendered on this headset, for panels or meshes. The old cinema's floor stayed a 1 m cube you sat inside, so there was no environment. Every box is now built at its real size (`Box` corners), and every panel is made at its real size.
- **B (next):** browsing beyond the TV: an ambient backdrop of the focused title behind the window; hand scrubbing (pinch and drag); a wrist menu; an album wall in the music room; environment art from a generated glTF; a first-run tour of the gestures.

## 14. Phase C: Bigscreen-class watching (2026-10-10)
The headset verdict after A2: it opens now, but the cinema screen is still too small. The bar is Apple TV, Netflix and Bigscreen; NEX Player was named as a reference for environments.

**Why the screen was small.** Sizes ran from 40° to 92° across, the default was 64°, and the cinema's screen stood at a fixed distance. Bigscreen's screens fill 80–110° of your view.

**What changed**
| Facet | Before | Now |
|---|---|---|
| Screen size | 40–92°, default 64° | 55 / 70 / **85** / 100 / 115°; older saved sizes are moved to the new default |
| Cinema | A screen at a set distance | One IMAX wall, 24 m across; a size is how near you sit (13 m away at 85°, 7.6 m at 115°) |
| Hall | A fixed rake; the parapet could hide the screen's foot | The rake is chosen from your sightline (0.25–0.6); a seat too close becomes a front balcony; the parapet is kept under the sightline (tested) |
| Places | Room, Cinema, Void | + **Space**: a starfield all round you (`mesh://skybox`, a 4096×2048 Milky Way from `Scripts/starfield.py`) |
| Browsing away from your room | The window over a dark screen | The **marquee**: the big screen shows the title you're on (backdrop, logo, facts), crossfading as you move (`ui.Marquee`, `MarqueeScreen`) |
| Film light | The title's average colour | The picture's colour now, sampled every 2 s from its trickplay tile; the title's colour until the first tile arrives |
| Transport | Play, ±10 s, scrubber, a few buttons | Title, time and scrubber with frame previews; Next episode; a **Subtitles & Audio** sheet; size, curve, place, window, close; 52–60 dp targets |
| Skip intro / credits | Hidden in the Theater (it was drawn in the hidden window) | A pill over the transport (Floating) |
| Pointer | Hovering switched tabs and scrolled the page | Pointing only looks; pressing chooses; the page never scrolls under the ray (`Pointing`, `CalmScroll`) |
| Targets | 36–40 dp buttons and chips | At least 52 dp on Quest (icons 56 dp), per Horizon OS's 48 dp minimum |
| Overlays | Closed only with Back | A tap outside closes them (actions, genre/letter chooser, episode strip) |
| Home banner | Dots for show; turned while you read | Each dot is a target; the banner holds while you point at it |
| Images | No fade, 16-bit colour (TV memory budget) | Crossfade and full colour on Quest |

**NEX Player, for reference** (store pages and reviews; the app itself wasn't run). Photoreal environments (a cinema hall, a lakeside, a modern cabin, "MAX Cinema", "Voidline"); you browse and switch videos without leaving the environment; controls work at any distance, with shortcuts you can pin to the first layer. Lumiere now matches the browse-in-place part (the marquee) and adds Space. Lakeside and cabin, and pinnable shortcuts, are in Phase D.

**Phase D (next)**
- Environments: a lakeside at dusk and a modern cabin, as glTF or procedural meshes with baked light, and the film's light on them.
- Pinnable transport shortcuts (NEX's first layer): choose which 4–6 buttons are always there.
- Netflix and Apple TV parity: a search field with voice; remove from Up Next; My List; trailers in the banner after a few seconds (no spoiler previews); loading skeletons; profiles.
- Close (×) buttons on every overlay, alongside tap-outside and Back.

## 15. Phase D (2026-10-11)
Built as eight features on their own branches, merged, then the whole build and tests run together (182 tests). Trailers were left out at the owner's request; the spotlight's preview is unchanged.

| Feature | What changed |
|---|---|
| Lakeside | A sixth place: a 360° mountain lake at blue hour (`Scripts/lakeside.py`, a ray-marched terrain, deterministic), a timber pontoon under you that stops short of your sightline, the screen floating 14 m out over the water |
| Cabin | A seventh place: a modern timber room built round a 5.5 m wall screen (a size is how near you sit), window bays onto the lake, beams, a fireplace, a sofa behind you; its floor steps down so the film's foot is never hidden |
| Window and marquee | Away from your room the window sits low and tipped back, under the big screen; a film starting there never flashes the window over the screen (TheaterHold) |
| Private Room | Empty, it lists your libraries to choose from; ids from the Mac are matched however they're spelt |
| Shortcuts | The transport's first layer is yours: pin up to six actions (speed and sleep timer among them); everything else is in More |
| Profiles | "Who's watching?": several people on one device, each with their own My List, recents and Not Interested; the picker appears only once two or more are saved |
| My List and Up Next | My List on title pages, Home and the actions panel (the server's favourites); titles come off Continue Watching and Up Next, with undo |
| Search | A real field on the Quest (Horizon's keyboard dictates), a compact remote keyboard on TV, Speak where a recogniser exists, recent searches |
| Skeletons | Home's first load, the library grid and a title's page come in outline with a soft sheen |
| Pointer polish | × on Quest overlays; the window's controls stay up under the ray; phone drags off on Quest; a pinchable Undo; cast faces ring; a Quest-specific first-run tour |

**Headset checks:** the lakeside sky's orientation (the calm water should be behind the screen; turn the skybox if not), the cabin at 115° (the poster wall sits behind the front wall at that size), voice dictation in the Quest's search field.

**Next:** trailers (when wanted, with a LocalTrailers route on the Lumiere server), snow on the lakeside's peaks if wanted, the poster wall in the cabin at the largest size.

## 16. Phase E1: places that feel lived in (2026-10-11)
| Place | Added |
|---|---|
| All | Real surfaces from `Scripts/textures.py` (14 seamless textures: oak boards, timber, weathered deck, fabric, velvet, carpet, a wool rug, stone, book spines, two pictures), tinted by the existing light model so dimming and the film's colour still work. Each texture loads once (the SDK caches by resource). |
| Cabin | A wall of books behind you (three bays, a vase, a photo, a plant), side tables (a mug, a candle, books), cushions and a knitted throw, a tall plant, pictures over the shelves and the mantel, logs in the fire with flickering flames and embers, a woodpile, candles on the mantel, floor-standing speakers beside the screen, pendant lights, a coffee table where the sightline allows |
| Lakeside | Two chairs and a crate (mugs, a jar candle) behind you, a rod and tackle box, a cool box, rope, a rowing boat tied alongside, string lights, flames in the lanterns, fireflies drifting over the water |
| Cinema | Seats as individual seats with armrests (texture), patterned carpet, cloth walls and acoustic panels, velvet curtains drawn back under a valance, sconces that dim for the film, the projection booth's windows behind you |
| Sound | Each place's own sound, synthesised live and placed where its source is: the fire's crackle from the fireplace, water lapping and crickets round the pontoon, a hall's hush, a deep drone in space. Fades out when a film plays, back when you pause; "Sounds of the place" on the tab bar and under More |

Motion runs every frame (Animator → Director.animate → Scenery.animate) from pure, tested functions (Life); nothing moves with Reduce Motion on.

## 17. Proposals (for the owner to choose)
See the reply of 2026-10-11; recorded here so the list survives.
1. Wall-mounted screen in your room, from Space Setup (MRUK): snaps flush to a real wall, remembered by the wall's anchor.
2. New places: the Moon (Earthrise), a space station's observation deck, above the clouds, plus a drive-in, an Art Deco picture palace, a rooftop over a city at night, a winter cabin with snowfall, under the sea.
3. Places that change: time of day and weather (the lake at dawn, rain on the cabin glass, snow), slowly moving cloud and star layers.
4. Curtains that open as the film starts and close at the credits; house lights that fade at the cinema's own pace; an optional pre-show.
5. Ambilight-style light from the picture's left and right halves onto the matching walls, refreshed faster.
6. Your library on the walls: framed posters of your favourites in the cabin and the cinema's lobby.
7. A hand menu: turn your palm up for play/pause, volume and the place, without reaching for a panel.
8. Choose your seat in the cinema (front, middle, balcony) instead of size steps.
9. Spatial captions: follow your gaze comfortably, size and depth options, two languages at once.
10. Truer film sound: head-tracked spatial audio (HRTF) from the screen and surround channels placed round you.
11. Picture: per-film brightness and black level, sharpening, a "fill the IMAX wall" zoom for 2.39:1 films.
12. Depth in the browse window: posters with parallax layers, as Apple TV's cards tilt.
13. Comfort: recentre automatically when you sit or stand, a seated or standing height calibration, a "lie back" mode that tilts the whole place.
14. Watch together with friends' avatars in the same place (larger; later).
15. (Owner, 2026-10-11) A small, handy controller away from your room: a compact panel and tab bar near your hands for choosing what plays on the place's big screen, instead of shrinking the home window — shrinking it leaves it small and the tab bar misaligned when you go back to your room (the tab bar docks by the window's default width, Docking.beside, not its size now).
16. (Owner, 2026-10-11) Realistic detail in every place, the cinema above all: real shapes (seats with backs, arms and cup holders, a proscenium, stepped aisles with lights, acoustic panels, speakers, the projection booth's window and beam, exit signs), not plain boxes.

## 18. Batch 1 of the proposals (2026-10-11)
**The screen on your wall.** In your room, "Screen on the wall before you" (under More on the transport, pinnable) reads your Space Setup through Meta's Mixed Reality Utility Kit (`meta-spatial-sdk-mruk`, the `com.oculus.permission.USE_SCENE` permission asked for only then; with no Space Setup the headset offers to run it). The wall your gaze meets takes the screen: flush, 3 cm proud, square and upright, your size from where you stood but never past the wall's edges, its middle at least a TV's height (WallMount, tested). The wall's own id, where on it and your distance are saved (Stage.mount), so every film in your room plays there until you take it off; a wall Space Setup no longer has, or a refused permission, leaves the screen floating as before. MRUK is left out of a plain start (StartGuard.peek), so a failure there can't stop the app.

**Three places.**
| Place | Sky | Around you | Sound |
|---|---|---|---|
| Above the clouds | A cumulus sea at golden hour (`Scripts/clouds.py`) | A teak terrace: rails, two loungers and a low table with drinks behind you, olive trees in planters, lanterns; the deck stops short of your sightline; screen 16 m out, 0.9 m over your eyes | Wind in long gusts |
| The Moon | Lunar highlands, the Earth over the horizon (`Scripts/moon.py`) | A lunar base's tread-plate deck on legs: safety rails, cases, oxygen bottles, a toolbox, work lights, a mast with a dish and a blinking beacon; screen 18 m out on the surface | A suit's quiet hum, a radio click now and then |
| The space station | The Earth from 400 km, its limb, night side and city lights (`Scripts/orbit.py`) | An observation module round a 4 m wall screen: hull panels, windows down both sides, one in the floor and a skylight, handrails, light strips, lockers and the hatch, blinking panel lights, a grow box, a laptop on its arm, things drifting free | Fans, a hum, a soft chime |

Tests: WallMountTest; NewPlacesTest (no part of any new place hides the screen at any size, film shape or eye height; every box has a size; tall things beside you or behind; each has a sky and a sound).

## 19. Batch 2 of the proposals, in three parts (2026-10-11)
Each part ends in its own APK. Proposals 15 and 16 come from the owner's own use, so they lead.
- **2a, the controls and the cinema:** the compact controller away from your room (15) and the tab bar docked by the window's real size; the cinema made real (16): modelled seats, proscenium, stepped aisles, acoustic walls, booth and beam; its ritual (4): curtains that open as the film starts and close at its end, house lights at the cinema's own slower pace; choosing your seat (8); light from the picture's left and right halves on the matching walls (5).
- **2b, comfort and picture:** the hand menu (7); recentring when you sit or stand, and lying back (13); picture controls and wider scope films (11); captions you can size and set nearer (9); posters with depth in the browse window (12).
- **2c, more places:** a drive-in, an Art Deco picture palace, a rooftop over a city at night, a winter cabin with falling snow, under the sea (2); skies that change with the time of day and the weather (3); your library's posters on the walls (6); film sound placed round you (10).
- Watch together (14) stays for later.

The APK is over 30 MB now (the Spatial SDK's runtime alone is 18.6 MB compressed, MRUK added 2.9 MB), so it's sent in two parts to join before SideQuest.

## 20. Batch 2a, the controls and the cinema (2026-10-11)
**The handset (proposal 15).** Away from your room a small pane comes near your hands (0.66 m across, 0.78 m away, under the big screen's line of sight; it can be carried): a shelf of posters at a time — Continue, Next Up, My List, what's new in each library — where touching a title fills the big screen and touching it again (or Play) plays it there; Resume, Start over, Episodes (seasons and episodes in the same shelf), My List. Its rail: every place one touch away (with your seat in the cinema, the screen's size elsewhere), search and everything else (the whole window comes for those, and the tab bar's handset button takes it away again), the place's sounds, the poster wall, bring everything here. The window stays as you left it for your room. A film starting or another place puts the window away; signing in, choosing who's watching, a PIN or a report always bring it. If a film asked for from the handset hasn't appeared in six seconds, the window comes to say why. The tab bar now docks by the window's real width (IsdkPanelDimensions / PanelDimensions), not its starting width.

**Why the places looked flat, and the fix.** The SDK reads a Material's base colour only when it makes a mesh, and ignores it once there's a texture: the textured walls, seats and floors showed their light-grey textures, and nothing dimmed for a film. Now each place is modelled (Model.kt's Modeller) and made through our own mesh creator (ModelMeshes, `mesh://lumiere?id=N`, registered in LumiereSpace.onSceneReady), each mesh's material relit by `setAlbedoColor` in full precision (linear; a plain part's first colour kept as the fallback). Faces are shaded by the way they look (Facing): in the cinema five ways, so the backs of the seats before you stand dark against the picture; elsewhere three. Still parts are gathered into one mesh per kind, side and facing; moving ones (flames, fireflies, the curtain) are meshes of their own.

**The cinema made real (16).** Rows of seats (velvet cushions and tilted backs on dark pans and shells, shared arms with cup holders, end standards; plainer beyond 5 m), lit step nosings, framed acoustic panels, surround speakers, sconces on brackets, beams under a ceiling of tiny stars, a gilt proscenium with fluted pilasters, drapes and a valance in folds, and a front curtain of strips that gather to the sides. About 110 meshes and at most ~110k vertices (the hall was 170 boxes). Every part is made within the bounds the sightline tests check (ModelTest).

**Its ritual (4), seats (8), ambilight (5).** The curtain draws across as you press Play, opens over five seconds as the film begins, draws again for six seconds after it ends, then opens on the next title (FrontCurtain; open whenever a film is on, and always open with less motion asked for). The hall's house lights go down over about four seconds and come up over two. In the cinema the five sizes are seats — the back row, rear stalls, the middle of the hall, front stalls, the front row — on the transport ("Sit further back / nearer the screen") and the handset. The film's light comes from the picture's left and right thirds onto the walls on your left and right, sampled every second and gliding between colours.

Left for later: holding the film until the curtain is open (a pre-show).

## 21. Batch 2b, comfort and picture (2026-10-11)
- **The hand menu (7).** Raise a hand (not a controller) into the middle of your view, near and at least shoulder high, hold it still a moment and look at it: a row of glass comes just above it — in a film back ten seconds, play/pause, forward ten; always quieter/louder (the system volume), the next place, bring everything here — for the other hand to press. It stays where it came while you use it, and goes a moment after you lower the hand (HandRaise; still and raised, so pointing at the handset or pinching doesn't call it). On or off under More (Hand menu). The trigger uses only the hand's position and your gaze, not the palm's direction, which the SDK doesn't document.
- **Comfort (13).** Sit down or stand up and, two and a half seconds later, the place and its screen come to your new height, still facing the same way (Posture: 30 cm held 2.5 s; a lean or a stretch doesn't count). On by default; More › Follow when you sit or stand. Lying back keeps its own placement (looking up).
- **Picture (11).** More › Picture: brightness and contrast in four steps either way (media3 effects), kept for the film or a whole show, on SDR films (an HDR one is shown as it came); and wide films either keep the screen's width or fill the wall as a scope cinema shows them, as tall as a 16:9 picture and so wider — a curve kept within 130°, where every place still keeps clear of the screen (every sightline test runs both ways). Sharpening isn't offered: media3 has no sharpening effect.
- **Captions (9).** Audio & Subtitles now also holds: a second language under the first (the film's other text subtitles read from the server as WebVTT, a little smaller and warm in colour); the captions' size (the window's own four sizes); and where they are — on the screen, or before you, low in your view, turning to where you face once you've looked more than 28° away for most of a second.
- **Posters with depth (12).** In the browse window, the card under a hand's or controller's pointer tips toward it, its picture shifts inside the frame as a layer behind the glass would, and a soft light follows the pointer (not with less motion asked for, nor on a low-memory device).

## 22. Batch 2c, part 1: the cinema, modelled and baked (2026-10-12)
The places' skies were good and their furniture wasn't: boxes in flat colours beside Skybox VR's lit, modelled halls. So the places are now made as a game's levels are, starting with the cinema.
- **The pipeline (Scripts/env).** Blender, run headless from Python (envkit.py): each place modelled in the app's seat frame, lit with real lights — sconces, coves, downlights, step lights, footlights — and Cycles bakes the light into a few texture atlases (soft shadows, light pooling under the lamps, the bounce off every wall), cleaned of its grain by an edge-stopping filter and exported as glTF with unlit materials. On the headset the model loads from the APK's assets and is drawn unlit (BakedPlace), so its lighting costs nothing. Each material's name says how it takes the light (BakedLight): a baked surface dims for a film and takes the picture's colour — the left wall the left half's, the right the right's; a lamp's glass goes down with the house lights; an exit sign or step light stays lit.
- **The cinema (cinema.py, CinemaHall).** One fixed stadium hall round one 20 m screen: twelve rows of thirty-three velvet seats (cushion and two-part back in a hard shell, shared padded arms with cup holders, taller row ends) stepping up 38 cm a row from a balcony front 2 m above the pit; upholstered wall panels between walnut fins, a brass sconce on each fin washing the wall up and down; a walnut wainscot and a brass handrail along the aisle stairs, a light in every step; a ceiling in three steps with a glowing cove in each and downlights over the seats; speakers high on the walls; the projection booth's windows and exits at the back; a walnut-fronted stage with footlights, a brass-moulded proscenium, velvet drapes and a pleated valance with a gold fringe; exit doors beside the stage.
- **Sizes are seats.** The five sizes are five rows of the one hall — the back row (55°), the rear stalls (70°), the middle (85°, where everyone starts), the front stalls (98°) and the front row (115°). The screen is the hall's: flat, a wide film its full width and shorter, a 4:3 one its full height; its middle sits as the hall has it, a little below your eyes from the back, about 10° up from the middle, 29° up from the front row, wherever your head is. The curve and "wider, as in a scope cinema" don't apply there and say so.
- **The front curtain** is its own baked model: velvet in forty folds with a gold fringe that drops in front of the screen as a film comes and rises out of sight behind the valance as it starts (eased at both ends).
- **Tests.** Every seat, sitting low or standing, sees the screen's whole foot over the seats in front (and the front row over the parapet); the raised curtain is out of sight from every seat; each size is within 2° of its share of your view; the baked model's numbers (cinema.json) and materials (unlit, a texture on every baked surface, the left wall on your left) agree with the app's.
- **If it doesn't load** (a missing asset, or the SDK unable to draw it) within 30 s, the cinema falls back to the modelled hall of batch 2a.
- **Next in 2c:** the cabin, the lakeside, the terrace, the Moon base and the station rebuilt the same way; then the five new places, living skies, posters on the walls and the film's sound placed round you.
