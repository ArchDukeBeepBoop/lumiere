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
