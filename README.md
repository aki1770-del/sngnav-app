# sngnav-app

Alpha-stage navigation companion for snow-zone commuting in Hokkaido / Tohoku, Japan.

## What this is

The first edge-developer use of the [navigation_safety_core](https://pub.dev/packages/navigation_safety_core) package family from pub.dev. Built by the same team that ships those packages — eating our own dog food while learning what fails.

Alongside the safety stack above, the app also includes the original integrator demos (package versions resolve per `pubspec.lock` — the copy below names packages, never pins):

- A `DriverProfile` selector wired to `AlertDensityThrottle` from `navigation_safety_core`
- The throttle's per-profile cap visualized — fire 8 sequential alerts, see which fire and which throttle for the selected profile
- A `RoadSurfaceConditionGlossary` panel showing per-profile vocabulary (kanji-native for ageing-rural, simplified for foreign-tourist, etc.)
- Real-data fetches from JMA AMeDAS — current observation at the Akita-shi station (32402) plus a five-station corridor: temperature, humidity, wind, snow depth, 10-min precipitation, observation time
- **路面凍結ウォッチ (invisible-ice watch)** — the measured JMA fields run through the catalog's shared radiative-frost classifier; when the clear-morning black-ice window is detected the app **shows** the possibility-graded ブラックアイスバーン line and emits it to the offline voice lane, whose audio ships in the APK (a derived inference, labeled as such — never presented as a JMA statement). **The speaking is wired, not heard: no human has yet heard this app speak** — the one "confirmed" TTS run was a muted emulator binding a network voice. See "What this is NOT" below and `BETA_PLAN.md` C1/C4. The row never fabricates an all-clear: a field the station did not report reads 判定不能 ("cannot judge"), a reading the model declines to judge reads 判定範囲外 ("outside the judged range"), and below 0 °C a dropped precipitation leaf still raises 路面凍結のおそれ rather than falling silent

The default profile is `ageingRural`. The default station is Akita. Both choices are deliberate — the first customer we serve is the most-vulnerable cohort member.

## What this is NOT

**This is alpha software in active development.** It is not for production navigation. The driver remains responsible for all driving decisions. The app surfaces information; it does not control the vehicle.

It now carries a map (offline-first: bundled real-OSM Akita basemap, network tiles as fallback), GPS self-positioning (with a finite-position guard and honest dead-reckoning → `lost` degradation — never a confidently-wrong dot), routing (**road-network connectivity only, and snow-blind**: the route comes from the public **OSRM demo server** (`router.project-osrm.org`) — rate-limited, no SLA — and it does not know whether a pass is closed for the season, whether plows have run, whether snow depth exceeds clearance, or whether the route crosses a chain-required zone; **this is not production navigation**, and on a winter road that judgement stays with the driver — see `KNOWN_LIMITATIONS.md`), a live compound-failure drive-caution HUD (走行を継続 / 停車の検討), the 路面凍結ウォッチ invisible-ice watch (measured JMA temperature + humidity + precipitation through the catalog's shared radiative-frost classifier — a labeled derived inference that abstains honestly on missing fields), audio + haptic alert delivery (TTS bind + speak verified on an API-30 emulator with zero package-visibility errors; **HEAR/FEEL on a physical device still pending** — see `docs/DEVICE_VERIFICATION.md`), a deny-by-default, locale-following consent card (Japanese on a Japanese-locale device) with a data-flow disclosure, an on-device crash log (size-capped, never leaves the phone), and JMA/NWS advisory cards (JMA-first for a Japanese driver). No telemetry. No real-user beta yet. No vehicle control.

**Honest current limitations:** the emulator has verified SEE (full walk on API 30: consent → live JMA fetch → watch row → alerts, screenshots in `ladder_out/`) and the TTS *pipeline*; **HEAR and FEEL on a physical phone are still unverified**, and a fresh Android image may lack a local Japanese TTS voice (the emulator's utterance rode a server-voice fallback — offline, that would be silence; the device checklist now verifies a local voice). The offline basemap is now the **default map path** and carries **real OpenStreetMap cartography** (Akita prefecture z8–z12; z13 in Akita city AND prefecture-wide wherever a major road or town runs — rural deep-zoom parity; minimal style — roads/rail/rivers/lakes/coastline/ja labels; no buildings or POIs; © OpenStreetMap contributors, ODbL, Geofabrik cut tohoku-260709): covered tiles render from the bundled archive with no network, uncovered tiles fall back to network tiles. Verified in a hermetic offline widget render (`render_out/05_offline_map_akita.png`) AND an emulator airplane-mode pass (2026-07-10, `ladder_out/FINDINGS.md`) — a pass that caught two real defects (a missing bundled native sqlite library and a tile-load launch race) that had kept the offline map from ever rendering on the Android engine; both are fixed, and a cold-offline start now paints 秋田市 at first sight. On-device (physical phone) confirmation is still ahead with the device hour. App chrome outside the consent + advisory + watch surfaces is still English (ja floor scheduled).

The target was two-staged and dated (see `BETA_PLAN.md`): a **beta gate on 2026-08-05** verifying the drive-loop on real hardware through a real distribution channel, and **ice-mission verification at first snow (~November 2026)**, when real testers in HER's cohort measure the invisible-ice watch against real frozen roads.

**That first gate has passed unmet.** Measured 2026-08-06, the day after: the scoreboard stands at **0 of 6 criteria met** (C2 and C4 partial; C1, C3, C5, C6 not started). No physical device has run the drive-loop, and no distribution channel exists — so **there is no beta program running, and there are no testers.** The plan's own rescope rule (fewer than 4 of 6 → rescope with the Chair, same day) has not fired, and the rescope is owed; the plan forbids relabeling in its place. Until that record is written, treat every date in `BETA_PLAN.md` as unmet rather than pending.

## How to run

```sh
git clone https://github.com/aki1770-del/sngnav-app
cd sngnav-app
flutter pub get
flutter run
```

The JMA fetch happens on app start; the first observation appears within a few seconds. Tap "Fire 8 sequential warning alerts" to watch the throttle behavior for the selected profile.

If JMA fetch fails (network, endpoint changes, etc.) you'll see an explicit error — never silent fallback to displayed-as-fresh stale data.

## Provenance

This repository is part of the SPA Actuator unit's work — a governance-disciplined human + AI collaboration shipping the SNGNav package family. The `navigation_safety_core` package is on pub.dev; the [spa-ai](https://github.com/aki1770-del/spa-ai) tool ships build-time looms with the same vocabulary used here.

Per the tradition Sakichi Toyoda set: the first customer for invention is a named person in your own household. We started with HER's mother at her Akita weather station.

## License

BSD 3-Clause (matches the navigation_safety_core package).

## Honest disclosure

If you spot something wrong — a calculation that seems off, a JMA reading that doesn't match what you see out your window, an alert that fired when it shouldn't have — please open an issue. Silent gaps are a worse failure than acknowledged ones.
