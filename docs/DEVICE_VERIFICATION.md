# WS5 / WS6 — On-Device Verification Checklist (the DEFERRED reach)

**Owner**: the app maintainer.
**Why this file exists**: the WS5 actuators (`lib/actuators/`) and the WS6 live
drive brain (`lib/services/drive_hud_controller.dart`) are **code-complete and
wired** — the caution code-path reaches the driver on audio + haptic. But **no Android
device is available in this build environment**, so the final "she HEARS / FEELS
it" step is **DEFERRED**, not done. Under observation-grade verification (reach
is verified on a device), the app **must not claim "works on Android"** from a green test suite
alone: passing tests + a render-SEE on desktop prove the *code-path*; only a real
device proves the *reach*. This checklist is what makes the deferred claim
honest — each item is verified on a real phone before any "reaches the driver on-device"
claim is made.

## How to use

Run the app on a real Android device (`flutter run -d <device>`), drive the WS6
"Live drive — compound-failure caution" panel + the WS5 "Announce to driver"
button, and check each item. Record PASS/FAIL + device + date. A FAIL is an
Andon, not a footnote.

---

## Audio channel (flutter_tts)

- [ ] **ja-JP voice pack present** — the device has a Japanese TTS voice
      installed; `setLanguage('ja-JP')` selects it (not a silent fallback to a
      Latin voice mangling the kana). If absent, the app must surface that the
      Japanese voice is missing, never speak garbled audio.
- [ ] **Actually audible over road noise** — spoken guidance is loud enough to
      hear at highway speed with the heater/defroster running; consider media
      volume + audio-focus ducking of music/nav.
- [ ] **Spoken text is the correct JA guidance** — the `heightenedCaution` /
      `considerStopping` line matches `DriveHudLocalizer.spokenGuidance(...,'ja')`
      verbatim (no truncation, no re-ordering).
- [ ] **A TTS fault does not crash the drive surface** — kill the TTS engine
      mid-drive; the map + caution banner stay up (the outer catch holds).

## Haptic channel (vibration)

- [ ] **Fires on real hardware** — `warning` and `critical` produce a felt
      vibration on a device with a vibrator; the deaf / HoH / can't-hear driver
      gets the cue.
- [ ] **warning vs critical are distinguishable by touch** — 2 measured pulses
      (warning) vs 3 longer/urgent pulses (critical); a driver can tell "ease"
      from "consider stopping" without looking.
- [ ] **Absent vibrator degrades safely** — on a device with no vibrator the app
      does not crash and still speaks.

## Keep-awake (wakelock_plus)

- [ ] **Screen stays awake while the nav surface is foregrounded** — the screen
      does not dim/lock under the OS screen-timeout during an active drive.
- [ ] **Wakelock holds under Doze / battery-saver** — verify on a device in
      battery-saver mode; document any OEM (e.g. aggressive Chinese-ROM) killer.
- [ ] **Released when the surface leaves** — backgrounding the app releases the
      SCREEN wakelock. NOTE (2026-09-24): the drive's foreground service also
      sets geolocator's `enableWakeLock: true`, a CPU wakelock with a different
      lifetime — it is held for the whole drive, screen off included, and is
      released when the last position-stream listener detaches. Check both.
- [ ] **Single owner** — only ONE actuator toggles the wakelock (WS6 injects the
      app's single actuator; the controller never resolves its own). No
      double-hold / double-release.

## Foreground-service / long-drive reality

THIS SECTION'S PREMISE CHANGED 2026-09-24. It read "today the app is
foreground-only"; that is no longer true. The ongoing-drive foreground service
landed (geolocator's own `GeolocatorLocationService`, driven by
`driveLocationSettings`), so the checks below are now LIVE, not hypothetical.

- [ ] **Multi-hour screen-off drive** — a true hours-long drive with the screen
      off. Verify the app is NOT silently killed mid-drive, and that the
      ongoing-drive notification is **actually visible for the whole of it**
      (FOREGROUND_SERVICE_LOCATION) — **never silent background location**
      (no ACCESS_BACKGROUND_LOCATION; refused for dignity).
- [ ] ⚑ **THE NOTIFICATION ACTUALLY APPEARS ON ANDROID 13+.** This is the one
      that cannot be checked on our AVD, which is API 30 (measured 2026-09-24:
      `ro.build.version.sdk=30`) where POST_NOTIFICATIONS does not exist and
      the notification posts freely. targetSdk is 36. On a 13+ device the
      permission is denied by default and the app does not yet request it, so
      the service can run with location collection and NO visible indicator —
      the exact state the manifest, `her_position.dart` and the in-app
      disclosure all declare forbidden. **Needs a real 13+ device. Until then
      this row is UNVERIFIED, never *cleared*.**
- [ ] **Tapping the notification** — confirm it opens the app (geolocator wires
      a bring-to-front intent) and that she can then find and press 停止. It
      does NOT end the drive by itself; the shade words must not imply it does.
- [ ] **Lock screen** — geolocator creates the channel with
      `VISIBILITY_PRIVATE` and `IMPORTANCE_NONE`
      (BackgroundNotification.java:69,71). Nobody has yet looked at what she
      sees on a LOCKED phone, which is the condition the words actually name.
- [ ] **Battery-killer audit** — the ongoing-drive notification + wakelock do not
      drain the battery unacceptably over a 1-hour drive.

## Alert quality (non-startling, interruptible)

- [ ] **Not startling** — the first haptic/audio at speed does not jolt the
      driver into an unsafe reaction; onset is firm but not alarming.
- [ ] **Interruptible / non-nagging** — de-dup works: a steady caution rung does
      NOT re-announce every tick (the controller fires only on a rung RISE); a
      later re-rise re-announces. The driver is not nagged.
- [ ] **Advisory tone preserved on-device** — the ceiling is spoken as an
      invitation ("if you can do so safely, pausing … is an option"), never a
      command; the tone survives the TTS voice.

## Consent / dignity (WS7 interaction)

- [ ] **Deny-by-default honored** — nothing touches GPS or speaks until the driver's
      deliberate "Share my location"; the WS6 brain has no position until then.
- [ ] **Revoke stops the reach** — revoking location mid-drive surfaces
      `PositionUnavailable`, the honest dot degrades toward `lost`, and no stale
      confident dot or phantom announcement continues.

---

## Status

**DEFERRED** — no **physical** Android device in this environment. An Android
SDK, an emulator and the AVD `sngnav_api30` DO exist here and were walked on
2026-07-09 (`ladder_out/`, 71 files tracked in git; airplane-mode pass
2026-07-10). Until every item above is PASS on a **physical phone**, the app
claims only: *"the caution code-path reaches the driver on audio + haptic; on-device
HEAR / FEEL is deferred."* It never claims *"works on Android."*

> **Corrected 2026-08-09.** This line read *"no Android
> device in this environment"* — false since 2026-07-09, and never propagated.
> The deferral itself was and remains correct: the emulator ladder ran
> `-no-audio` and bound a **server** voice, so it cannot discharge HEAR or FEEL.
> Measured this turn: `flutter devices` → `Found 1 connected device: Linux
> (desktop)`; `adb devices` → empty.
