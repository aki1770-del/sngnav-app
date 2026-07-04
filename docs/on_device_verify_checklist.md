# On-Device OPS-066 Verify — Published JA Narration + Voice (the 10-minute act)

**Owner**: AAE (android-app-engineer). **Status**: **DEFERRED — no Android device
in the build environment.** Everything below is PREPARED; the moment a device is
plugged in, this is a ~10-minute verification, not a build session.

**Companion**: `docs/DEVICE_VERIFICATION.md` (the WS5/WS6 actuator deep
checklist — audio quality, haptic distinguishability, wakelock, long-drive).
THIS file is the fast reach-verify for the **published Japanese narration +
voice** after the 2026-07-05 dependency bump (voice_guidance **0.7.2**,
adaptive_reroute **0.1.5**, all hosted).

**Honesty note on the expected register**: the published JA maneuver narration
in `voice_guidance 0.7.2` (`ManeuverSpeechFormatter`) prefers the maneuver's
own `instruction` when non-empty, and otherwise speaks the fallback register:
`左折です。` / `右折です。` / `目的地に到着します。` / `出発します。` /
`次の案内です。`. There is **no** `国道…方面へ左折` template in the published
package or this app — do not "verify" a string that does not exist. Hazards
speak as `危険。…` (critical) / `注意。…` (warning); off-route as
`ルートを外れました。再検索します。`.

---

## Pre-flight (already done, this session, 2026-07-05)

- APK built: `build/app/outputs/flutter-apk/app-debug.apk` (111M, debug,
  `flutter build apk --debug --target-platform android-arm64` exit 0; badging
  lists arm64-v8a + armeabi-v7a + x86_64 native code — installs on a real
  phone AND the x86_64 emulator).
- Merged permissions verified from the artifact (`aapt dump permissions`):
  INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, WAKE_LOCK,
  FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION, VIBRATE —
  **no ACCESS_BACKGROUND_LOCATION** (dignity floor intact).
- `flutter analyze` clean; `flutter test` all 198 pass on the bumped deps.
- Toolchain persists (no scratch rebuild needed next time):
  SDK `/home/komada/android-sdk` (platform 34+36, build-tools 36.0.0,
  cmake 3.22.1), JDK `/home/komada/android-sdk/jdk-21.0.11+10`, both registered
  via `flutter config --android-sdk … --jdk-dir …`.

## Rebuild-if-stale (only if the tree changed since the APK's mtime)

```sh
cd sngnav-app
flutter build apk --debug --target-platform android-arm64   # ~7 min cold, ~10 s warm
```

---

## The 10 minutes

### 1. Install (1 min)

```sh
adb devices                      # device shows as 'device', not 'unauthorized'
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n dev.aki1770del.sngnav_app/.MainActivity
```

- [ ] App launches to the Akita map surface; no crash on boot.
      (Capture: `adb logcat -d > run_out/verify_boot.log` on any failure.)

### 2. Consent flow in JA (1 min)

Set the device language to 日本語 (Settings → System → Languages) — or verify
the app's JA strings directly (the l10n keys are locale-driven).

- [ ] Before any grant: the JA deny-by-default line shows —
      `位置情報はまだ共有されていません。` — and NO permission dialog has
      appeared uninvited (deny-by-default: nothing touches GPS until HER act).
- [ ] Tap `現在地を共有` (Share my location) → the **OS** permission dialog
      appears, in Japanese, offering while-in-use only.
- [ ] Deny once → the app degrades honestly (JA permission-state message, e.g.
      `位置情報の許可が恒久的に拒否されています（OSの設定で変更してください）`
      for the permanent case); no crash, no nag loop.

### 3. Live location dot (1 min)

- [ ] Grant while-in-use → HER position dot renders on the map (real GPS; or
      `adb emu geo fix <lon> <lat>` on the emulator).
- [ ] Revoke mid-session (Settings → Apps → sngnav_app → Permissions) → the dot
      degrades toward `lost` honestly; no stale confident dot.

### 4. Route request → JAPANESE maneuver list (2 min)

The app fetches driving routes from the OSRM public demo
(`router.project-osrm.org`, `lib/route_fetch.dart` / `OsrmRoutingEngine`) —
needs network; INTERNET permission is in the APK.

- [ ] Request a route (destination entry on the map surface) → maneuver list
      populates (`RouteManeuver` list; next actionable maneuver highlighted).
- [ ] With the device/app locale ja: narration text for a maneuver whose
      instruction is empty falls back to the published register —
      `左折です。` / `右折です。` — and arrival shows `目的地に到着します。`.
- [ ] Position-confidence gating (commit 9035519): with the dot honest-degraded
      (revoke or GPS off), the turn is NOT announced — SUPPRESS, not a
      confident lie. Re-grant → narration resumes.

### 5. Voice = the SAME Japanese text (2 min)

- [ ] **Device prerequisite (one-time)**: a Japanese TTS voice is installed —
      Settings → Accessibility (or System → Languages) → Text-to-speech →
      install/confirm 日本語 voice data. Without it `setLanguage('ja-JP')`
      must surface "JA voice missing", never speak mangled kana
      (see DEVICE_VERIFICATION.md audio section).
- [ ] Trigger an announcement (WS5 announce control, or a caution-rung rise in
      the WS6 live-drive panel) → the utterance is **verbatim** the on-screen
      JA text (`DriveHudLocalizer.spokenGuidance(...,'ja')` /
      `ManeuverSpeechFormatter` output) — no truncation, no English fallback,
      no re-ordering.

### 6. Whiteout modality — eyes-off (2 min)

- [ ] Drive the caution rung to `considerStopping` (WS6 panel) → **audio AND
      haptic fire together** (OPS-059 floor: the deaf/HoH driver gets the
      haptic; the whiteout-blinded driver gets the audio).
- [ ] Screen is HELD LIT (wakelock) — a glance never finds a dark screen.
- [ ] De-dup: a steady rung does not re-announce every tick; a re-RISE does.

### 7. Record per OPS-066 (1 min)

- [ ] Screenshots: `adb exec-out screencap -p > run_out/verify_<step>_<date>.png`
      for steps 2, 3, 4 (consent JA / dot / JA maneuvers).
- [ ] Log: `adb logcat -d -s flutter > run_out/verify_<date>.log`.
- [ ] Append PASS/FAIL + device model + Android version + date per item to
      this file (a FAIL is an Andon, not a footnote — OPS-066 clause B: a
      caught overstatement fires the cord same turn).
- [ ] Only after every box above is checked on a REAL device may any surface
      claim "JA narration + voice verified on-device". Until then the claim
      stays: *code-complete, analyze-clean, 198 tests green, APK built —
      on-device reach DEFERRED.*

---

## Results log

| Date | Device | Android | Step | PASS/FAIL | Evidence |
|------|--------|---------|------|-----------|----------|
| —    | —      | —       | —    | —         | —        |
