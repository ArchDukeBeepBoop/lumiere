# Lumiere VR: handover for a local session

From the cloud session on branch `claude/blissful-goodall-k71k9o` (last commit `79dc793`, 2026-10-14).
Read this first, then `docs/quest/PLAN.md` (the spatial app's plan and history).

## 0. Read before anything: there are two Quest apps

| | This branch (`android/quest/` module) | The plan the user now wants (`QUEST_PLAN.md`) |
|---|---|---|
| App id | `app.lumiere.android.spatial` | `app.lumiere.android.quest` ("Lumiere for Quest") |
| What it is | Meta Spatial SDK app: the phone/TV screens in a window, a 3D Director, Theater, places | The `quest` flavour of `android/app` |
| Status | Built up over many rounds, sideloaded by the user as split APKs | Step 1 done 2026-10-27, step 2 (QuestLook) next |

**The cloud session couldn't continue `QUEST_PLAN.md`.** Neither `docs/QUEST_PLAN.md` nor `Scripts/check.sh`
is on GitHub (newest `origin/main` commit: 2026-10-24). They exist only in the user's local checkout.
A local session should:
1. read `docs/QUEST_PLAN.md` in full;
2. do the steps one at a time: `./Scripts/check.sh` green → commit → `./Scripts/publish.sh quest` →
   ask the user to run that step's headset checks (plan section 9);
3. use the work below as a source of answers and code, rather than redoing the debugging. Step 8
   (Cinema mode on the Spatial SDK) in particular should reuse §3 and §4.

Standing rules: the TV session shares the checkout, so don't touch TV-only code. Report any shared phone code you
change. Never install over something playing, and never hand the user an install command. Every personal
preference is a Settings option. Refer to the user as they/them. Commit trailer:
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Keep model names out of commits and PRs.

The user's working style: they test in the headset and send **Diagnostics reports** (see §2). They want short
replies and a built APK after each change. Earlier builds were sent as `split -b 29M` parts for SideQuest.
The QUEST_PLAN replaces that with `publish.sh` plus self-update.

## 1. Layout of the spatial app

- `android/core`: Server (Jellyfin-based "Lumiere Server" on the user's Mac), Probe, Breadcrumbs, CrashLog/StartGuard.
- `android/screens`: all Compose UI (phone/TV/Quest window), AppState, Stage (place, size, mount), Theater
  (film state), SelfTest + Diagnostics, Handset, SpatialSidebar, LocalVideos, AudioOutputs.
- `android/quest`: `LumiereSpace` (activity, panels, MRUK), `Director` (per-tick spatial logic), `Sky`,
  `TheaterScreen`/`TheaterGeometry`, `RoomWalls`/`WallMount`, `Remote` (controllers → keys and scroll),
  and the old modelled places (blocks).
- `android/Scripts/env`: Blender scene scripts (`envkit.py`, `cinema.py`, `cabin.py`, `station.py`,
  `lakeside.py`, `terrace.py`, `moonbase.py`, `skies.py`, plus unused palace/winter/drivein/rooftop/sea).
  These ran under bpy 5.0.1 in a venv (`pip install bpy`), headless, Cycles on the CPU.

## 2. Diagnostics (keep it; it's how bugs were found)

- **Check** on the sidebar rail opens `DiagnosticsScreen`. On opening it runs `SelfTest`. **Save report**
  writes `Download/Lumiere/lumiere-diagnostics-*.txt`, which the user uploads.
- `Probe.report(area, name, status, detail)` (core) is live state from every subsystem.
  `Breadcrumbs` persists start steps across native crashes. `SelfTest.exits()` reads
  `ApplicationExitInfo` including native tombstones (it found the SDK crash below).
- The build stamp (version · git commit · build time) is on the page, so you can tell which APK is installed.

## 3. Hard-won Quest / Spatial SDK facts (0.14.0)

1. **`SceneTexture(Bitmap)` uploads arrive WHITE on the GPU**, and `fromResource()` did too on the baked glTF
   models. glTF materials with `KHR_materials_unlit` also drew white. **Baked 3D rooms were abandoned for this.**
   Textures do work through the toolkit `Material(baseTextureAndroidResourceId, unlit=true)` on
   `mesh://skybox`, which is how the skies and 360 rooms are drawn.
2. **RGB_565 bitmaps crash natively** (SIGABRT in `GraphicsHSR::SceneTextureUpdate`). Use ARGB_8888.
3. **`Quaternion(w, x, y, z)`**: w comes first. A half-turn about up is `Quaternion(0f, 0f, 1f, 0f)`.
4. **FLAG_SECURE on the window panel makes it draw solid black in the headset.** That caused the "private room
   is a black page" bug. It's off on Quest.
5. The Home window is a panel activity, so `finish()` doesn't quit. Quit through `OpenApp.quit` and
   `finishAndRemoveTask()` on the spatial activity.
6. **StartGuard**: a "plain start" (no 3D) now trips only when `ApplicationExitInfo` shows a crash or ANR. A
   timer-based guard tripped on SideQuest reinstalls and made "nothing works".
7. **MRUK walls**: request `USE_SCENE` (and `USE_ANCHOR_API`). Call `loadSceneFromDevice(false, true,
   SceneModel.V2_FALLBACK_V1)`, because `true` can wait for ever. Time it out at 10 s. Walls come in world space
   through `TransformParent`.
8. The controller thumbstick only exposes button bits, with no analog position. Smooth scrolling is done with
   injected `ACTION_SCROLL` (`OpenApp.scroll`).
9. `largeHeap="true"`. 4096² atlases at ARGB were about 64 MB each.
10. Banner previews need the signed-in OkHttp data source, or the server answers 401.

## 4. Places (current design)

- Offered: room, cinema, cabin, lake, clouds, moon, station, space, void (`Stage.offered`). The palace,
  winter cabin, drive-in, rooftop and sea were withdrawn.
- Each is a **360° equirect picture rendered in Blender from the seat**, shown on the skybox and turned with
  `Sky.face(seat)` (times a half-turn).
  - Cinema, cabin and station have one picture per screen size: `pano_<place>_s0..4`. Changing size changes seat.
  - Lake, clouds and moon have `pano_<place>` plus `pano_<place>_dark`.
  - When a film plays: the dark picture if there is one, otherwise the lit one dimmed to 0.32. Changes fade
    through near-black (`Sky.fadeTo`, using albedo; **unconfirmed** that the SDK honours albedo on the skybox).
- In 360 places the film screen is placed `Sky.FAR` (6×) further away and larger, so its stereo depth matches
  the picture (`Director.far`). This is **unconfirmed** in the headset.
- Render: `PANO=<view> PANO_OUT=… PANO_RES=4096x2048 PANO_SAMPLES=64 PANO_SKY=<sky jpg> [PANO_SIZE=k]
  [PANO_SEAT=hx,back,front] [PANO_DARK=0.1] python <place>.py preview <dir>`.
  - `PANO_SEAT` removes only your own seat (seat boxes used: cinema `0.36,0.45,0.55`, cabin `1.35,0.6,0.5`,
    station `0.5,0.6,0.5`).
  - A cinema seat takes about 30–60 min on 4 cores, so batch them.

## 5. Open items the user raised

- **Check in the headset:** the screen lines up with the drawn screen at each seat, and the 6× screen isn't
  blurry. Confirm the fade.
- **Dark seat pictures** for the cinema, cabin and station (skipped for time; the dimming stands in).
- The sidebar's own scrolling is still step-wise (SDK panel scroll).
- The moon's dark version barely darkens (the sun stays).
- Log spam every tick: `attempt to get key for attribute 1000005 on entity 0` (cause not found; harmless).
- Wall mount works: it brings up the handset and can be taken off from there.
- The private room works, without a PIN on Quest. On-device videos work. Captions work.
