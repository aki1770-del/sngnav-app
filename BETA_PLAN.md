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
| A6. Beta-tester conversation STARTS (not "invite at the end") | 2026-07-22 | Komada-as-tester is the floor (N=1 tester, said honestly) |

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

**Mid-month checkpoint (fix #7) — 2026-07-22, decision rule written down:**
count criteria with evidence-or-clear-path. ≥4 of 6 → GO (finish the month).
<4 → RESCOPE with the Chair same-day: either shrink the beta definition
HONESTLY (e.g., "internal beta, N=1 tester, device-matrix N=1") or move the
date; never relabel. This is the §11 measure applied to the plan itself.

**Weekly gate protocol (fix #7)**: Friday, ~30 min: re-read this scoreboard
against evidence, run the OPS-068 review scaled to the week's diff (full
multi-lens only for safety-class changes), log the gate verdict in this file's
history section, roll reds forward visibly.

**Batched publish sessions (fix #6)**: package releases queue in a PENDING
PUBLISH list here; the Chair publishes in ONE sitting per batch (A3), each
followed by the 062(C) live-version assert. No scattered per-package asks.

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
- [ ] Emulator ladder pass #1 (API 30/34/36, screenshots affirmed)
- [ ] NSC 0.10.6 STAGED (graded ICE/wetIce ja strings, 0.10.x line) → PENDING PUBLISH (A3)

### W2 → gate Fri 2026-07-18
- [ ] Device hour #1 evidence processed; fix-list burned (A2)
- [ ] Play internal track created + first signed build uploaded (A4)
- [ ] Offline basemap PoC → default (bundled Akita MBTiles); emulator airplane-mode pass
- [ ] Crash boundary + on-device local error log
- [ ] pretrip_source ^0.5.0 wave STAGED → PENDING PUBLISH (A3)

### CHECKPOINT Tue 2026-07-22 — GO / RESCOPE (rule above)

### W3 → gate Fri 2026-07-25
- [ ] Remaining English chrome → ja-primary; OPS-059 floor re-audit (C5)
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

## Gate history
- 2026-07-09 (v2 adoption): C4 ✅. W1 substantially complete 2 days early;
  emulator ladder + NSC 0.10.6 staging are the W1 remainder.

## Ownership (§4)
AAE owns the app + execution; SDE debug + traps; NDI the JMA seam; FDD the
package releases; audit-trio + OPS-068 the gates; VAA-as-SEO coordinates;
the Chair anchors the Chair-hands register (A1–A6).

*Plan is a start, not an accomplishment (§12.6). First verified device-day
finding outranks any line in this file.*
