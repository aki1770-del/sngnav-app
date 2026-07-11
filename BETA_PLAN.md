# BETA_PLAN v2 — alpha → beta in one month (target gate: 2026-08-05)

**Chair directive (2026-07-08, verbatim)**: *"Turn alpha SNGNav app into beta one … find better way to find better way to find better way to achieve it in a month"* — §12 triple-recursive priority-finding.
**v2 (2026-07-09)**: Chair-directed self-review of the method (*"find some improvement point of view … go ahead and improve"*). Nine weaknesses found in v1; every one is fixed in the structure below. v1's level-3/level-2 derivation stands (beta = HER drive-loop verified on real hardware through a real channel); what changed is HOW the month runs.

**Mission anchor (OPS-060B)**: beta exists so a real driver in HER cohort holds a
phone that keeps helping when Google Maps fails, GPS degrades, and the snow is
unexpected (D3 worst case; PHIL-001 Driver Test). Beta is a *reach* milestone,
not a feature milestone.

---

## The beta definition (unchanged from v1 — falsifiable, all six, none waivable)

## Criteria scoreboard (v2 fix #1: continuous burn-down, not a big-bang W4 gate)

Each criterion turns ✅ the moment its evidence exists, with the evidence
linked HERE. W4 is *confirmation*, not first measurement. A criterion with no
plausible path by the mid-month checkpoint triggers the rescope rule below.

| # | Criterion | Status | Evidence |
|---|---|---|---|
| C1 | Drive-loop device-verified: HEAR (ja voice) + FEEL (haptic) + SEE (GPS dot, alert) on a physical phone (OPS-066) | ⬜ | — |
| C2 | Offline survival: map + alerts through airplane-mode mid-drive, device-verified | ⬜ | — |
| C3 | Real channel: release-signed build on Play internal testing; ≥1 tester installed via the track | ⬜ | — |
| C4 | Train wired: JMA humidity → invisible-ice watch live; ja announcements spoken; pins current | ✅ | commit `67e1eb8` (watch + verbatim announcement + honest-unknown row; 205/205; APK builds). On-device HEAR of it → C1 |
| C5 | ja floor on every HER-facing surface + OPS-059 accessibility floor | ⬜ | consent + advisories + watch row done; chrome audit owed |
| C6 | Honesty at beta scale: claims match verified reality; 30-min crash-free session; in-app feedback path | ⬜ | — |

**Device-matrix honesty (v2 fix #9)**: beta will be verified on N=1 physical
device + an emulator API-level spread (30/34/36). The beta notes MUST say so —
"works on HER cohort's phones" is not claimable from N=1.

**Season honesty (2026-07-09 audit, VPM doubt #2)**: the gate lands in August;
the app's central ice promise cannot fire in Akita until ~November. The beta
declaration MUST carry: "drive-loop verified; ice-mission verification
scheduled for first snow, ~2026-11" — the drive-loop claim and the
mission-loop claim are never conflated.

**Chair ratification (2026-07-09, verbatim): the downpour/typhoon surface IS
in scope.** *"yes. it is good to proceed in august because we are in a turmoil
atmosphere and it means we do not assume but measure the actual weather. Not
our historical data. Sakichi vision says measure first. pull andon when you
broke thread. ask why it happened. Think deeply about root cause. Once you
find root cause you are allowed to proceed. Do not proceed when no root cause
surfaces. VAA is reponsible for that process overall."*
Two bindings follow: (1) the W3 turmoil surface is built on MEASURED actual
weather — live JMA observations (the measured `precipitation10m`/wind fields
already wired) + live JMA warnings — never on historical/seasonal assumption;
(2) the beta arc runs under the stop-and-root-cause gate below, VAA-owned.

**Claim boundary (TFA condition 1)**: beta text may claim phone-reach on the
verified matrix ONLY — never the PHIL-001 IVI-hardware rung, whose
Destination-Re-anchoring Andon stays held until a measured rung renders on
real embedded hardware.

## Method mechanics (v2 fixes #2–#8)

**Chair-hands register (fix #2) — every Chair dependency is a dated ask with a
fallback, not ambient background:**

| Ask | Needed by | Fallback if slipped |
|---|---|---|
| A1. `vehicle_condition_fusion 0.4.0` publish (command in W1 box) | 2026-07-11 | app beta unaffected (monorepo lane only) — publish batches with A3 |
| A2. **Device hour #1 (early smoke)** — current APK: HEAR/FEEL/GPS checklist §1 | 2026-07-15 | emulator ladder covers SEE + voice-pipeline; C1 stays ⬜ and the 07-22 checkpoint decides |
| A3. **Batched publish session** — NSC 0.10.6 + pretrip_source wave + anything staged (one sitting, commands listed by me) | 2026-07-18 | app ships beta on current published versions; graded-ICE string slips to post-beta |
| A4. Play Console account + ~US$25 (OPS-067 consent) | **2026-07-15** (moved UP from W3 — external review latency, fix #5) | no channel → C3 unmeetable → rescope rule fires at checkpoint |
| A5. Device hour #2 (full drive-loop + airplane-mode) | 2026-07-29 | C1/C2 partial from hour #1 evidence; beta date honesty-adjusted |
| A6. **The tester question — "who is she, by name, and has she said yes?"** (VPM doubt #1: the board's own diagnosis is downstream-pull; this is the plan's ONLY pull item — it gets criterion-grade falsifiability, not a soft verb). **Voice Mission extension (Chair-ratified 2026-07-11)**: the tester conversation carries `docs/listening_guide_ja.md` — the live-voice listening protocol; the first insights-ledger entry is a deliverable of the same conversation (docs/VOICE_MISSION.md binding sequence: voice design waits for the first live voice) | **asked by 2026-07-14, answered by 2026-07-18** | Komada-as-tester is the floor (N=1, said honestly) — and if no real HER-cohort human is reachable by 07-22, THAT finding surfaces to the Chair at the checkpoint as a finding, not a footnote |

**Verify-early-verify-late (fix #3)**: hardware verification is decoupled from
feature completion — device hour #1 runs on whatever the APK does TODAY;
hour #2 confirms the full loop. The physical hours spend ONLY on what needs
hardware (haptic feel, real TTS audibility, real-sky GPS, wakelock-in-car);
everything else moves to the emulator ladder.

**Emulator ladder (fix #4) — runs BEFORE any device hour, no Chair hands:**
AVDs exist locally (`sngnav_obs`, `sngnav_dot`). Ladder: boot API 30 + 34 + 36
→ install APK → scripted walk (consent → JMA fetch → watch row → fire alert →
TTS attempt logged) → screenshot each state → OPS-066 affirm the renders.
API-level spread exists precisely because the TTS_SERVICE-class bug
(Android-11+-only package-visibility) is invisible on old APIs.

**Mid-month checkpoint (fix #7; tightened by the 2026-07-09 vision audit) —
2026-07-22, decision rule written down:** count criteria with EVIDENCE only —
"clear path" is struck (it is a story the pen tells itself; the narration
seam VPM and TFA independently named). A criterion with zero evidence on
07-22 counts red regardless of its story. The count gets a SEPARATED READ
(ORS or Vice-SEO) beside the plan-author's own — the author does not solely
grade its own ≥4/6. ≥4 of 6 → GO (finish the month). <4 → RESCOPE with the
Chair same-day: shrink the beta definition HONESTLY (e.g., "internal beta,
N=1 tester, device-matrix N=1") or move the date; never relabel. **C5 (ja
floor) and the OPS-059 accessibility floor are NOT rescope currency** (AAA
F2): only date, tester-count, and device-matrix may shrink.

**Stop-and-root-cause gate (Chair-voice 2026-07-09; VAA owns the process):**
any broken thread in the beta arc — a red suite, a device-hour failure, a
false claim caught, a tester-reported defect — STOPS that lane (Andon), gets
asked WHY to root cause (5-Whys, measured not narrated per §11), and the lane
may proceed ONLY once a root cause has surfaced. No root cause surfaced = no
proceed; the stop and the root cause are both logged in the gate history.

**Weekly gate protocol (fix #7)**: Friday, ~30 min: re-read this scoreboard
against evidence, run the OPS-068 review scaled to the week's diff (full
multi-lens only for safety-class changes), log the gate verdict in this file's
history section, roll reds forward visibly. **Standing test before any review
round beyond the first (VPM doubt #4): "could a device-hour or a tester
answer this question instead?" If yes, the empirical hour outranks the review
round — sibling verifiers cannot supply a stranger's hour with the phone.**

**Batched publish sessions (fix #6)**: package releases queue in a PENDING
PUBLISH list here; the Chair publishes in ONE sitting per batch (A3), each
followed by the 062(C) live-version assert. No scattered per-package asks.

**Roadmap honesty — Play production access (recorded 2026-07-11, VAA-led
Android research; AAE+TFA+AAA converged):** this beta needs only the internal
track (no prerequisites) → closed testing; C3 is compatible with N=1 tester.
Google Play PRODUCTION access for a new personal account requires **12
testers opted-in continuously for 14 days** on closed testing
(support.google.com/googleplay/android-developer/answer/14151465, read
2026-07-11). That is a ~2027 question answered by November field evidence,
NOT a beta goal. **Standing adoption tripwire (OPS-067/061):** any artifact
that states a tester/install count as a TARGET, recruits testers outside
HER-cohort/family/serving-edge-developers, or proposes tester-exchange/farm
services → Andon + Vice-SEO separated read before any Chair surfacing. Safe
harbor: Komada-as-tester N=1, said honestly. If production ever becomes
foreseeable, prefer an organization account at creation time.

**Feedback path shaped for HER cohort (fix #8)**: not GitHub-issues-only. W3
adds a one-tap **"ログを共有" (share log)** action — user-initiated share-sheet
export of the local error log (consent-preserving; no auto-telemetry, no
accounts). A beta tester sends feedback the way she sends a photo.

## The month (re-sequenced)

### W1 → gate Fri 2026-07-11 (was 07-15; the wiring landed early)
- [x] Train published (4/5 live, 062C-verified) + app pins current
- [x] Invisible-ice watch + verbatim ja announcement + honest-unknown row (`67e1eb8`)
- [x] Release-signing scaffold + version-rot loom (`6b7179e`)
- [x] CI green incl. env-honest render_see (`b2b6649`)
- [x] Emulator ladder pass #1 — **API 30 FULL WALK RAN** (CT 2026-07-09;
      VAA own-eyes-reviewed the renders; ladder_out/FINDINGS.md): install ✓,
      live JMA fetch ✓ (秋田 26.7°C/71%, 該当なし correctly), throttle 2/6 ✓,
      TTS bind+speak CONFIRMED with ZERO package-visibility errors (the
      9aad0d5 manifest fix works on API 30; no audibility claim, -no-audio),
      airplane-mode no-crash ✓, 0 FATAL. API 34/36 SKIPPED honestly (images
      not installed; persistent SDK now at /home/komada/android-sdk so the
      wipe-loss cannot recur — android-34 image re-enables 4 existing AVDs).
- [ ] NSC 0.10.6 STAGED (graded ICE/wetIce ja strings, 0.10.x line) → PENDING PUBLISH (A3)

### W2 → gate Fri 2026-07-18
- [ ] Device hour #1 evidence processed; fix-list burned (A2)
- [x] **Ladder fix-list — BUILT by CT, VAA own-eyes-audited, landed
      2026-07-09**: (a) consent status line reflowed full-width above its
      buttons (ja render SEEN: one dignified sentence) + liveRegion
      semantics; (b) the a11y "zero-size consent targets" claim was
      REFUTED by CT's measurement (standard hidden-semantics for
      scrolled-out nodes — FINDINGS.md correction appended) and a
      semantics-floor test pins the contract anyway; (c) shared _kv
      narrow-label pattern fixed adaptively (threshold render SEEN:
      word-boundary wrap). Audit note: the same render shows core 0.10.5's
      flat-certainty 凍結路面です still live — fresh visual proof of what
      the staged NSC 0.10.6 publish buys. ORIGINAL ITEM: (a) consent-card label
      column mangles its most trust-carrying line one-syllable-per-line
      ("Loca/tion/not/yet/shar/ed." — 02b_location_consent.png) and the
      路面凍結ウォッチ label wraps mid-word — widen/reflow the label column;
      (b) **OPS-059 correction-class**: consent actions report zero-size /
      non-clickable semantics to assistive tech (ui_dump evidence) — real
      Semantics targets before any tester; (c) threshold-preview labels
      same wrap class. (Consent-gate "regression" REFUTED by measurement:
      the card is locale-following — ja on HER ja-locale phone; the
      emulator ran en. The brief overstated the README claim — VAA's
      brief-authoring error, recorded.)
- [ ] **TTS offline-voice check (D3-load-bearing ladder finding)**: fresh
      API-30 image had NO local ja voice — the confirmed utterance rode a
      SERVER voice fallback (ja-jp-x-jab-server). On HER offline worst case
      that is silence. Device hours must verify a LOCAL ja voice is
      installed (Settings→TTS→download offline ja) and DEVICE_VERIFICATION
      gains that step; the beta notes state the dependency honestly.
- [ ] Play internal track created + first signed build uploaded (A4)
- [x] **Offline basemap → default with REAL cartography (built 2026-07-10)**:
      placeholder grid replaced by a real-OSM render — Geofabrik Tohoku
      extract → tool/extract_akita.py (273k line features, 9.4k water polys,
      65 ja place labels) → tool/render_akita_mbtiles.py (965 tiles, Akita
      pref z8–z12 + city z13, palette-quantized 10.1MB, © OpenStreetMap
      ODbL). Hermetic offline widget render SEEN (render_out/
      05_offline_map_akita.png: real 秋田市 street grid + coastline +
      rivers + labels, zero network); 217/217 tests green. REMAINING:
      emulator airplane-mode pass with the real tiles (fold into the next
      ladder run / device hour).
- [x] **Emulator airplane-mode pass on the real offline basemap — RAN
      2026-07-10, and it caught exactly what it existed to catch** (evidence:
      ladder_out/FINDINGS.md appended section + api30_offline_v2/): the
      offline map had NEVER rendered on the Android engine — (1) missing
      bundled native sqlite (no sqlite3_flutter_libs) made MbTiles() throw,
      silently swallowed → map BLANK in airplane mode on-device while every
      host test painted it; (2) launch-race: tiles created before the async
      provider load never reload on provider swap → cold-start viewport
      stayed grey until a far pan. Both FIXED same-turn (dependency +
      honest failure log + TileLayer remount key). Cold-offline start now
      paints 秋田市 at first sight: sea fill, 雄物川 bridge casings,
      国道7/13 plates, E7 green, 県道56/62 hexagons, unverified grey. 0
      FATAL. Honest bounds: emulator not device (HEAR/FEEL/GPS = device
      hour); tunnel span verified in host tiles, not walked on-device.
- [x] **Tohoku-extract deep dive + vision-alignment gate (2026-07-10,
      Chair-ratified composite)** — gate record:
      `../outputs/audits/vision_alignment_tohoku_extract_deep_dive_2026_07_10.md`.
      LANDED: 田沢湖/relation-lakes fix + cut pin (PP1+PP6); rural selective
      z13 within 秋田県 boundary (PP4: 629 z13 tiles, asset 16.22MB — Chair
      size-gate "meaningfully under +14MB" met at +6.06MB). QUEUED W3: route
      shields (PP3). HOLDS recorded: sea-fill (PP2, tripwire), bridge/tunnel
      styling (PP5-i), bridge-icing-from-raw-OSM (PP5-ii, unanimous —
      cry-wolf risk), bbox-clip restraint (PP7).
- [x] Crash boundary + on-device local error log (LocalErrorLog, size-capped, no network — the read surface for W3's ログを共有; 5 tests)
- [ ] pretrip_source ^0.5.0 wave STAGED → PENDING PUBLISH (A3)

### CHECKPOINT Tue 2026-07-22 — GO / RESCOPE (rule above)

### W3 → gate Fri 2026-07-25
- [ ] **Turmoil surface (Chair-ratified 2026-07-09): measured downpour/typhoon
      in-drive caution** — live JMA measured fields (precipitation10m, wind)
      + live JMA warnings drive it; same honesty grammar as the ice watch
      (derived-and-labeled, possibility-graded, abstain-on-missing → 判定不能,
      transition-gated). The August tester tests a surface the season can
      actually fire. NO historical/seasonal assumption anywhere in the gate.
- [ ] **ENTRY GATE (CT's load-bearing correction): OPS-062 claims-vs-reality
      pass runs BEFORE first tester contact** — README front door, store
      text, in-app captions re-read against verified reality. (Two defects
      the audit already caught are fixed as of 2026-07-09: the false
      "no derivation" caption under the derived watch row; the 0.4.1-era
      README front matter.) W4's re-read remains as confirmation.
- [ ] Remaining English chrome → ja-primary; OPS-059 floor re-audit (C5)
- [ ] **Locale-aware spoken alerts (AAA F1, correction-class)**: announce
      paths currently hardcode ja while enSpokenText parity sits published
      one import away — select spoken line + localeTag by locale, or bound
      it explicitly ("spoken alerts are Japanese-only in this beta") in the
      store text and beta notes. The eyes-off channel must not silently
      degrade for a named cohort.
- [ ] "ログを共有" share-log feedback action (C6)
- [ ] Store listing (honest-bounds style, ja-primary) + privacy statement page
- [ ] Tester onboarding text (ja); A6 conversation concluded

### W4 → gate Tue 2026-08-05
- [ ] Device hour #2: full drive-loop + airplane-mode (C1, C2 confirmation)
- [ ] ≥2 smoke sessions, 30-min crash-free (C6)
- [ ] Full OPS-068 multi-lens beta-gate review of the app
- [ ] README + store text re-read against verified reality (OPS-062)
- [ ] Tag v0.1.0-beta; internal → closed testing; tester(s) invited
- [ ] **Beta declared ⇔ scoreboard all ✅** (or the honest smaller declaration from the checkpoint)

## PENDING PUBLISH (batch for A3)
*(commands appended here as packages stage; each publish is followed by the
062(C) live-version assert)*
- `vehicle_condition_fusion 0.4.0` — `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/SNGNav/packages/vehicle_condition_fusion`
- `navigation_safety_core 0.10.6` (graded ICE/wetIce, 0.10.x line; staged from
  the released 0.10.5 source at `/home/komada/work/nsc-0.10.6`; 304/304 tests,
  analyze clean, dry-run 0 warnings) —
  `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/work/nsc-0.10.6`
  *(after publish, sngnav-app takes it with a plain `flutter pub upgrade` —
  its `^0.10.0` pin admits 0.10.6)*
- `pretrip_source_digitraffic 0.2.3` + `pretrip_source_jma 0.2.1` +
  `pretrip_source_met_norway 0.2.2` (constraint-widen to pretrip ^0.5.0;
  staged + committed SNGNav `16aa60c`; analyze/tests/dry-run clean) —
  `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/SNGNav/packages/pretrip_source_digitraffic`
  `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/SNGNav/packages/pretrip_source_jma`
  `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/SNGNav/packages/pretrip_source_met_norway`
- `condition_aggregator_jma 0.4.0` (W3 turmoil widening — 9 downpour/typhoon/
  thunder/fog classes + 危険警報→extreme rung; committed SNGNav `f0fbadd`;
  2-round multi-gate panel READY-TO-REPUBLISH; 71/71 tests, analyze clean,
  dry-run 0 warnings) —
  `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/SNGNav/packages/condition_aggregator_jma`
  *(after publish, VAA lifts the sngnav-app pin `^0.3.0` → `^0.4.0` — the
  荒天ウォッチ warnings lane's supply line; recorded serve-decision in the
  0.4.0 CHANGELOG + board §B)*
- `nav2_safety_layer 0.1.3` (staleness repair: widens the core constraint to
  `>=0.10.0 <0.12.0` — the published `^0.10.0` blocks co-consumers from the
  core 0.11 line; suite run at BOTH bounds 12/12; committed SNGNav `581e990`;
  panel READY-TO-REPUBLISH zero MUST) —
  `PUBLISH=1 bash /home/komada/SNGNav/scripts/publish-from-target-dart.sh /home/komada/SNGNav/packages/nav2_safety_layer`

## Gate history
- 2026-07-09 (ladder return): W1 emulator item CLOSED as API-30-full +
  34/36-honest-SKIP. Stop-and-root-cause note: the ladder stalled once
  (agent continuation died after boot); root cause = watcher fired into a
  dead continuation + adb absent from PATH; resumed with absolute paths;
  persistent SDK root removes the original wiped-/tmp cause. Proceeded
  only after both causes surfaced (Chair's 2026-07-09 discipline).
- 2026-07-09 (v2 adoption): C4 ✅. W1 substantially complete 2 days early;
  emulator ladder + NSC 0.10.6 staging are the W1 remainder.

## Ownership (§4)
AAE owns the app + execution; SDE debug + traps; NDI the JMA seam; FDD the
package releases; audit-trio + OPS-068 the gates; VAA-as-SEO coordinates;
the Chair anchors the Chair-hands register (A1–A6).

*Plan is a start, not an accomplishment (§12.6). First verified device-day
finding outranks any line in this file.*
