# Lumiere for Meta Quest 3 — Plan

Status: **approved 2026-10-07, no code yet.** Decisions in §2 and answers in §11 are settled; Phase 0 is next.

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
| D2 | Code layout | Split `android/` into Gradle modules: `:core` (api, models, cache, downloads, prefs, playback logic), `:ui-shared` (Compose design system), `:app` (phone/TV), `:quest` (new) | One client, three shells — the same rule the Mac follows with `LumiereKit` / `LumierePlayer` / `Lumiere`. Phone/TV behaviour must not change; the split is a pure move with green tests. |
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
 ├─ :core        api/ cache/ downloads/ Prefs Room AppState Device  (moved, untouched)
 ├─ :ui-shared   Theme Palette Cards Pill Buttons Frosted Featured… (moved; TvLook → Look.mode = Phone|Tv|Spatial)
 ├─ :app         phone + TV shell (as today)
 └─ :quest       Spatial SDK app
      ├─ shell/       SpatialActivity, window manager, ornaments, environment switcher
      ├─ panels/      Compose panels hosting :ui-shared screens
      ├─ theatre/     environments (glTF), screen entity, dimming, light spill
      ├─ player/      ExoPlayer → Spatial video panel, stereo/projection layouts
      └─ input/       hover-lift, pinch-drag, controller mapping, scrub gestures
```

- **State:** `AppState`, `Room`, change feed, outbox are shared from `:core`, so watched state, favourites and the Private Room behave exactly as on phone/TV.
- **Discovery/sign-in:** reuse `api/Discovery.kt` and `SignInScreen`/`SetupScreen` as panels. QR sign-in from the Mac app is a later nice-to-have.
- **Private Room:** Android `USE_BIOMETRIC` isn't available on Quest, so it unlocks with a **separate Lumiere PIN** (4–6 digits, entered on a glass keypad panel). The PIN is stored on the headset only as a salted hash (Android Keystore-backed key), never sent to the server; after 5 wrong tries the keypad waits 30 s, doubling each time. Leaving the room or taking the headset off locks it again.
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

### 6.1 Phase 0 — module split (no user-visible change)
- Create `:core` and `:ui-shared`; move files with `git mv`; replace `TvLook.on` checks with `Look.mode`.
- Gate: `./gradlew testDebugUnitTest` green, phone + TV APK diff behaviourally identical, existing tests untouched.

### 6.2 Phase 1 — 2D panel app (v0.5)
- `:quest` module depending on `:app`'s TV shell; manifest: `com.oculus.intent.category.VR` not set (2D), `com.oculus.supportedDevices=quest3|quest3s`, landscape, no leanback.
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
| 0 | Module split | All existing checks green; no behaviour change |
| 1 | 2D panel app on Quest (v0.5) | Watch a film end to end on headset; sync verified |
| 2 | Spatial shell: glass window, sidebar ornament, hover-lift, settings window, Private Room unlock | Design review vs mocks; a11y pass |
| 3 | Player: spatial surface, transport ornament, subtitles layer, theatre environments, 24p→72 Hz | Codec matrix passes; 2-h perf run clean |
| 4 | 3D + 180/360 (all in scope), spatial audio, downloads offline | Sample library of each format plays correctly |
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
