# sngnav-app — Encountered Traps

**Owner**: SDE (sngnav-debug-engineer) per CLAUDE.md §4 + §8 ownership cascade
**Ratification**: D-VGC176-1 (Recovery plan v0; Komada-voice 2026-04-29 evening JST)
**Class**: trap log — pre-flight checklist for every new slice
**Status**: v0.1 seeded 2026-04-29 evening JST by SDE-as-author spawn

## Komada-voice authorization (verbatim, 2026-04-29 evening JST)

> *"My ORDER: start today. DO NOT WORRY ABOUT making mistakes. INSTEAD try anyway. IF you are not fully aware you see, use loupe, glass, or camera."*

The "loupe / glass / camera" instruction operationalizes V77 genchi-genbutsu and OPS-RULE-036 Verify-First: the trap log is the loupe SDE applies before each new slice declares done.

## Why this file exists (V92 origin)

Failure modes that bit the unit on Slice 2/3 of sngnav-app + the nav2 PR #6104 push were not novel — they are documented in `~/.claude/projects/.../memory/feedback_*.md` files. The structural gap was that **the trap memory lived in agent feedback memory, not in the working tree**. SDE-of-session entering a new slice did not have the traps in the immediate file scope. This file places them at the slice-author's hand: every new slice opens this file, runs the pre-flight check column, then ships.

Per CLAUDE.md §3 Andon-must-produce-loom: the cord-pull (Komada-voice "do not worry about mistakes / use loupe") obligates the loom; this trap log IS that loom for slice-author reflex.

## How to use

1. Before any new slice declares done, walk the table top-to-bottom and run the pre-flight check column for each TRAP whose class matches the slice's surface area (web platform / git push / external data / etc.).
2. If a NEW trap is encountered during a slice, append it to the table with `TRAP-NN` next-numbered, before merging the slice.
3. Linked feedback memory is the canonical detail; this file is the trap-name index.
4. Append-on-observe — never delete a TRAP, even if structurally fixed; structural fixes are recorded as a `## Resolved` section with class + how it was fixed.

---

## TRAP-01 — User-gesture gate for permission API (web)

- **First observed**: Slice 2c (sngnav-app) 2026-04-28; commit `18ece08` per `feedback_flutter_web_traps.md`
- **Symptom**: App shows "Locating you…" forever; no browser permission dialog ever appears
- **Class**: web-only
- **Pre-flight check**: For ANY code that calls `Geolocator.requestPermission()` / `Permission.<x>.request()` / mic / camera / notifications API on web — verify the call is gated behind a button `onPressed` handler or other user-gesture event. `initState()` / `build()` / post-frame callback all silently return `denied` on browsers without showing the prompt. Test in browser DevTools console: should see no "blocked by user gesture requirement" warning.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_flutter_web_traps.md` (point 1)

## TRAP-02 — CORS preflight on custom HTTP headers (web)

- **First observed**: Slice 2b (sngnav-app) 2026-04-28; same commit `18ece08`
- **Symptom**: Browser shows `NetworkError when attempting to fetch resource`; curl from same machine succeeds
- **Class**: web-only / http
- **Pre-flight check**: For ANY HTTP request originating from web target — check that the request does NOT set custom headers (especially `User-Agent`). Custom headers trigger an `OPTIONS` preflight; if the target server's `Access-Control-Allow-Methods` does not include `OPTIONS`, the preflight fails and the real request never fires. Strip custom headers on web; the browser sends its own User-Agent. Native HTTP libraries (mobile / desktop) do NOT have this constraint.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_flutter_web_traps.md` (point 2)

## TRAP-03 — `Stream.handleError` return-value silently discarded

- **First observed**: Slice 2c-fix (sngnav-app) 2026-04-28; caught while fixing TRAP-01
- **Symptom**: Stream stops emitting after an error; no synthetic event surfaces; error is silently swallowed
- **Class**: dart-stream / lifecycle
- **Pre-flight check**: For any `Stream.handleError` usage — confirm you are NOT relying on the return value. The callback returns `void`; returning a synthetic event does nothing. Use `controller.add()` inside `listen(onError: ...)` OR convert errors to data inside a `StreamTransformer`. Not web-specific — bites everywhere; particularly subtle because `flutter analyze` does not flag the pattern.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_flutter_web_traps.md` (point 3)

## TRAP-04 — DCO sign-off required on ROS / CNCF / LF repos

- **First observed**: nav2 PR #6104 C.2.a fix push, 2026-04-29 morning JST
- **Symptom**: PR shows green linting + green build but a `DCO` check refuses to clear (status `action_required`, NOT failed)
- **Class**: git-push / external-PR
- **Pre-flight check**: Before pushing any commit to a PR against `ros-navigation/*`, `ros2/*`, COVESA repos, CNCF projects, or any project calling itself "Linux Foundation" — check the repo's `CONTRIBUTING.md` for "DCO" or "sign-off" mention. If present, always commit with `--signoff`. Verify before push: `git log --pretty='%h | %s | signoff=%(trailers:key=Signed-off-by,valueonly,separator=,)' upstream/main..HEAD` shows the trailer per commit. Fix on amend: `git commit --amend --signoff --no-edit` then `--force-with-lease` push. The `Co-Authored-By` trailer is a SEPARATE trailer; both can coexist on one commit — do not conflate.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_git_workflow_gotchas.md` (point 1)

## TRAP-05 — Narrow `remote.origin.fetch` refspec stops feature-branch tracking refs from updating

- **First observed**: nav2 PR #6104 C.2.a fix push, 2026-04-29 morning JST; clone at `/home/komada/tmp/navigation2`
- **Symptom**: `--force-with-lease` rejects with "stale info" but `git ls-remote origin <branch>` shows the remote IS at the SHA you expect
- **Class**: git-push / lifecycle (clone-config drift)
- **Pre-flight check**: When `--force-with-lease` rejects unexpectedly, run `git ls-remote origin <branch>` to query github.com live (bypasses local ref cache). If the live SHA matches your expected, the cause is a stale local tracking ref. Inspect `git config --get remote.origin.fetch`: default is `+refs/heads/*:refs/remotes/origin/*` (all branches); narrow form `+refs/heads/main:refs/remotes/origin/main` (single-branch clones; main only) silently desyncs feature-branch tracking refs. Fix-A: `git fetch origin +<branch>:refs/remotes/origin/<branch>` then re-push. Fix-B: explicit lease form `git push --force-with-lease=<branch>:<expected-sha> origin <branch>`. Per `CLAUDE.md` "NEVER update the git config" — do NOT autonomously rewrite the refspec; surface to Komada-voice for manual fix.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_git_workflow_gotchas.md` (point 2)

## TRAP-06 — `--force-with-lease` without explicit lease target requires upstream-tracking config

- **First observed**: nav2 PR #6104 C.2.a fix push, 2026-04-29 morning JST; same `/home/komada/tmp/navigation2` clone, branch `feat/zone-parameter-filter`
- **Symptom**: `--force-with-lease` (no args) rejects with "stale info" even after a fresh fetch confirms the local tracking ref is current
- **Class**: git-push / lifecycle (upstream-config gap)
- **Pre-flight check**: Run `git rev-parse @{u}`; if it errors with "upstream branch ... not stored as a remote-tracking branch", the local branch has no upstream config (`branch.<name>.remote` + `branch.<name>.merge` unset). `--force-with-lease` defaults to using the upstream-tracking ref as lease anchor; no upstream = no anchor = rejection. Fix: switch to explicit form `git push --force-with-lease=<branch>:<expected-sha>`. The explicit form does not depend on upstream config. Alternative: set upstream first with `git push -u origin <branch>` (regular push — fine if not history-rewriting). Cross-cutting takeaway: when force-push-with-lease rejects, diagnose ALL THREE failure points (TRAP-05 stale ref / TRAP-06 no upstream / wrong SHA) before retrying.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_git_workflow_gotchas.md` (point 3)

## TRAP-07 — JMA AMeDAS station IDs guessed from memory; canonical source is `amedastable.json`

- **First observed**: sngnav-app Slice 3 corridor weather panel, 2026-04-29 morning JST; commit `a2f3396` shipped 5 station IDs of which 3 were wrong (404)
- **Symptom**: Corridor weather rows return 404 from JMA AMeDAS API; specific incorrect IDs were `32441` (大曲 — actual `32551`), `32486` (湯沢 — actual `32691`), `32414` (男鹿 — actual `32286`); fix landed in `48865fb` after Explore-agent verification
- **Class**: external-data / verify-first
- **Pre-flight check**: For ANY new station / endpoint / external-ID lookup — query the canonical source first. JMA AMeDAS station table: `outputs/research/jma_amedas_akita_corridor_stations_2026_04_29.md` (Explore-sourced) OR fetch live `amedastable.json` from JMA. Do NOT guess from memory. Per `feedback_vaa_executes_solo_anti_pattern.md`: spawn Explore for any external-data verification; default-to-execute-solo with memory-guess is forbidden. The 3-of-5 wrong-rate at slice-3-initial is the founding evidence that memory-guess on external IDs has a high error rate even for "well-known" Japanese station tables.
- **Linked feedback memory**: `~/.claude/projects/-home-komada-Documents-LLMnotebooks-toyota-flutter-masterplan/memory/feedback_vaa_executes_solo_anti_pattern.md` + research artifact `outputs/research/jma_amedas_akita_corridor_stations_2026_04_29.md` + session log `~/.claude/projects/.../memory/project_log_2026_04_29_morning.md`

---

## Vision attribution (file-level, 3-slot)

- `sakichi_vision_id = 11` (Andon — anyone pulls; this trap log is the loom installed when Komada-voice's "do not worry about mistakes / use loupe" cord-pull obligated the kaizen artifact)
- `method_vision_ids = [77, 92, 99]` (V77 genchi-genbutsu — read the actual error in browser console / git rejection / 404 response / V92 missing-loom — every TRAP row IS a loom for the next slice / V99 write-it-down — append-on-observe)
- `stance_vision_ids = [22, 96, 100]` (V22 loom-serves-weaver — protects the slice author from re-tripping known traps / V96 maintainers-are-edge-developers — TRAP-04/05/06 protect the maintainers we PR against / V100 equal-dignity)

## Append-on-observe rule

When a NEW trap is encountered during slice authoring, append a `TRAP-NN` row to this file BEFORE the slice merges. Schema match the rows above (First observed / Symptom / Class / Pre-flight check / Linked feedback memory). If a parallel feedback memory does not yet exist, the slice author writes a 1-paragraph stub and links it. Failure to record a NEW trap on first encounter is V42 ornament (we paid for the trap; we owe the loom).

## Resolved (none yet at v0.1)

This section reserved for traps that have been structurally eliminated (e.g., a lint rule installed that auto-catches the pattern; a CI check that prevents the failure mode from reaching `main`). When a trap moves to Resolved, it does NOT delete from the active table — it gets a one-line entry here with the resolution mechanism + date.

---

**End of trap log v0.1.** 7 TRAPs seeded from three feedback-memory sources. Next-slice author runs the pre-flight checklist before shipping.
