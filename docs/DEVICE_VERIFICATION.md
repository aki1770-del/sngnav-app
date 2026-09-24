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
      the notification posts freely. targetSdk is 36.
      ⚑ Corrected 2026-09-25: this row said the app "does not yet request it,
      so the service can run with location collection and NO visible
      indicator". That is FALSE at HEAD. The app requests it
      (`_askForDriveNotificationPermission`, called from `_shareLocation` in
      `lib/main.dart`), and when it cannot post, NO foreground service is
      started — the `driveNotification:` argument is null — and the drive is
      screen-on only. The service can never START behind a notification it
      cannot post. (What it cannot prevent is the notification being hidden
      or swiped away AFTER it starts — see the two rows below.)
      What still needs a real 13+ device is the ROW BELOW, not this one.
      **Needs a real 13+ device to watch the dialog appear and the
      notification land. Until then this row is UNVERIFIED, never *cleared*.**
- [ ] **Tapping the notification** — confirm it opens the app (geolocator wires
      a bring-to-front intent) and that she can then find and press 停止. It
      does NOT end the drive by itself; the shade words must not imply it does.
- [ ] ⚑ **Lock screen — MEASURED ON AN EMULATOR, NOT ON HER PHONE.**
      On a secured Android 14 (API 34) emulator (PIN set, `deviceLocked=1`),
      a probe posting this app's notification exactly as geolocator_android
      4.6.2 builds it (channel `geolocator_channel_01`, `IMPORTANCE_NONE`,
      `VISIBILITY_PRIVATE`, `setOngoing(true)`, location FGS) was ABSENT from
      the lock screen — no card, no shelf icon. The same run at channel
      importance LOW and at DEFAULT: also absent. Beside a plain, non-ongoing
      notification from the same app: both shown, auto-grouped. (AAE lock
      probe 2026-09-24, six controlled runs; re-measured 2026-09-25, lone FGS
      absent again.) The record's importance was 2 although the channel said
      0, and the channel dump showed `mLockscreenVisibility=-1000`, so
      neither source constant describes what the platform did.
      ⚑ Corrected 2026-09-25: this row said "Android filters
      minimum-importance notifications", "Nobody has looked", and
      "INCONCLUSIVE" from an unset `lock_screen_show_silent_notifications`.
      All three were wrong the moment they were written: the probe above had
      looked the day before, and it had already falsified importance as the
      lever. It also recorded a fix route — create `geolocator_channel_01`
      FIRST at `IMPORTANCE_LOW` so geolocator's NONE call cannot lower it —
      which that same probe had already run: LOW was absent too. That route
      is withdrawn; nothing measured so far makes a LONE ongoing FGS
      notification appear on this lock screen.
      Consequence already taken: the notification body no longer promises
      「画面オフでも警告」, and the privacy policy, store listing and in-app
      card now say the notification may not show on a locked screen.
      **Still owed: her phone, secured, locked, during a real drive.
      UNVERIFIED there, never *cleared*.**
- [ ] ⚑ **Swipe to dismiss — MEASURED 2026-09-25 ON AN EMULATOR: SHE CAN.**
      Same secured API 34 emulator, same probe, unlocked: ONE sideways swipe
      (`input swipe`, 800 ms) removed the notification from the shade, and
      `dumpsys activity services` still reported `isForeground=true`. Positive
      control: the identical gesture removed a plain shell notification. Two
      earlier gestures were instrument failures and are NOT evidence: a 300 ms
      `input swipe` registered as a TAP (it relaunched the probe), and an
      `input motionevent` drag removed neither the probe nor the control.
      Record flags `0x62` (ONGOING | NO_CLEAR | FOREGROUND_SERVICE), no
      `0x2000` (NO_DISMISS). After the swipe, the only trace was Android's
      「1 個のアプリがアクティブです」 in the fully expanded Quick Settings
      footer; the status-bar icon was gone. The probe does not read location,
      so whether a location status icon would remain is NOT measured.
      Why it matters: the app is not told (geolocator sets no deleteIntent),
      and 停止 is the only thing that ends collection — so on 14+ location can
      keep running with nothing in the shade, the state the manifest's dignity
      comment reserves to the Chair. The pages now disclose it. The fork (stop
      the drive on dismissal, re-post it, or keep disclosing) changes what she
      experiences mid-drive and is routed to the Chair through the SEO.
      **Still owed: the real app on her phone, and one pre-14 image to bound
      the "below 14 it cannot be swiped" half, which is recalled, not
      measured.**
      ⚑ Do NOT resolve this by dropping `setOngoing` — see the setOngoing
      comment in `lib/her_position.dart`.
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
