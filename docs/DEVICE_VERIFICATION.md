# WS5 / WS6 — On-Device Verification Checklist (the DEFERRED reach)

**Owner**: AAE (android-app-engineer) per CLAUDE.md §4.
**Why this file exists**: the WS5 actuators (`lib/actuators/`) and the WS6 live
drive brain (`lib/services/drive_hud_controller.dart`) are **code-complete and
wired** — the caution code-path reaches HER on audio + haptic. But **no Android
device is available in this build environment**, so the final "she HEARS / FEELS
it" step is **DEFERRED**, not done. Per OPS-066 (observation-grade verification)
and AAE-1, the app **must not claim "works on Android"** from a green test suite
alone: passing tests + a render-SEE on desktop prove the *code-path*; only a real
device proves the *reach*. This checklist is what makes the deferred claim
honest — each item is verified on a real phone before any "reaches HER on-device"
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
      wakelock (foreground-only contract; no silent battery drain).
- [ ] **Single owner** — only ONE actuator toggles the wakelock (WS6 injects the
      app's single actuator; the controller never resolves its own). No
      double-hold / double-release.

## Foreground-service / long-drive reality

- [ ] **Multi-hour screen-off drive** — a true hours-long drive with the screen
      off would need a foreground service; today the app is foreground-only.
      Verify the app is NOT silently killed mid-drive, and that a future
      foreground service uses a **user-visible ongoing-drive notification**
      (FOREGROUND_SERVICE_LOCATION) — **never silent background location**
      (no ACCESS_BACKGROUND_LOCATION; refused for dignity).
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

- [ ] **Deny-by-default honored** — nothing touches GPS or speaks until HER
      deliberate "Share my location"; the WS6 brain has no position until then.
- [ ] **Revoke stops the reach** — revoking location mid-drive surfaces
      `PositionUnavailable`, the honest dot degrades toward `lost`, and no stale
      confident dot or phantom announcement continues.

---

## Status

**DEFERRED** — no Android device in this environment. Until every item above is
PASS on a real device, the app claims only: *"the caution code-path reaches HER
on audio + haptic; on-device HEAR / FEEL is deferred."* It never claims *"works
on Android."*
