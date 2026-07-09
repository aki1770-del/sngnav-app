# sngnav-app emulator API-level ladder — FINDINGS (2026-07-09)

Implementer: CT. Repo HEAD at walk time: `fb51490949223ae923fb224d61a1860adc7f4785` (rebuilt fresh; `flutter build apk --debug` exit 0, 39.2s, APK 185,530,589 bytes, mtime 2026-07-09 20:27).
All artifacts under `ladder_out/api30/`. Every claim below cites an artifact or a command output read this session.

## Environment measured BEFORE running (OPS-062)

- `/dev/kvm` present (crw-rw---- root:kvm).
- SDK root: `/home/komada/android-sdk` (NOT `~/Android/Sdk`; located via `flutter config --list`).
- **No emulator binary and no system images existed at session start.** The 4 pre-existing AVDs (sngnav_obs, sngnav_dot, sngnav_t, sng_arc — all `target=android-34` per their config.ini) pointed at an emulator + android-34 image installed in a prior session's `/tmp/claude-1000/...31ce4f05.../scratchpad/android-sdk` (per `emu-launch-params.txt` / `hardware-qemu.ini` in the AVD dirs) — that path no longer exists (`ls` ENOENT). So the "existing" AVDs were NOT runnable.
- Per the one-download cap, installed via sdkmanager into the persistent SDK root: `emulator` + `system-images;android-30;google_apis;x86_64` (exit 0). Created AVD `sngnav_api30` (pixel_5 profile).

## Per-API status

| API | Status | Basis |
|-----|--------|-------|
| 30 | **RAN — full walk complete** | this file, artifacts in `api30/` |
| 34 | **SKIPPED** — android-34 system image not installed (prior copy lived in wiped /tmp scratchpad); one-image download cap already spent on API 30 | `ls /home/komada/android-sdk/system-images/` → `android-30` only |
| 36 | **SKIPPED** — same reason (no android-36 image ever present) | same `ls` |

## API 30 walk

- **Boot**: headless (`-no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -accel on`). `BOOT_SECONDS=28` (`api30/boot_time.txt`). `getprop ro.build.version.sdk` → 30.
- **Install**: `adb install -r` → `Success`.
- **Launch**: `am start -n dev.aki1770del.sngnav_app/.MainActivity` (component verified from AndroidManifest.xml line 34 + build.gradle applicationId) → `Starting: Intent {...}`, focus reached `dev.aki1770del.sngnav_app/...MainActivity` (dumpsys window).

### Walk steps

1. **Launch screen (`01_consent_gate.png`)** — NOTE: the app at HEAD fb51490 does NOT show a blocking Japanese consent gate at launch. It opens directly to the "sngnav-app (alpha)" control screen (alpha disclaimer banner, Driver profile=ageingRural, Mocked road condition=ice, Vehicle class dropdowns). The filename is kept per contract but its content is the main control screen. Consent in this build is a **location-consent card** (opt-in, deny-by-default) inside the Map panel, in English.
2. **Consent surface (`02b_location_consent.png`, `ui_dump_14.xml`)** — "Location not yet shared." + buttons `Share my location` / `Use Akita mock (dev)` + full privacy copy (JMA/NWS-only, opt-in, not stored, never sent to app servers). Consent-accept control found via uiautomator: `Share my location` bounds `[173,1069][553,1201]` → tapped center (363,1135) — not a blind tap.
3. **OS runtime permission (`02c_after_share_tap.png`, `ui_dump_15.xml`)** — Android dialog "Allow sngnav_app to access this device's location?" appeared; tapped `While using the app` (bounds `[72,1120][1008,1274]` from dump).
4. **Post-consent (`02_main.png`, `ui_dump_16.xml`)** — map card now reads "You are here · ±5 m" + `Stop` control; OS location icon in status bar. Consent path works end-to-end. (No visible position dot in the map viewport in the screenshot — emulator default GPS is not in the mapped Akita/Yamagata viewport; card text is the evidence of the location flow.)
5. **JMA card + 路面凍結ウォッチ (`03_jma_card.png`, `ui_dump_13.xml`)** — **auto-fetch LIVE on API 30**: Station 秋田 (32402), Observed 2026-07-09 20:20 JST, 26.7 °C, 71 %, wind 1.6 m/s, snow depth —, "Fetched: 20:28 (0 min ago)". **路面凍結ウォッチ row present: 該当なし** (correct: +26.7 °C July night), with the honest derived-not-JMA-statement caption.
6. **Alert sequence (`04_alerts.png`, `ui_dump_21.xml`)** — `Fire 8 sequential warning alerts` (bounds `[88,1330][992,1462]` from `ui_dump_20.xml`) tapped: Attempt 1 (t+0s) FIRED, Attempt 2 (t+5s) FIRED, Attempts 3–8 throttled — consistent with the shown per-profile cap 1.2 alerts/min (ageingRural). LoomFit telemetry trace populated (coldStart / fired / droppedByThrottle rows with timestamps 20:37:08, 20:37:13).
7. **TTS (`tts_logcat.txt`, `03b_announce_tts.png`)** — tapped `Announce to driver (audio + haptic)` (bounds `[88,571][992,703]`, `ui_dump_18.xml`). Evidence classification:
   - (i) **TTS service bind: SUCCESS** — logcat shows `com.google.android.tts` (`TTS.GoogleTTSServiceImp`) processing our request; **zero TTS_SERVICE package-visibility errors** anywhere in `tts_logcat.txt`/`logcat_tail.txt`. The manifest `<queries><action android:name="android.intent.action.TTS_SERVICE"/></queries>` (AndroidManifest.xml:76-78) is doing its job on API 30.
   - (ii) **speak() invocation: CONFIRMED** — `Synthesis request for locale jpn-JPN and name ja-JP-language`, `TTS dispatch: ja-jp-x-jab-server`, then app-side `Utterance ID has started: d9c0b8b0-...` (20:35:09.576) and `Utterance ID has completed` (20:35:19.538) — a full ~10 s utterance lifecycle.
   - (iii) **Package-visibility errors: NONE.**
   - Wrinkles honestly noted: fresh image has no local ja-JP voice — engine logged `The requested voice is not available for this app identifier`, one early `No local or network voice found, failing dispatch`, then fell back to the server voice (`ja-jp-x-jab-server`) and started downloading local voice packs (`Superpack download completed`). The completed utterance is the load-bearing line.
   - **NO audibility claim** — emulator ran `-no-audio`; nothing about actual sound is claimable or claimed.
8. **Airplane-mode probe (`05_airplane.png`, `05b_airplane_top.png`)** — `cmd connectivity airplane-mode enable` → airplane icon visible in status bar; app did NOT crash (`pidof` → 9001; window focus retained; UI renders normally incl. the Japanese compound-failure advisor card 現在地の信頼度: GPS 良好 / 走行を継続). Map-tile blanking under airplane was not specifically exercised (the map was off-viewport during the probe) — honestly unmeasured. Airplane disabled after.
9. **Crash scan** — `logcat_tail.txt` (730 lines): 0 matches for `FATAL|AndroidRuntime.*Exception`.
10. **Shutdown** — `adb emu kill` → OK; device list empty afterwards.

## Defects / observations found (each with artifact)

1. **DEFECT (layout, dignity/readability)**: "Location not yet shared." renders in a ~1-syllable-wide column ("Loca / tion / not / yet / shar / ed.") beside the consent buttons — `02b_location_consent.png`. The consent status label is the single most trust-carrying string on that card and it is visually mangled.
2. **DEFECT-SIGNAL (accessibility)**: `Share my location` / `Use Akita mock (dev)` semantics nodes reported `bounds=[0,0][0,0]` while off-viewport, and even when on-screen are `clickable="false"` (only the whole map card is clickable) — `ui_dump_06/07.xml` vs `ui_dump_14.xml`. A screen-reader/automation user gets a zero-size or non-clickable target for the consent action.
3. **OBSERVATION (walk ergonomics)**: swipes over the map pan the map instead of scrolling the page (dumps 7–12 identical until edge-swipe at x=30) — expected map behavior, but the page's main scroll is easy to lose; noted, not judged.
4. **OBSERVATION**: expected "Japanese consent gate at launch" (per brief) does not exist in this build; consent is the English location-consent card. If a ja-JP launch gate is still the design intent, that is a divergence to review; if the design moved on, the brief's model is stale.
5. **OBSERVATION (label wrapping)**: Threshold-preview label column also wraps one-word-per-line ("Baseline / warning / visibility:") — `05b_airplane_top.png`. Same narrow-label pattern as defect 1, milder impact.

## Artifact inventory (`ladder_out/api30/`)

01_consent_gate.png, 02_map_consent_card.png, 02b_location_consent.png, 02c_after_share_tap.png, 02_main.png, 03_consent_buttons.png, 03_jma_card.png, 03b_announce_tts.png, 04_alerts.png, 05_airplane.png, 05b_airplane_top.png, tts_logcat.txt, logcat_tail.txt, boot_time.txt, emulator_console.log, ui_dump_01..21.xml.

Nothing committed, nothing pushed, no app source modified. `ladder_out/` is untracked output only.
