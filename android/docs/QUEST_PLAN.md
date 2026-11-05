# Lumiere for Quest — plan

Target: Meta Quest 3 and 3S on Horizon OS, the `quest` flavor (`app.lumiere.android.quest`, "Lumiere for Quest").
Reference: Meta's guidance for Android apps on Horizon OS — design requirements, panel sizing, making apps compatible — and the Spatial SDK docs for anything immersive (links in section 10).
Scope: the Quest app. Shared code it changes is called out so the phone and TV sessions know; the TV app is not touched.
Status: step 1 done (2026-10-27). **Changed on 2026-10-27: the spatial app is being merged in first** (section 0), and steps 2–8 follow on the merged app.

---

## 0. The merge (2026-10-27): one Quest app

There were two Quest apps:
- the `quest` flavor here, which is the phone's layout in a window;
- the cloud session's Spatial SDK app, `app.lumiere.android.spatial`, on `ArchDukeBeepBoop/lumiere` branch `claude/blissful-goodall-k71k9o`. It has a room, a Theater, 360° places, room walls, a handset and Diagnostics, and its handover is `docs/quest/HANDOVER.md` there.

The user chose to merge them. The merged app is this repo's `quest` flavor, with the spatial work brought into it.

- **Where the code goes.**
  - Spatial-only code goes in `app/src/quest/` (activity, panels, Director, places, room walls).
  - The Spatial SDK is a `questImplementation` dependency.
  - The quest flavor alone is minSdk 34 and arm64-only, so the phone and TV builds don't change.
- **Switches the shared screens read** (`Theater.enabled`, `Floating.enabled` …) live in `app/src/main`, default off. Only the Quest's activity turns them on, so the phone and TV behave exactly as before. Each hook in a shared screen is one guarded line, reported to the TV and phone sessions.
- **Layout:** the Quest's window shows the **TV layout**, as the spatial app did: big targets, and a focus the controller ray moves.
- **Not merged:** the branch's own `core`/`screens` copies of shared code. They date from 2026-10-06, and the local code is newer.
- **App id:** `app.lumiere.android.quest`. The spatial install is removed once, as decided in section 11.

Stages, each a build the headset installs and checks:
- **M1, the shell:** the room in passthrough, the window (`MainActivity` as a panel), its sidebar, controllers mapped to keys and scrolling, Quit, StartGuard, Breadcrumbs, the crash log, SelfTest and Diagnostics, and self-update.
- **M2:** the Theater (a film on its own screen, captions and transport near the hands, sound from the screen).
- **M3:** places (360° pictures, lights-down, the far screen). **One seat per place: the back row** (the user's choice, 2026-10-27), so only `pano_<place>_s0` comes over for the cinema, cabin and station, plus the single pictures of the lake, clouds and moon. That's a fraction of the 46 MB. Screen size no longer changes the seat. **Exactly one sky at a time:** the spatial app kept a hidden skybox per picture, and a second one turned every sky white in the headset, the middle row included. The merged app removes the old sky before it makes the new one.
- **M4:** the handset, wall mount (MRUK), hand menu, Marquee and poster wall.
  - **Wall mount, from the first try (2026-10-28).** The screen didn't sit flat on the wall: "the angles are all wrong". And Hang on Your Wall, inside the player's More menu, wasn't found ("there is no button for it").
    - It gets its own button: on the transport, and later on the handset.
    - Before it ships again, log the wall's pose, Space Setup's plane axes and the screen's computed pose in the headset, and compare them with what's seen. The suspects are `RoomWalls.worldPose` (the parent chain) and `WallMount.pose`'s facing.
    - Until then it's switched off (`TheaterStage.WALL_MOUNT`), and a mount already saved is ignored.
- **Screen size (done 2026-10-28):** 35°–85° of your view, starting at 45° (85° was too big), in the player's More menu and remembered.

Then steps 2–8 below, applied to the merged app.

### 0b. The complete app (2026-11-02): direction and tools

**Direction:** NEX 3D Video Player and Apple TV, as the user named them.
- **From NEX:** play anything from your own library, in true 3D (side-by-side and over-under), 180° and 360°, with a handful of polished environments and deep playback settings.
- **From Apple TV:** cinematic browsing, environments that feel like places rather than backdrops, and calm, legible controls.
- **What not to copy:** Pluto TV's lesson, that the place must never outshine the film.

**Tools (the user's decision):**
- **The app stays this one:** Meta Spatial SDK, sharing code with the phone and TV.
- **Blender** (4.5 LTS, headless) builds the environments as scripts in `Scripts/env/`: 360° pictures from the seat, lit and lights-down.
- **Unity** (2022.3 LTS, Android build support) is for what needs a real-time engine: baking light, previewing a scene at true scale, and glTF export if baked 3D rooms are tried again (HANDOVER §3.1: their textures arrived white).
- **Hermes** (Solar Mini 4, free) does reviewed side work: research summaries, first drafts of Blender scripts, test cases and docs. Nothing it writes lands without review and the gate.

**Phases**, each a headset build:
- **C1, the environment pipeline:** the spatial app's Blender scripts brought here and rendering under Blender 4.5; real lights-down pictures for the cinema, cabin and station from the back row.
- **C2, 3D and immersive playback (NEX):** side-by-side and over-under detected (by frame shape, by name, or by your choice per title) and played in stereo; 180° and 360° on a half or whole sphere.
- **C3, Apple TV polish:**
  - a visual environment picker;
  - the place and the title you're on shown while browsing (Marquee);
  - light that follows the film's colour;
  - the wall mount back with its own button.
- **C4:** the deferred plan steps 2, 4 and 6, then the signing key (step 7), with you present.
- **C5, the Quest's own face (decided 2026-11-02):** the user found the app still the TV's, placed in a room. Their choices:
  - **Home: a curved shelf.** A wide, gently curved glass panel of poster rows round you, with a slim tab strip at its side (Home, Movies, Shows, Search, Places). The TV's screens stay only for deep pages such as Settings.
  - **Controls: a bar under the film.** No handheld window during a film. A slim glass bar low before you (FilmBar): play, ten seconds either way, the scrubber, Audio, Subtitles, Places, More, and the wall. It comes up with any button or pinch and fades. Menus open in the window just above it. (First step landed: FilmBar.)
  - **Places: on the film's bar, and a tab on home.** Browsing happens inside a place too, not only films.

The newest spatial build (`79dc793`, five seat pictures per room) crashed at start. Its code change was only to the self-test, so the cause isn't visible from the source. The merged build's Breadcrumbs and crash log will name it if it recurs.

---

## 1. The goal in one sentence

In the headset, Lumiere is a comfortable, legible panel. It is pointed at with a controller or a pinch rather than touched, and it has everything the Mac and the phone gained this month. Being in VR is used only where it earns its place: a bigger screen in a quiet room, never motion for its own sake.

## 2. The roles behind this plan

Each step is written and checked from these points of view.

| Role | Owns | Sign-off question |
|---|---|---|
| **Horizon OS interaction designer** | Pointer, pinch and hover; target sizes; the panel's size and resizing | Can it be used one-handed with hand tracking, without a missed pinch? |
| **Visual designer** | Type sizes, contrast, the Quest palette, the prism theme | Is every line readable at arm's length, and is nothing pure black or pure white? |
| **Comfort reviewer** | Motion, brightness, anything that moves the page under the eye | Does anything drift, parallax or flash that the user did not ask for? |
| **Playback engineer** | Media3, codec probing, the music player, reporting | Does any change cost frames, memory, or a play report? |
| **Build and release engineer** | Flavors, the gate, dependencies, signing, the update channel | Is the build reproducible, tested per flavor, and updatable without a cable? |
| **QA in the headset** | The checks in section 9, run by you on the real Quest | Does it behave the same after an hour in the headset as in the first minute? |

---

## 3. Where the Quest app is today

Measured in the code on 2026-10-27, not assumed.

- **What makes it the Quest's:** `app/src/quest/AndroidManifest.xml` (landscape, the device-media permissions) and `Flavor.quest`. No Kotlin code branches on it. In practice it is the **phone app in a wide window**: `LocalFormFactor.isTv` is false, so it gets `PhoneHome`, `PhoneMusicScreen`, the phone player (`PhoneChrome`) and `PhoneLook`.
- **Input:** no hover handling anywhere in the app (`hoverable`/`PointerEventType.Enter` appear nowhere). On a phone that's right; on Quest, a controller's pointer hovers before it clicks, and Meta makes hover states a requirement.
- **Palette:** under `PhoneLook` the canvas is #0B0D1C (near-black navy) and `textPrimary` is **#FFFFFF**. Meta recommends avoiding pure #FFFFFF and #000000 in the headset.
- **Motion:** the phone's Home banner drifts slowly. That's fine in a hand; in a headset it moves a large area under the eye.
- **Updates:** `Updater` asks `Lumiere/Android/quest/Latest`, but the server serves only the TV's `Lumiere/Android/Latest`. **The Quest can never update itself today.** The phone has the same gap; it is updated over USB.
- **Codec support:** `player/Compatibility.kt` already probes `MediaCodecList` at launch. That's the right pattern, the Android equivalent of the Mac's VideoToolbox probe. Never assume what the headset's chip decodes.
- **Build:** one module, three flavors, R8 and resource shrinking on release, baseline profiles. Compose BOM 2024.09.03, Media3 1.8.0. The gate is `./gradlew assembleTvRelease testDebugUnitTest`, which builds only the TV's release. Release builds are signed with the debug keystore, so installs replace each other in place.
- **Content check for VR features:** the library has **no stereoscopic files** (0 side-by-side or over/under by frame shape, 0 by name). The "3D" library is CGI animation, not stereo. Stereo playback is therefore a later, optional phase (section 7), not a first step.

---

## 4. What the recent Mac, TV and phone work means for the Quest

| Change (October 2026) | Lives in | Quest today | Action |
|---|---|---|---|
| Prism icon, periwinkle accent, navy theme | Shared `res/` mipmaps, `ui/Theme.kt` | Has it | Give Quest its own `QuestLook` palette (step 2), keeping the theme and fixing pure white |
| Top 10 rows ranked with big numbers | `PhoneHome.RankedPoster` | Has it, at phone size | Check it at panel size; widen with the panel (step 3) |
| Top 10 Artists, genre cards, songs counted as played | `PhoneMusicTop.kt`, `Music.kt` | Has it | Hover states, and 60 dp targets on the genre cards (step 3) |
| AniList franchises, Monogatari, key art, season covers | Server | Has it, automatically | — |
| **Continue the Franchise** banner on Home | Mac only (`ContinueFranchise.swift`) | Missing | Port to `PhoneHome`, which Quest gets for free (step 5). Uses `Lumiere/Collections/NextAfter/{id}`, which now returns `CollectionId` |
| **Next in this franchise** card on a title page | Mac only (`NextInCollectionCard.swift`) | Missing | Port to the phone title page (step 5) |
| **Season cover beside the season menu** | Mac only | Missing | Port to the phone's "Season 2 ⌄" header (step 5) |
| **My Watch Order** per collection | Mac only, kept on the Mac (GRDB `collectionRank`) | Missing | Move the arranged order to the server first, so Mac, phone and Quest agree on what "next" is (step 6). Porting it as local-only would give three different answers |
| Title order per library (folder name or romaji first) | Mac only (`LibraryTitleOrder`); the romaji comes from the server | Missing | Port the setting; it's server data plus a preference (step 6) |
| Country filter | Mac only; the countries come from the server | Missing | Port to the library filters (step 6) |
| The update channel | TV only on the server | **Broken** for Quest and phone | Server routes per channel, and `publish.sh` per flavor (step 1) |

---

## 5. Horizon OS practices this plan holds to

From Meta's design requirements for Android apps (section 10). Requirements first, then recommendations.

**Requirements**
- **Targets:** at least 48 × 48 dp, and **60 × 60 dp for primary controls** such as Play, tab-bar items and the player's transport. Add invisible hit slop under smaller icons, and space small controls so their hit areas don't overlap.
- **Hover and focus states on every interactive element.** Where the system draws its own hover (Look and Pinch), match its shape: rounded rectangles that follow the card's corner radius.
- **A visible back button wherever there is somewhere to go back to.** The system back is not available on every input. The phone's back chevrons already exist; check every pushed screen has one.
- **Text at least 14 sp**, 18 sp or larger for reading. The phone's `IosType.caption` (11 sp) and `footnote` (13 sp) are under that minimum and need Quest sizes.
- **Contrast 4.5:1 for text**, 3:1 for headlines, button fills and non-text marks.

**Recommendations**
- **No pure #000000 or #FFFFFF.** Text tops out at #F3F4FA, the Mac's dark `textPrimary`, and the canvas stays navy.
- **A sans-serif with a high x-height**, weights Regular to Black. The system font qualifies; avoid Light and Thin.
- **Panel size:** design for the default of 1024 × 640 dp, and test at the minimum (384 × 500) and maximum (1440 × 1000). The panel is resizable, so layouts take their column counts from the width (`phoneColumns()` already does) rather than assuming a phone.
- **Declare the panel's default size and resize behaviour in the manifest**, as Meta's panel-sizing guide describes. Take the exact element and attribute names from Meta's "AOSP features on Horizon OS" page when building step 2, not from memory.
- **Remove manifest permissions Horizon OS doesn't support**, and depend on nothing that needs Google Play services. The app uses none today; keep it that way.
- **Comfort:** no ambient drift or parallax, no flashing, no autoplaying motion behind text. Reduce Motion is treated as on by default for Quest.
- **Test colours in the headset.** The display renders saturation differently from a phone; the periwinkle accent may need a Quest value.

**Engineering practices**
- **Quest behaviour lives in the `quest` source set and one `QuestLook` object**, the way `TvLook` and `PhoneLook` work. It is not scattered `if (Flavor.quest)` checks. Shared screens read sizes and capabilities from composition locals (`LocalFormFactor` gains `isHeadset`), so each screen is written once.
- **Pure logic stays pure and unit-tested:** franchise "next", title order, the hover-target sizes table. Same rule as the Mac's.
- **Every flavor is built and tested at the gate**, not just the TV's.
- **Probe, don't assume:** what the headset decodes comes from `MediaCodecList` at launch, as now. A new codec path is chosen from the probe.
- **Measure memory** on the headset with `adb shell dumpsys meminfo app.lumiere.android.quest` while browsing and during an hour of playback. Write the numbers into this file, as the Mac's CLAUDE.md does.

---

## 6. Build and release work (the foundation)

1. **Gate script.** Add `Scripts/check.sh` to LumiereAndroid:
   - `assemblePhoneRelease`, `assembleTvRelease`, `assembleQuestRelease`
   - `testDebugUnitTest` (all three flavors, as now)
   - `lintQuestRelease` with a baseline file, so new lint warnings fail and the old ones are paid down
   - green before any commit, like the Mac's gate
2. **The update channel.**
   - The server serves `Lumiere/Android/{phone,quest}/Latest` and `…/lumiere.apk` beside the TV's.
   - `publish.sh` takes the flavor (`publish.sh tv|phone|quest`) and writes to `android/<flavor>/`.
   - The server's `APILevel` goes up with it, and the app hides Install Update on an older server instead of failing quietly.
   - After this, the Quest updates from its own Settings without a cable.
3. **Dependencies.** Move to current stable releases in one dedicated step, with the whole gate and a headset check, and never mixed with feature work:
   - the Compose BOM (2024.09 is two years old)
   - lifecycle
   - activity
   - Coil
   - the ASS renderer

   Media3 moves only with a playback check on all three devices.
4. **Signing.** Releases are signed with the debug keystore. That's convenient but not a release practice: anyone with that well-known key could sign an update. Moving to a proper upload key kept outside the repo (path and passwords from `~/.gradle/gradle.properties`, never in `build.gradle.kts`) is right. But Android will not install a differently signed build over the old one, so every device needs one uninstall and reinstall (sign-in and downloads lost once). **Your decision** (section 11).
5. **Quest-only manifest settings** live in `app/src/quest/AndroidManifest.xml`: the panel's default size and resizing, and dropping `screenOrientation="landscape"` if Meta's page says panels ignore or dislike it.

---

## 7. VR-native features (later, each needs your yes)

These use Meta's **Spatial SDK**, Meta's Kotlin SDK for Android apps on Quest. It would be the app's first Meta dependency, so each item waits for a decision.

- **Cinema mode.** Play a film on a large screen in a dim virtual room, or in passthrough with the room darkened. Media3 keeps decoding; the Spatial SDK supplies the room and the screen surface. The 2D panel remains the default; Cinema is a button in the player.
- **Stereoscopic playback.** The Spatial SDK has stereo modes for side-by-side and over/under video. Nothing in the library is stereo today, so build this only when there is content for it. Detection would be by frame shape from the server's stream data (width ≥ 3.2 × height) plus filename tags such as `SBS`, `HSBS` and `OU`, with a per-title override.
- **Spatial audio** for Cinema mode. A film's 5.1 or 7.1 is placed around the room. This follows Cinema mode and is not a separate project.

Not planned: 360° and VR180 video (no such content), games-style locomotion, or anything that moves the user.

---

## 8. The order of work

Each step ends with the gate green, a commit, a published build for the Quest (after step 1, through its own updater), and your check in the headset.

1. **Update channel and gate** (section 6, items 1–2). Server routes, `publish.sh <flavor>`, `Scripts/check.sh`, API level. *Done when:* the Quest offers and installs an update from its own Settings.
2. **`QuestLook`.** Quest palette (no pure white, navy canvas, accent checked in the headset), Quest type sizes (nothing under 14 sp, body 18 sp), panel size in the manifest, `LocalFormFactor.isHeadset`, Reduce Motion on, the Home banner's drift off. *Done when:* every screen passes the contrast and size table in section 9 at 1024 × 640.
3. **Pointer and hover.**
   - A shared `Modifier.questTarget()` that adds the hover state, the 48/60 dp minimum with hit slop, and the pressed scale.
   - Applied to cards, rows, pills, the tab bar, the player's transport, and the music cards and Top 10 rows.
   - The card corner radius matches the system hover shape.

   *Done when:* every control can be hit by pinch on the first try, and every control lights when pointed at.
4. **Panel resizing.** Layouts at 384 × 500, 1024 × 640 and 1440 × 1000: columns from width, the player letterboxed rather than cropped, no clipped text. *Done when:* the three sizes look intended, not stretched.
5. **Franchise parity with the Mac.**
   - Continue the Franchise on Home.
   - Next in this franchise on the title page.
   - The season cover beside the season menu.
   - "Next" logic in one pure, unit-tested function shared with the phone. Ported in shared code, so the phone gets them in the same step; tell the phone session.

   *Done when:* the same title shows the same "next" on the Mac and in the headset.
6. **Server-side watch order, title order and countries.**
   - "My Watch Order" moves from the Mac's local store to the server, with a migration that uploads existing arrangements once.
   - The Mac, phone and Quest all read it from there.
   - The Android apps gain per-library title order (romaji, folder name) and the country filter.
   - Back up the server database before the migration.
7. **Dependency refresh and signing** (section 6, items 3–4), only after your decision on signing.
8. **Cinema mode** (section 7), only after your yes on the Spatial SDK.

---

## 9. How each step is checked

**By the build:**
- `Scripts/check.sh` green: all three flavors, unit tests and lint against the baseline.
- New pure logic has tests written first, from the real shape of the data.

**By you, in the headset** (I can't see inside it), using this check-list:

| Check | Pass |
|---|---|
| Point at every control on Home, a title page, Music and the player | Each lights before you pinch |
| Pinch the smallest control on each screen with hand tracking | Works on the first try, three times out of three |
| Read the smallest text at your normal panel distance | Readable without leaning in |
| Resize the panel to its smallest and largest | Nothing clipped or stretched |
| Leave Home open for a minute | Nothing moves by itself |
| Play a film for an hour | No stutter; memory figure noted here |
| Settings › Install Update | Offers, downloads, installs |

**By measurement:**
- Memory, from `dumpsys meminfo` while browsing and after an hour of playback. The first numbers set the Quest's budget, recorded here.
- Optionally, a screen recording through Meta Quest Developer Hub's cast, for design-critique and accessibility passes after steps 3 and 5.

---

## 10. Sources

- Meta, Android apps on Horizon OS, design requirements: https://developers.meta.com/horizon/documentation/android-apps/design-requirements
- Meta, Horizon OS panel sizing: https://developers.meta.com/horizon/essentials/horizon-os-panel-sizing/
- Meta, Styles and layouts (default and limit sizes): https://developers.meta.com/horizon/design/styles_layouts/
- Meta, Making apps compatible (permissions, dependencies, flavors): https://developers.meta.com/horizon/documentation/android-apps/making-apps-compatible-overview
- Meta Spatial SDK, media playback and stereo modes: https://developers.meta.com/horizon/documentation/spatial-sdk/spatial-sdk-media-playback

## 11. Decisions (made 2026-10-27)

1. **Signing key: move to a proper key.** One reinstall per device is accepted. Done in step 7, with you present for the reinstalls, since each loses that device's sign-in and downloads once.
2. **Spatial SDK: yes.** Cinema mode (step 8) goes ahead; it is the app's first Meta dependency.
3. **Distribution: sideloaded, updating itself.** No Meta Horizon Store work; step 1's update channel is the way builds reach the headset.
