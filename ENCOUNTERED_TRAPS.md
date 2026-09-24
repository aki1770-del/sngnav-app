# sngnav-app — Encountered Traps

**Owner**: the app's debugging maintainer
**Adopted**: 2026-04-29 evening JST (recovery plan v0)
**Class**: trap log — pre-flight checklist for every new slice
**Status**: v0.1 seeded 2026-04-29 evening JST

## The instruction that started it (verbatim, 2026-04-29 evening JST)

> *"My ORDER: start today. DO NOT WORRY ABOUT making mistakes. INSTEAD try anyway. IF you are not fully aware you see, use loupe, glass, or camera."*

The "loupe / glass / camera" instruction means: go and look at the real thing, and verify before claiming. The trap log is the loupe applied before each new slice is declared done.

## Why this file exists (V92 origin)

Failure modes that bit the project on Slice 2/3 of sngnav-app + the nav2 PR #6104 push were not novel — they were documented in notes kept outside this repository. The structural gap was that **the trap memory lived in those notes, not in the working tree**. Whoever entered a new slice did not have the traps in the immediate file scope. This file places them at the slice-author's hand: every new slice opens this file, runs the pre-flight check column, then ships.

The instruction ("do not worry about mistakes / use loupe") called for a lasting fix, not a one-off; this trap log IS that fix for the slice author's reflex.

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
- **Linked note**: kept outside this repository (Flutter web traps, point 1)

## TRAP-02 — CORS preflight on custom HTTP headers (web)

- **First observed**: Slice 2b (sngnav-app) 2026-04-28; same commit `18ece08`
- **Symptom**: Browser shows `NetworkError when attempting to fetch resource`; curl from same machine succeeds
- **Class**: web-only / http
- **Pre-flight check**: For ANY HTTP request originating from web target — check that the request does NOT set custom headers (especially `User-Agent`). Custom headers trigger an `OPTIONS` preflight; if the target server's `Access-Control-Allow-Methods` does not include `OPTIONS`, the preflight fails and the real request never fires. Strip custom headers on web; the browser sends its own User-Agent. Native HTTP libraries (mobile / desktop) do NOT have this constraint.
- **Linked note**: kept outside this repository (Flutter web traps, point 2)

## TRAP-03 — `Stream.handleError` return-value silently discarded

- **First observed**: Slice 2c-fix (sngnav-app) 2026-04-28; caught while fixing TRAP-01
- **Symptom**: Stream stops emitting after an error; no synthetic event surfaces; error is silently swallowed
- **Class**: dart-stream / lifecycle
- **Pre-flight check**: For any `Stream.handleError` usage — confirm you are NOT relying on the return value. The callback returns `void`; returning a synthetic event does nothing. Use `controller.add()` inside `listen(onError: ...)` OR convert errors to data inside a `StreamTransformer`. Not web-specific — bites everywhere; particularly subtle because `flutter analyze` does not flag the pattern.
- **Linked note**: kept outside this repository (Flutter web traps, point 3)

## TRAP-04 — DCO sign-off required on ROS / CNCF / LF repos

- **First observed**: nav2 PR #6104 C.2.a fix push, 2026-04-29 morning JST
- **Symptom**: PR shows green linting + green build but a `DCO` check refuses to clear (status `action_required`, NOT failed)
- **Class**: git-push / external-PR
- **Pre-flight check**: Before pushing any commit to a PR against `ros-navigation/*`, `ros2/*`, COVESA repos, CNCF projects, or any project calling itself "Linux Foundation" — check the repo's `CONTRIBUTING.md` for "DCO" or "sign-off" mention. If present, always commit with `--signoff`. Verify before push: `git log --pretty='%h | %s | signoff=%(trailers:key=Signed-off-by,valueonly,separator=,)' upstream/main..HEAD` shows the trailer per commit. Fix on amend: `git commit --amend --signoff --no-edit` then `--force-with-lease` push. The `Co-Authored-By` trailer is a SEPARATE trailer; both can coexist on one commit — do not conflate.
- **Linked note**: kept outside this repository (git workflow gotchas, point 1)

## TRAP-05 — Narrow `remote.origin.fetch` refspec stops feature-branch tracking refs from updating

- **First observed**: nav2 PR #6104 C.2.a fix push, 2026-04-29 morning JST; clone at `~/tmp/navigation2`
- **Symptom**: `--force-with-lease` rejects with "stale info" but `git ls-remote origin <branch>` shows the remote IS at the SHA you expect
- **Class**: git-push / lifecycle (clone-config drift)
- **Pre-flight check**: When `--force-with-lease` rejects unexpectedly, run `git ls-remote origin <branch>` to query github.com live (bypasses local ref cache). If the live SHA matches your expected, the cause is a stale local tracking ref. Inspect `git config --get remote.origin.fetch`: default is `+refs/heads/*:refs/remotes/origin/*` (all branches); narrow form `+refs/heads/main:refs/remotes/origin/main` (single-branch clones; main only) silently desyncs feature-branch tracking refs. Fix-A: `git fetch origin +<branch>:refs/remotes/origin/<branch>` then re-push. Fix-B: explicit lease form `git push --force-with-lease=<branch>:<expected-sha> origin <branch>`. Per `CLAUDE.md` "NEVER update the git config" — do NOT autonomously rewrite the refspec; surface to the maintainer for a manual fix.
- **Linked note**: kept outside this repository (git workflow gotchas, point 2)

## TRAP-06 — `--force-with-lease` without explicit lease target requires upstream-tracking config

- **First observed**: nav2 PR #6104 C.2.a fix push, 2026-04-29 morning JST; same `~/tmp/navigation2` clone, branch `feat/zone-parameter-filter`
- **Symptom**: `--force-with-lease` (no args) rejects with "stale info" even after a fresh fetch confirms the local tracking ref is current
- **Class**: git-push / lifecycle (upstream-config gap)
- **Pre-flight check**: Run `git rev-parse @{u}`; if it errors with "upstream branch ... not stored as a remote-tracking branch", the local branch has no upstream config (`branch.<name>.remote` + `branch.<name>.merge` unset). `--force-with-lease` defaults to using the upstream-tracking ref as lease anchor; no upstream = no anchor = rejection. Fix: switch to explicit form `git push --force-with-lease=<branch>:<expected-sha>`. The explicit form does not depend on upstream config. Alternative: set upstream first with `git push -u origin <branch>` (regular push — fine if not history-rewriting). Cross-cutting takeaway: when force-push-with-lease rejects, diagnose ALL THREE failure points (TRAP-05 stale ref / TRAP-06 no upstream / wrong SHA) before retrying.
- **Linked note**: kept outside this repository (git workflow gotchas, point 3)

## TRAP-07 — JMA AMeDAS station IDs guessed from memory; canonical source is `amedastable.json`

- **First observed**: sngnav-app Slice 3 corridor weather panel, 2026-04-29 morning JST; commit `a2f3396` shipped 5 station IDs of which 3 were wrong (404)
- **Symptom**: Corridor weather rows return 404 from JMA AMeDAS API; specific incorrect IDs were `32441` (大曲 — actual `32551`), `32486` (湯沢 — actual `32691`), `32414` (男鹿 — actual `32286`); fix landed in `48865fb` after Explore-agent verification
- **Class**: external-data / verify-first
- **Pre-flight check**: For ANY new station / endpoint / external-ID lookup — query the canonical source first. JMA AMeDAS station table: fetch live `amedastable.json` from JMA (or a research note made from it). Do NOT guess from memory. Verify external data with a separate lookup; guessing from memory is forbidden. The 3-of-5 wrong-rate at slice-3-initial is the founding evidence that memory-guess on external IDs has a high error rate even for "well-known" Japanese station tables.
- **Linked notes**: kept outside this repository (verify external data before use; the 2026-04-29 station research; the 2026-04-29 morning session log)

## TRAP-08 — a Dart probe compiled inside package A links package B FROM THE PUB CACHE, so it measures the PUBLISHED package, not the tree you just edited

- **First observed**: `~/SNGNav`, 2026-09-13, converting assert-only release guards. A probe compiled inside `packages/snow_rendering/` to prove guards fire with asserts OFF reported `FAIL -- NOTHING THREW` for two subjects in `navigation_safety_core`. The code was correct; the probe was reading `~/.pub-cache/hosted/pub.dev/navigation_safety_core-0.10.3` while the edited tree was `0.11.5`.
- **Symptom**: A verification passes or fails for reasons that have nothing to do with your diff, and the failure is indistinguishable from a real defect. `dart analyze` and `dart test` in the EDITED package are green throughout, because they resolve locally — only the cross-package probe is lying.
- **Class**: verification-substrate / Verify-First. Same family as `ran-what-you-claim-dart.py` (a Dart result is about the package that RESOLVED, never about the tree you edited) and `a-lock-is-not-a-constraint-2026-08-24`.
- **Pre-flight check**: Before trusting ANY cross-package Dart probe, print what actually resolved:
  ```
  python3 -c "import json;[print(p['name'],'->',p['rootUri']) for p in json.load(open('.dart_tool/package_config.json'))['packages']]"
  ```
  A sibling showing `file:///home/.../.pub-cache/...` is NOT your tree. Compile the probe INSIDE the package you edited (whose own entry reads `rootUri: ../`), or add a `dependency_overrides` path entry. **The consolation prize is real**: a pub-cache-resolved probe is an accurate measurement of what an edge developer actually installs — just say which question you answered.
- **Linked feedback memory**: `ran-what-you-claim-dart.py` header (masterplan `scripts/`), `a-lock-is-not-a-constraint-2026-08-24.md`

---

## TRAP-09 — `dart format --set-exit-if-changed | tail` reports success while the check fails

- **First observed**: `~/SNGNav`, 2026-09-13. A format gate printed `format exit=0` for four packages that were all actually exit 1. `$?` after a pipeline is the exit of the LAST command — `tail` — which succeeds no matter what `dart format` did.
- **Symptom**: A gate reports green in the same breath as printing the evidence that it is red (`Changed <file>` lines were visible directly above `exit=0`).
- **Class**: measurement-instrument / success-shaped-failure. Same family as the three cases recorded against the pen in CLAUDE.md v4.5 — "its own verification steps returned success-shaped while the operation failed".
- **Pre-flight check**: Never read `$?` through a pipe. Capture first, then inspect: `out=$(dart format --output=none --set-exit-if-changed .); rc=$?`. Applies to every `cmd | tail` / `| grep` / `| head` in a gate. Also: `--output=none` still prints `Changed <file>`; those are files that WOULD change, so grep that list against the files you actually touched before reformatting someone else's in-flight work.
- **Linked feedback memory**: CLAUDE.md v4.5 version note (the three success-shaped verification failures); `gate-block-is-not-length-2026-09-04.md`

---

## TRAP-10 — a tracked example lockfile keeps a sibling version the pubspec no longer means, so the example never compiles against the sibling at HEAD

- **First observed**: `~/work/r3-fdd-sngnav-52c2f30` (a clone of `~/SNGNav`), 2026-09-13, C-20 (a). Widening `packages/navigation_safety/example`'s `routing_engine: ^0.4.0` to `'>=0.4.0 <0.7.0'` turned CI's sibling-constraint step green, and `flutter pub get` plus analyze in the example stayed clean. A would-be archive rebuilt outside the monorepo resolved routing_engine 0.6.3 and failed to compile (`LatLng?` passed where `LatLng` is required). The tracked lock still held 0.4.0, and pub keeps a locked version the new range still admits.
- **Symptom**: every in-tree check is green; the first developer who resolves fresh gets a compile error. Once the code was fixed, the same stale lock produced two analyzer warnings in-tree, pointing the other way.
- **Class**: verification-substrate / Verify-First. Same family as TRAP-08 and `a-lock-is-not-a-constraint-2026-08-24`.
- **Pre-flight check**: after changing a constraint, print what resolved (TRAP-08's one-liner) and do not trust an in-tree result until one of these has run: `flutter pub upgrade <dep>` in the example, or the archive rebuilt from `pub publish --dry-run`'s file list and resolved outside the monorepo. Before writing a range, pin each line floor with a scratch `dependency_overrides` entry and compile it.
- **Linked feedback memory**: `a-lock-is-not-a-constraint-2026-08-24.md`; TRAP-08

---

## TRAP-11 — `dart format` can introduce a lint the file did not have

- **First observed**: same clone, 2026-09-13, C-20 (e). Formatting `packages/driving_conditions/tool/abi_layout_check.dart` moved the body of a too-long `if (fields.isEmpty) throw ...;` onto its own line, and `curly_braces_in_flow_control_structures` then reported an info. The file at `52c2f30` analyzed with 0 issues; the formatted file had 1.
- **Symptom**: a commit that only formats changes the analyzer's verdict, and `dart analyze` still exits 0 because infos do not fail it.
- **Class**: tooling interaction / success-shaped. Same family as TRAP-09.
- **Pre-flight check**: format, then analyze the package again and compare issue COUNTS, not exit codes. Prove the change is layout-only by comparing both versions with whitespace and commas stripped.
- **Linked feedback memory**: TRAP-09

---

## TRAP-12 — an error's `toString` can span lines, which breaks a one-line log report

- **First observed**: same clone, 2026-09-13, C-20 (b). `navigation_safety_core`'s default rejection report promises one stdout line. A transform calling `int.parse('three hundred')` throws a `FormatException` whose `toString` prints the source and a caret on following lines, so one report became several lines, and only the first carried the `navigation_safety_core:` prefix.
- **Symptom**: a log reader that takes one line per entry splits the error and its stack trace away from the prefix that says where they came from. A test using `StateError` passes, because its text is one line.
- **Class**: output contract.
- **Pre-flight check**: where a report promises one line, escape line breaks in every interpolated error and stack trace, and test it with a `FormatException`, not a `StateError`.
- **Linked feedback memory**: none; the regression test is `packages/navigation_safety_core/test/vehicle_threshold_overrides_test.dart` ("the DEFAULT report is exactly ONE stdout line").

---

## TRAP-13 — pub publishes `dependency_overrides` as written, and its validator calls them a hint

- **First observed**: SNGNav, 2026-09-19. 9 of 36 published archives carried `path: ../<sibling>` overrides — 7 in the package ROOT `pubspec.yaml`, 4 in `example/pubspec.yaml`. `pub get` inside each extracted archive exits 66, "path which doesn't exist". The same packages' `dart pub publish --dry-run` said "Package has 0 warnings", with a hint "Non-dev dependencies are overridden in pubspec.yaml".
- **Symptom**: the publish succeeds and an app that depends on the package resolves normally (a dependency's overrides never apply to its dependents). Only someone resolving INSIDE the downloaded package — its tests, its example, an editor opening it — fails, and they are the one person we never hear from.
- **Class**: success-shaped publish; a belief ("pub strips them") written into comments and shipped.
- **Pre-flight check**: no `path:` override in any shipped `pubspec.yaml`. Package root → `pubspec_overrides.yaml` (pub never publishes the root one); `example/` → `example/pubspec_overrides.yaml`, named in the package `.pubignore` (a nested one IS published otherwise). Prove it from outside: rebuild the archive from the dry-run's own file list, resolve it alone in an empty directory. Standing guard: `scripts/sibling_constraint_check.py`, archive-path lane.
- **Linked feedback memory**: none; the record is `outputs/flutter-dart-developer/r115_published_examples_on_main_2026_09_19/`.

---

## TRAP-14 — a `.pubignore` replaces its own directory's `.gitignore`, not the repository's

- **First observed**: 2026-09-19, measured with `dart pub publish --dry-run` (Dart 3.11.1) in a scratch repository. With a `.pubignore` present, a file named only in that directory's `.gitignore` IS published. The repository-root `.gitignore` still applies — but only when publishing from inside the git work tree; from a copy outside it, `build/` and `coverage/` are published.
- **Symptom**: adding a `.pubignore` can silently start shipping what the package's own `.gitignore` kept out; publishing from a staging copy ships build output (this catalog shipped 15-17 MB `build/` directories that way on 2026-07-13).
- **Class**: tooling semantics; both the fear ("it will ship build/") and the belief ("it replaces every .gitignore") were wrong until measured.
- **Pre-flight check**: a new `.pubignore` restates its directory's `.gitignore`, and names `build/` and `coverage/` so it travels with the package. Compare the dry-run file list before and after: it must not change.
- **Linked feedback memory**: none; the measurement matrix is in the record above (`pubignore_semantics`).

---

## TRAP-15 — an empty sandbox makes `pub get` exit 66, the same code as the defect

- **First observed**: 2026-09-19. A harness copied a package's file list by a RELATIVE path after `cd`-ing into the package, so it copied nothing; `pub get` in the empty directory exited 66 and all nine packages "reproduced" the defect. Only stderr (`No such file or directory`) showed it.
- **Symptom**: a false red that looks exactly like the true red. The same harness would have produced a false green had the defect's code been 0.
- **Class**: dead instrument, success-shaped (here failure-shaped).
- **Pre-flight check**: resolve every input path to absolute before `cd`; refuse to run the tool unless the sandbox holds every listed file; classify each non-zero exit by its MESSAGE, never its code alone.
- **Linked feedback memory**: none.

---

## TRAP-16 — `git stash` is shared by every worktree of a repository

- **First observed**: 2026-09-19, SNGNav (80+ worktrees). `git stash list` in a brand-new worktree showed two entries from other work (2026-06-23, 2026-08-25). A `push`/`pop` pair in one worktree operates on the stack every other worktree uses; a `pop` in a busy repository can take someone else's entry.
- **Symptom**: none when it goes right; lost or misapplied work when two worktrees stash at once.
- **Class**: shared state that looks local.
- **Pre-flight check**: in a repository other seats use, compare against a pristine `git worktree add --detach <path> <sha>` instead of stashing.
- **Linked feedback memory**: none.

---

## TRAP-17 — Dart never warns about a declared dependency that nothing imports, even when a comment says something does

- **First observed**: 2026-09-25. `pubspec.yaml` declared `japanese_snow_vocabulary` DIRECT "because lib/services/drive_diary.dart now imports it", with a drift guard at `test/services/drive_diary_vocabulary_test.dart`. The declaration landed on 2026-08-23; the import and the guard stayed uncommitted in a working tree. For a month, zero files in `lib/` or `test/` imported the package on the line that ships.
- **Symptom**: none. `depend_on_referenced_packages` flags an import with no declaration, never a declaration with no import, and the package still resolved transitively (via `snow_rendering`), so nothing broke. The comment read as proof of wiring.
- **Class**: a justification that is prose, not a check; a partial landing that looks whole.
- **Pre-flight check**: `git grep -l 'package:<dep>/' <sha> -- lib test` on the COMMIT, not the working tree, for every dependency whose comment names an importer; confirm every path a pubspec comment cites is tracked at that commit.
- **Linked feedback memory**: none.

---

## TRAP-18 — a call-graph walk that treats "never referenced" as "entry point" reports dead code as reachable

- **First observed**: 2026-09-25, reading `test/voice/announce_call_site_census_test.dart`'s release-reachability column (first draft): it counted any function with no referrers as an entry point, so deleting a voice's last caller would leave it "reaching release"; and it declared the developer-page roots dev-only by name, so embedding `_developerSections()` in the release page would not register.
- **Symptom**: a voice that went quiet, or a developer page built into her screen, passes. Measured 2026-09-25 by mutation, each run to completion: with the first-draft census, commenting out the only caller of `tellWithNoShare` PASSED, and embedding `..._developerSections()` in the release page PASSED. With the corrected census, both FAIL, as do a dev-only voice gaining a release caller and the developer-page entry losing its gate.
- **Class**: an instrument's default that sits on the success side; a seed asserted by declaration instead of measured.
- **Pre-flight check**: before trusting a reachability walk, mutate the code both ways (delete the last caller; add a release caller) and watch it fail; treat only `main` and `@override` declarations as entry points; measure the seed's own referrers.
- **Linked feedback memory**: none.

---

## Vision attribution (file-level, 3-slot)

- `sakichi_vision_id = 11` (anyone may stop the line; this trap log was installed after the instruction "do not worry about mistakes / use loupe" called for an improvement artifact)
- `method_vision_ids = [77, 92, 99]` (V77 genchi-genbutsu — read the actual error in browser console / git rejection / 404 response / V92 missing-loom — every TRAP row IS a loom for the next slice / V99 write-it-down — append-on-observe)
- `stance_vision_ids = [22, 96, 100]` (V22 loom-serves-weaver — protects the slice author from re-tripping known traps / V96 maintainers-are-edge-developers — TRAP-04/05/06 protect the maintainers we PR against / V100 equal-dignity)

## Append-on-observe rule

When a NEW trap is encountered during slice authoring, append a `TRAP-NN` row to this file BEFORE the slice merges. Schema match the rows above (First observed / Symptom / Class / Pre-flight check / Linked feedback memory). If a parallel feedback memory does not yet exist, the slice author writes a 1-paragraph stub and links it. Failure to record a NEW trap on first encounter is V42 ornament (we paid for the trap; we owe the loom).

## Resolved (none yet at v0.1)

This section reserved for traps that have been structurally eliminated (e.g., a lint rule installed that auto-catches the pattern; a CI check that prevents the failure mode from reaching `main`). When a trap moves to Resolved, it does NOT delete from the active table — it gets a one-line entry here with the resolution mechanism + date.

---

**End of trap log v0.1.** 7 TRAPs seeded from three feedback-memory sources. Next-slice author runs the pre-flight checklist before shipping.
