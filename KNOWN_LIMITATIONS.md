# Known limitations

**Rewritten 2026-07-10.** The previous version of this file described the
Slice-0 build (2026-04) and had become false in both directions — it said
map / routing / GPS / alert delivery were "not implemented" and that there
was "no consent flow because there is nothing to consent to", none of which
is true of the current app. The Slice-0 original is superseded; git history
preserves it. This rewrite states what `sngnav-app` does NOT do — or has NOT
yet verified — as of 2026-07-10, so anyone running it does so with eyes open.
<!-- OPS-062 fix 062-1 (scout_full_3 §062 candidates); W3 entry gate -->

## Alpha state — advisory ceiling

The whole app is alpha. It surfaces information; it does not control the
vehicle. The driver remains responsible for all driving decisions. The
drive-caution HUD's ceiling is 「停車の検討」 ("consider stopping") — it never
issues a "turn back" instruction. <!-- README.md:21; main.dart:743-745 -->

## On-device HEAR / FEEL is deferred

The audio + haptic delivery pipeline is wired and the TTS bind + speak path
is verified on an API-30 emulator (zero package-visibility errors), but
whether a driver actually HEARS the spoken line and FEELS the haptic on a
physical phone is **unverified** until the device hour runs
(`docs/DEVICE_VERIFICATION.md`). A fresh Android image may also lack a
**local Japanese TTS voice** — the emulator's confirmed utterance rode a
server-voice fallback, which offline would be silence. The device checklist
verifies a local voice; tester/store text states the dependency honestly.
<!-- README.md:23,25; BETA_PLAN.md:160-165 -->

## Device matrix is N=1 + emulators

Beta verification targets one (N=1) physical device plus an emulator
API-level spread (30/34/36). As of 2026-07-10 the API-30 emulator has run a
full walk (consent → live JMA fetch → watch row → alerts → airplane mode;
`ladder_out/FINDINGS.md`); API 34/36 are honestly skipped so far; the
physical-device hours are still ahead. "Works on HER cohort's phones" is
not claimable from this matrix, and no text in this repo claims it.
<!-- BETA_PLAN.md:30-32,127-134 -->

## Ice-mission verification waits for first snow (~2026-11)

The app's central promise — warning about invisible road ice — cannot be
verified against real frozen roads until Akita's first snow, around
November 2026. Until then, only the drive-loop (map, GPS, HUD, alert
delivery, offline survival) can be verified. **The drive-loop claim and the
ice-mission claim are never conflated.** <!-- BETA_PLAN.md:34-38; README.md:27 -->

## Verbatim relay + labeled derivation only (気象業務法 boundary)

JMA observation fields are surfaced as **verbatim relay** — what JMA
published, unmodified. The 路面凍結ウォッチ (invisible-ice watch) is a
**derived inference** (the catalog's shared radiative-frost classifier run
over the measured fields), labeled as such in the UI — never presented as a
JMA statement. Missing fields read 判定不能 ("cannot judge"), never "clear".

The boundary: geographic aggregation and clearly-labeled derivation from
current observations are operation-class (e)/(β) under the AAA Article 17
check. Time-shifted derivation ("may freeze in 2 hours") and
cross-source-fused prediction would require a forecasting permit
(予報業務許可) under 気象業務法 第十七条 and are **not in scope** until that
path is opened. No forecasting anywhere in the app.
<!-- main.dart:1526-1529; README.md:15 -->

## Corridor is 5 hardcoded stations — not route-aware

The corridor weather panel shows 5 hardcoded JMA AMeDAS stations along
Akita prefecture's main inhabited spine (秋田・大曲・横手・湯沢・男鹿), each
verbatim with its own observation timestamp, each failure isolated. The
stations do NOT dynamically follow a drawn route; adjacent prefectures are
not covered; there is no request batching/caching layer for many concurrent
users. <!-- jma_fetch.dart:24,48 -->

## Routing is NOT snow-aware; the OSRM demo router is not for production

The route panel calls the OSRM public demo server
(`router.project-osrm.org`) with coordinates the user taps, and draws the
returned polyline. That polyline reflects **road network connectivity
only** — it does not know whether a pass is closed for the season, whether
plows have run, whether snow depth exceeds clearance, or whether the route
crosses a chain-required zone. The driver assesses all of that. The OSRM
demo server is rate-limited, has no SLA, and is suitable for personal
testing, NOT production navigation.

Maneuver narration speaks the NEXT maneuver from the drawn route; there is
no deviation detection and no automatic recompute-on-deviation. The reroute
advisor **decides** (suggests) — it never re-routes on its own.
<!-- services/maneuver_narration.dart:19; services/reroute_advisor.dart:1-5 -->

## Spoken-language bounds

The drive-HUD spoken lines and the ice-watch announcement follow the device
locale (Japanese / English). The **condition-explainer announcement** is
driver-profile-bound: it speaks the catalog's explainer verbatim in the
profile's language — English on the foreign-tourist profile — regardless of
device locale. This is a scoped bound, not a blanket "Japanese-only" app.
<!-- Locale-following HUD/watch lines per the W3 locale fix landing in this
     same change-set (BETA_PLAN.md:219-224); explainer profile binding:
     main.dart:999 (explainer.localeTag). Re-verify at the W4 re-read. -->

## Remaining English chrome

The consent, advisory, and watch surfaces are Japanese-first
(locale-following). App chrome outside those surfaces is still partially
English; the ja floor (C5) is in progress and is not rescope currency.
<!-- README.md:25; BETA_PLAN.md:92-94,218 -->

## GPS honesty; no background location

Location is opt-in (deny-by-default consent card with a data-flow
disclosure), foreground-only by design — no `ACCESS_BACKGROUND_LOCATION` is
requested. The position dot carries a finite-position guard and degrades
honestly (dead-reckoning → `lost`) rather than showing a confidently-wrong
dot. There is no vehicle-bus (CAN/OBD) integration; sensor-grade dead
reckoning is out of scope for this app today.
<!-- AndroidManifest.xml:6-8; README.md:23 -->

## Dev-only mock GPS button still ships

A 「秋田のモック位置（開発用）」 / "Use Akita mock (dev)" button injects a fixed
position at Akita station so the position UX can be tested without GNSS
hardware. The mock dot is **amber**, its status line says it is not real
GPS, and it cannot be mistaken for the blue real-GPS dot. The button is not
yet compiled out of release builds; tester text explains it honestly.
<!-- main.dart:1609-1613; app_localizations.dart:59-60,71-73 -->

## Offline map bounds

The bundled offline basemap carries real OpenStreetMap cartography for
Akita prefecture (z8–z12; z13 in Akita city and rural-selective within the
prefecture), minimal style — roads / rail / rivers / lakes / coastline / ja
labels; no buildings or POIs. © OpenStreetMap contributors, ODbL. Uncovered
tiles fall back to network tiles. Verified in a hermetic offline widget
render AND an emulator airplane-mode pass (2026-07-10); **device-hour
confirmation is still ahead**, and the tunnel span is verified in host
tiles, not yet walked on-device. <!-- README.md:25; BETA_PLAN.md:177-190 -->

## No telemetry; local crash log only

No telemetry, no accounts, no analytics/ads SDKs. Uncaught errors append to
a local, size-capped (~200 KB) on-device log that leaves the phone ONLY via
the user-initiated 「ログを共有」 share action. <!-- lib/services/error_log.dart:9-15 -->

## JMA fetch failure surfaces explicitly

If a JMA endpoint is unreachable, the app shows the explicit failure
reason. It does NOT silently fall back to cached or stale data displayed as
fresh — staleness must be visible to the driver.

## What this means for someone running it

You can run it, look at real Akita observations, watch the labeled
invisible-ice inference, draw a route, and drive with the caution HUD — 
knowing that on-device audio/haptic verification and the real-ice field
verification are still ahead, on the dates stated above. If the JMA fetch
fails on your network, you'll see the failure honestly. If you spot
something that seems wrong, please open an issue — silent gaps are a worse
failure than acknowledged ones.
