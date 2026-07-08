# BETA_PLAN — alpha → beta in one month (target gate: 2026-08-05)

**Chair directive (2026-07-08, verbatim)**: *"Turn alpha SNGNav app into beta one … find better way to find better way to find better way to achieve it in a month"* — §12 triple-recursive priority-finding, applied below level by level.

**Mission anchor (OPS-060B)**: beta exists so a real driver in HER cohort holds a
phone that keeps helping when Google Maps fails, GPS degrades, and the snow is
unexpected (D3 worst case; PHIL-001 Driver Test). Beta is a *reach* milestone,
not a feature milestone — built-capability-not-reach is the named failure mode
this plan is shaped against.

---

## Level 3 — the way to find the way to find the way: WHO defines "beta"?

Three candidate evidence-sources were weighed:

| Source | Verdict |
|---|---|
| Our own feature backlog | REJECTED as definition-source — self-referential; measures building, not reach |
| Play-store beta mechanics | NECESSARY, not sufficient — machinery, not value |
| **HER drive-loop, verified on real hardware** | **THE DEFINITION** — beta = a real cohort member can install it through a real channel and the honest drive-loop survives a real (or faithfully simulated) compound failure |

**Beta definition (falsifiable exit criteria — all six, none waivable):**

1. **The drive-loop is device-verified (OPS-066)**: GPS dot → route → in-drive
   hazard alert **HEARD** (ja voice) + **FELT** (haptic) + **SEEN** — on a
   physical Android phone, not the desktop/emulator suite.
2. **Offline survival**: map + alerts survive airplane-mode mid-drive
   (the D3 compound-failure case), device-verified.
3. **A real distribution channel**: release-signed build on the Play internal
   testing track, ≥1 real tester installed *through the channel* (not adb).
4. **The train is wired**: humidity → `WeatherCondition.humidityRH`
   (invisible-ice detection live, not abstaining), the precise ja
   announcements spoken, package pins current.
5. **ja floor on every HER-facing surface** (consent + advisories are done;
   remaining chrome ja-primary), OPS-059 accessibility floor held.
6. **Honesty holds at beta scale**: store/README claims match verified reality;
   a 30-minute drive session crash-free; a visible feedback path (issues link
   in-app). No claim un-seen.

## Level 2 — the way to find the way: HOW gaps close

- **Engine**: a weekly measure → build → device-verify → multi-lens-gate loop.
  Every Friday a gate review (OPS-068 scale clause); red items roll into the
  next week — the *date* moves only if a gate proves the definition wrong.
- **Prioritization rule (OPS-067)**: vision-alignment ranks — "does HER
  drive-loop survive?" — cost only tie-breaks. Nothing is cut to make the
  month; if the month cannot hold all six criteria, the honest output is a
  smaller-but-true beta date, surfaced to the Chair, never a relabeled alpha.
- **Environment honesty**: emulator (AVDs exist: sngnav_obs, sngnav_dot)
  covers SEE + partial voice; **HEAR/FEEL/GPS need the physical device day**
  (Chair's hands). Claims stay env-bound per this repo's standing rule.

## Level 1 — the way: the month, four gates

### W1 — "Wire + See" (gate 2026-07-15)
- [ ] **PREREQ (Chair)**: push SNGNav train + publish
      calibration 0.1.3 → driving_weather 0.4.4 → snow_rendering 0.2.7 →
      pretrip 0.5.1 → vcf 0.4.0 (held, review-clean since 2026-07-08)
- [ ] Bump app pins; `flutter pub upgrade`; suite green
- [ ] Wire JMA humidity → `WeatherCondition.humidityRH` (kills the
      invisible-ice abstention — the app already fetches AMeDAS humidity)
- [ ] Wire `RoadSurfaceState.announcement` / `invisibleBlackIceAnnouncement`
      into the alert + voice path (replaces AlertExplainer flat-certainty ICE
      string on this surface)
- [ ] NSC 0.10.6 (graded ICE/wetIce ja strings, 0.10.x line — the app's
      core ^0.10 wall makes 0.11 unreachable) — release + take it
- [ ] Release signing scaffold (key.properties pattern; keystore = Chair
      secret), version → 0.1.0-beta series, kill hardcoded version strings
      (main.dart shows 'snow_rendering 0.2.5' in 3 places)
- [ ] Emulator OPS-066 pass: GPS dot + alert SEEN, voice attempt logged

### W2 — "Device + Offline" (gate 2026-07-22)
- [ ] **DEVICE DAY (Chair's hands, ~1h)**: docs/DEVICE_VERIFICATION.md
      checklist on a physical phone — HEAR (ja TTS; the TTS_SERVICE manifest
      fix 9aad0d5 is in), FEEL (haptic), GPS real dot, wakelock
- [ ] Offline basemap PoC (d29e017) → default: bundled Akita-region MBTiles,
      airplane-mode drive-loop device-verified
- [ ] Crash boundary + local error log (no telemetry — log stays on device)
- [ ] Fix-list from device day burned down

### W3 — "Channel + ja floor" (gate 2026-07-29)
- [ ] **Play Console internal testing** (Chair account; ~US$25 one-time —
      OPS-067 cost-gate: Chair consent required before spend)
- [ ] Store listing text — honest-bounds style, ja-primary
- [ ] Privacy statement page (truthful: no telemetry, no accounts)
- [ ] Remaining English chrome → ja-primary (OPS-059 floor re-checked)
- [ ] In-app feedback path (issues link on the footer)
- [ ] pretrip_source_* ^0.5.0 republish wave (pre-trip black-ice/bridge-icing
      reach the app's advisory lane)

### W4 — "Harden + Beta gate" (gate 2026-08-05)
- [ ] ≥2 real drive (or drive-simulated walk) smoke sessions, 30 min crash-free
- [ ] Full OPS-068 multi-lens beta-gate review of the app (the same structure
      that gated the 2026-07-08 train)
- [ ] README + store text re-read against verified reality (OPS-062)
- [ ] Tag v0.1.0-beta, promote internal → closed testing, invite HER-cohort
      tester(s) — **beta declared only if all six criteria hold**

## Standing dependencies on the Chair's voice/hands
1. Push + publish the held SNGNav train (W1 prereq).
2. Device day (W2) — physical phone, ~1 hour with the checklist.
3. Play Console account + US$25 (W3) — OPS-067 consent.
4. Beta-tester invitation(s) in HER cohort (W4).

## Ownership (§4)
AAE owns the app + this plan's execution; SDE debug + traps; NDI the JMA
humidity seam; FDD the package releases (NSC 0.10.6, pretrip_source wave);
audit-trio + OPS-068 workflow the weekly gates; VAA-as-SEO coordinates;
the Chair anchors the four dependencies above.

*Plan is a start, not an accomplishment (§12.6). First verified device-day
finding outranks any line in this file.*
