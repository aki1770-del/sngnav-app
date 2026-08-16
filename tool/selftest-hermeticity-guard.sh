#!/usr/bin/env bash
# selftest-hermeticity-guard.sh — a guard's --self-test must pass in a tree that
# contains ONLY TRACKED FILES.
#
# WHY THIS EXISTS (2026-08-16)
# ----------------------------
# main was RED at 7339570 on:
#
#   SELF-TEST FAILED: fixture archive absent at .../assets/tiles/gunma_offline.mbtiles
#
# tile-archive-identity-guard.sh's --self-test read its fixture from
# assets/tiles/gunma_offline.mbtiles — a local build intermediate of the
# 2026-08-11 multi-region render. Measured 2026-08-16: not tracked
# (`git ls-tree main assets/tiles/` lists only akita_offline.mbtiles) and not
# ignored (`git check-ignore` exits 1), so it is in NO checkout a runner ever
# makes. Those four detection cases had therefore NEVER RUN — first masked by
# the guards being wired through a private path a runner never checks out
# (fixed in ae1bcf6), then by the sibling guard's own red (fixed in bc3a2ea),
# at which point the failure simply moved to the fixture.
#
# ⚑ This paragraph said "and not on the authoring machine either. It exists
# nowhere." until 2026-08-16, when that was measured FALSE: the file is present
# at /home/komada/tmp/sngnav-app/assets/tiles/gunma_offline.mbtiles, 11,034,624
# bytes. It is absent only from the OTHER clone of this repository, which is
# where the sentence was written — a claim about "the machine" made from one
# tree. Corrected rather than deleted, because a wrong-tree measurement is the
# same shape as the defect this whole file exists to catch: a conclusion true
# in the author's checkout and nowhere else. What the guard rests on is
# untouched — untracked in every clone, therefore absent from every CI checkout.
#
# The root cause is not "a file was missing". It is one level below that:
#
#   NOTHING ASSERTS THAT A GUARD'S --self-test CAN RUN FROM A CLEAN CHECKOUT.
#   Four of the five self-tests in tool/ are hermetic by accident of idiom —
#   they write their fixtures into `mktemp -d` (assert_manifest_perms.sh:235-248)
#   or reconstruct them from git history (loom_mutation_gate.sh). Nothing MADE
#   them hermetic, so when one guard reached for a binary artifact on disk
#   instead, no check existed to notice. The author's disk had the file; every
#   other copy of this repository did not.
#
#   Had this script existed on 2026-08-11, ae1bcf6 would have failed at author
#   time: the fixture is untracked, so it is invisible in a pristine checkout,
#   and the self-test fails there while passing in the author's tree. That is
#   exactly the signature reported below as NON-HERMETIC.
#
#   This is a different question from the one loom_mutation_gate.sh answers.
#   That script certifies that a guard BITES A REAL DEFECT, given a corpus of
#   broken inputs. It says nothing about where the guard's own fixtures come
#   from. No overlap, so this is a new check rather than a rename of that one.
#
# The place nobody went and looked was a clean checkout of our own repository.
# Every guard was only ever run in the tree where it was written. This script is
# that visit, made mechanical so it happens whether or not anyone remembers.
#
# WHAT IT DOES
#   Materialises the repository's committed tree TWICE, as two throwaway git
#   worktrees — tracked files only, full git history (so history-reading guards
#   still work, the way CI's fetch-depth:0 checkout intends):
#
#     PRISTINE ... tracked files only. What a runner checks out.
#     SEEDED ..... the same tracked files, plus every untracked and ignored path
#                  copied in from the working tree. What the AUTHOR's disk looks
#                  like — without their uncommitted source edits.
#
#   Then it runs THE SAME COMMITTED SCRIPT in both. The trees differ by exactly
#   one thing, untracked content, so any difference in behaviour is a dependence
#   on it. Uncommitted edits cannot confound the comparison because neither run
#   ever sees them.
#
#     pristine FAIL + seeded PASS ... NON-HERMETIC. The self-test depends on
#                                     something not in the checkout. Exit 1.
#     both PASS, output DIFFERS ..... DIVERGENT. It passes either way but does
#                                     different WORK — the signature of a
#                                     self-test that SKIPS when its fixture is
#                                     absent and exits 0 anyway. Exit 1.
#     two runs in ONE tree differ ... UNSTABLE. The self-test disagrees with
#                                     itself, so divergence is unreadable.
#                                     Exit 3.
#     FAIL in both .................. UNDETERMINED. Hermeticity cannot be read
#                                     off a self-test that fails everywhere.
#                                     Exit 3 — never green.
#     pristine PASS + seeded FAIL ... hermetic; something untracked BREAKS it.
#                                     Reported loudly; the hermeticity question
#                                     is answered, so it does not fail here.
#     PASS in both, same output ..... hermetic.
#
# HONEST BOUNDS, because they decide how to read a green here:
#   - It materialises HEAD (override with SELFTEST_HERMETIC_REF). It sees the
#     COMMITTED tree, which is what a runner checks out — so at author time,
#     commit before trusting it, or point it at your ref.
#   - It runs the self-tests in the CALLER's environment. It does not create a
#     clean PATH or a clean HOME. A self-test depending on an installed
#     interpreter or a system package is out of scope here and shows up as
#     UNDETERMINED, not as a hermeticity verdict.
#   - ⚑ THE OTHER HALF OF THE CLASS — ADDED 2026-08-16 ON FBR FINDING F2, and
#     the bounds below are the corrected ones. This file previously claimed to
#     cover "the class"; it covered ONE SHAPE of it. Divergence detects a
#     dependence on an UNTRACKED PATH INSIDE the repo, and is structurally BLIND
#     to a dependence on an ABSOLUTE PATH OUTSIDE it — which behaves identically
#     in both trees and returned `hermetic`, exit 0. That outside shape is the
#     2026-08-11 defect's OWN shape (guards resolved through a private
#     $HOME/Documents/… path no runner checks out), so the file was blind to its
#     own founding incident. The OUTSIDE-REPO check now traces what each
#     self-test actually touches. ITS bounds, REWRITTEN after FBR round-3
#     returned CONFIRMED-DOWNGRADED on the first version of this list, which
#     overclaimed in two specific places and omitted the exclusion that mattered
#     most:
#       * it needs `strace`. Where strace is absent, cannot ptrace, is killed by
#         the timeout, or produces no usable trace, the answer is COULD-NOT-LOOK
#         and it is printed per guard as `trace-UNCHECKED`. ⚑ By default that
#         still exits 0, which is NOT good enough on its own — FBR: "UNVERIFIED
#         that clears the gate is cleared." Set SELFTEST_HERMETIC_REQUIRE_TRACE=1
#         (CI does) to make an unchecked class a fail-closed 3.
#       * it excludes system prefixes, the two worktrees, the git common dir,
#         the run's own fresh TMPDIR, dot-paths under $HOME, and ANY PATH UNDER
#         A DIRECTORY ON $PATH. That last rule exists because the dot rule alone
#         cried wolf on this machine's own Flutter SDK at /home/komada/flutter —
#         a hard RED on a healthy guard, which is how a check gets deleted.
#         A fixture parked in a dot-directory under $HOME, or inside a $PATH
#         directory, is therefore MISSED.
#       * ⚑ IT NO LONGER EXCLUDES THE LIVE CHECKOUT. The first version excluded
#         $REPO wholesale — and $REPO is exactly where untracked fixtures live,
#         so a self-test reaching into the working tree BY ABSOLUTE PATH was
#         invisible to BOTH halves of this guard. That is this file's own
#         founding defect, and it read green.
#       * it reports REGULAR FILES only, so a dependence on an outside
#         DIRECTORY merely existing is MISSED;
#       * it only traces self-tests that PASS here, because that is the shape
#         this class takes.
#   - ⚑ AND THE ONE THAT DECIDES HOW TO READ A GREEN FROM CI, measured by FBR:
#     A RUNNER CHECKOUT HAS ZERO UNTRACKED-NOT-IGNORED PATHS. PRISTINE and
#     SEEDED are then byte-identical, so NON-HERMETIC and DIVERGENT are
#     STRUCTURALLY UNREACHABLE IN CI — they are developer-machine verdicts. The
#     OUTSIDE-REPO check is the only verdict here that can fire on a runner.
#     A green from CI therefore means much less than a green from a developer's
#     machine, and both are needed.
#   - It excludes itself from discovery, to avoid recursing into its own
#     --self-test. Its own fixtures are built in a throwaway git repository
#     under `mktemp -d`, so it is hermetic by construction.
#   - ⚑ DIVERGENT COMPARES OUTPUT, AND OUTPUT IS A PROXY. Stated because the
#     alternative is over-claiming. A skip-on-absence self-test that skips
#     SILENTLY, or prints the same banner whether it skipped or worked, is
#     invisible to this check — measured, both evade it, exit 0. It catches the
#     ones that say something different, which is most of them and not all of
#     them.
#   - ⚑ AND IT NEEDS THE UNTRACKED FILE TO EXIST. On a clean runner, where the
#     fixture is absent from every tree, "skipped" and "ran" are
#     indistinguishable from outside and this reports hermetic. It catches the
#     defect on a DEVELOPER's machine — which is where the untracked fixture
#     lives and where the wrong fix gets written. A real capability with a real
#     edge, not a closure.
#
# Usage:
#   tool/selftest-hermeticity-guard.sh [repo-dir]     # default: this repo
#   tool/selftest-hermeticity-guard.sh --self-test    # prove it bites
# Exit: 0 all hermetic · 1 non-hermetic self-test · 2 substrate error
#       3 at least one self-test could not be evaluated (fail-closed)
set -uo pipefail

SELF_BASENAME="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"

# ------------------------------------------------------------------ the check
check_repo() {
  local REPO="$1"
  local REF="${SELFTEST_HERMETIC_REF:-HEAD}"

  command -v git >/dev/null || { echo "SUBSTRATE ERROR: git absent"; return 2; }
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "SUBSTRATE ERROR: not a git repository: $REPO"; return 2; }
  git -C "$REPO" rev-parse --verify "$REF" >/dev/null 2>&1 || {
    echo "SUBSTRATE ERROR: cannot resolve ref '$REF' in $REPO"; return 2; }

  local T PRISTINE
  # ADVERSARIAL-REVIEW C1, 2026-08-16. This carried `|| return 2` but NOT the emptiness
  # check — the very countermeasure this repo already owned one file over
  # (tile-archive-identity-guard.sh, "ADVERSARIAL-REVIEW C2 PRESERVED"). Under
  # `set -uo pipefail` with no `-e`, a `mktemp` that exits 0 while printing
  # nothing leaves T SET but EMPTY, so PRISTINE becomes "/pristine" and every
  # path below is an absolute path at the filesystem root. As an unprivileged
  # user it fails closed at `git worktree add`; as root it would create
  # /pristine, and the cleanup would be `rm -rf ""` — so the residue would be
  # permanent. Found by the independent reviewer by shimming `mktemp` to a bare `exit 0`. A
  # countermeasure that is preserved in one file and not carried into the next
  # is the defect this whole commit is about.
  T=$(mktemp -d) || { echo "SUBSTRATE ERROR: mktemp failed"; return 2; }
  [ -n "$T" ] && [ -d "$T" ] || { echo "SUBSTRATE ERROR: mktemp produced no usable directory"; return 2; }
  PRISTINE="$T/pristine"

  # A worktree, not a copy: tracked files only, git history intact, objects
  # shared. This is the closest thing to what actions/checkout gives a runner.
  if ! git -C "$REPO" worktree add --detach "$PRISTINE" "$REF" >/dev/null 2>&1; then
    echo "SUBSTRATE ERROR: could not materialise $REF as a worktree"
    rm -rf "$T"; return 2
  fi
  # ADVERSARIAL-REVIEW C2, 2026-08-16. This trap body was DOUBLE-quoted, so $REPO and
  # $PRISTINE were interpolated into the trap string at set-time and re-parsed
  # by the shell at fire-time. The reviewer measured both consequences: a repo path
  # containing an apostrophe (`O'Brien`) broke the quoting, cleanup never ran,
  # a worktree stayed registered in the TARGET repo, and this function still
  # returned 0; and a path crafted as `x';id>...;'` EXECUTED `id`. Single quotes
  # make the body a literal that expands its variables at fire-time, correctly
  # quoted — no interpolation, no re-parse, nothing to inject. Verified this
  # turn that a bash RETURN trap still sees the function's locals, including a
  # value containing a quote. CI is not the exposure (GITHUB_WORKSPACE is tame);
  # a developer's own path is.
  trap 'git -C "$REPO" worktree remove --force "$PRISTINE" >/dev/null 2>&1; git -C "$REPO" worktree remove --force "$SEEDED" >/dev/null 2>&1; rm -rf "$T"' RETURN

  echo ">> self-test hermeticity: does each guard's --self-test run from a CLEAN CHECKOUT?"
  echo "   repo     : $REPO"
  echo "   ref      : $REF ($(git -C "$REPO" rev-parse --short "$REF"))"
  echo "   pristine : tracked files only (untracked and ignored paths are INVISIBLE)"
  echo ""

  local nonhermetic=0 undetermined=0 hermetic=0 livebroken=0 found=0
  local divergent=0 advertised=0 unstable=0 outside=0 outside_unchecked=0

  # ⚑ THE COMPARISON WAS REDESIGNED 2026-08-16, second adversarial round, and the
  # reason matters more than the mechanism.
  #
  # It used to be PRISTINE-vs-LIVE. That confounds two different things: the
  # trees differ by untracked content (what we want to measure) AND by whatever
  # the author has uncommitted (noise). To stop crying wolf on the noise I added
  # an exemption — if the live copy of the script differs from the committed
  # one, skip the divergence comparison. The reviewer refuted it in one move:
  # take a COMMITTED skip-on-absence guard, which this correctly reports
  # DIVERGENT, then append ONE comment line to the live copy. Exit 0, green.
  # Its words: "the edit you make while investigating the verdict is what
  # suppresses it." The exit-code verdict cannot back it up, because this defect
  # class passes in the pristine tree too — divergence is its ONLY detector, and
  # the exemption switched it off.
  #
  # The fix is not a better exemption. It is to remove the confound, so there is
  # nothing to exempt. Both runs now use THE SAME COMMITTED SCRIPT, in two trees
  # that differ ONLY by untracked content:
  #
  #   PRISTINE  tracked files only — what a runner checks out.
  #   SEEDED    the same tracked files, plus every untracked and ignored path
  #             copied in from the working tree — what the AUTHOR's disk looks
  #             like, minus their uncommitted source edits.
  #
  # A self-test that reads something outside the repository behaves differently
  # in these two and identically otherwise. Uncommitted edits to the guard are
  # now irrelevant by construction: neither run ever sees them.
  local SEEDED="$T/seeded"
  if ! git -C "$REPO" worktree add --detach "$SEEDED" "$REF" >/dev/null 2>&1; then
    echo "SUBSTRATE ERROR: could not materialise $REF as a second worktree"
    return 2
  fi
  # Overlay UNTRACKED-BUT-NOT-IGNORED paths. `.gitignore` is the repository's own
  # declaration of "this is not source", so ignored paths are excluded by
  # default — and the first version of this, which seeded everything, copied
  # 9594 paths and took 52 seconds because build/ and .dart_tool/ are ignored
  # build output. Measured on this repo: exactly ONE path is
  # untracked-and-not-ignored, and it is assets/tiles/gunma_offline.mbtiles —
  # the file that started all of this. The cheap filter covers the real defect.
  #
  # The bound is REPORTED rather than assumed: a fixture hidden inside an
  # ignored directory would not be seeded and would not be detected. Set
  # SELFTEST_HERMETIC_SEED_IGNORED=1 to include those too, slowly.
  local seed_args="--others --exclude-standard"
  [ "${SELFTEST_HERMETIC_SEED_IGNORED:-0}" = "1" ] && seed_args="--others"
  # ⚑ FBR FINDING F1, 2026-08-16 — THIS LOOP FAILED OPEN, and it is the single
  # worst place in this file for that. The SEEDED overlay is the ONLY thing that
  # makes the two trees differ; if it silently seeds nothing, PRISTINE and SEEDED
  # are IDENTICAL, every comparison is vacuously equal, and the guard reports
  # `HERMETIC` — a green that measured nothing. This is the anti-loom the whole
  # file exists to condemn, inside the detector itself.
  #
  # MEASURED, with `cp` shimmed to fail only for destinations under .../seeded/:
  #   defect : "seeded : ... + 0 untracked path(s)"  ->  HERMETIC 5/5, exit 0
  #   control: "seeded : ... + 2 untracked path(s)"  ->  HERMETIC 5/5, exit 0
  # Same verdict, same exit code, one of them having compared two copies of the
  # same tree. `seeded_n` was PRINTED but never COMPARED TO ANYTHING — a number
  # on the screen is not a check.
  #
  # THE FIX IS A COUNT THAT MUST RECONCILE, not a louder warning: every path
  # `git ls-files` offered must land, or this is a SUBSTRATE ERROR and the guard
  # refuses to render a verdict. `mkdir` and `cp` are both checked; `|| continue`
  # was how a failed mkdir skipped a path without anyone noticing.
  #
  # ⚑ TWO FBR ROUND-3 CORRECTIONS, both in the fix above rather than the
  # original defect — a fix is not exempt from the discipline it enforces.
  #
  # (1) `git ls-files` ITSELF WAS UNCHECKED. want_n and seeded_n both derived
  #     from the same command, so a failure reconciled vacuously at `0 = 0`.
  #     FBR shimmed git so only `ls-files --others` fails (a locked or corrupt
  #     index): "0 of 0 untracked path(s)" -> HERMETIC 1/1, exit 0, against a
  #     control that correctly said DIVERGENT. `0 of 0` is indistinguishable
  #     from "there genuinely are none", and the process-substitution exit
  #     status was never read. The listing is now taken FIRST, into a file,
  #     with its status checked before anything is counted.
  #
  # (2) `-z`, BECAUSE THIS IS A REPOSITORY ABOUT AKITA. `git ls-files` C-quotes
  #     any path containing non-ASCII, a quote, a backslash or a newline, and
  #     the loop fed that raw to `cp`. FBR: one file named 秋田.txt turned this
  #     guard SUBSTRATE ERROR exit 2 with a message pointing at disk or
  #     permissions — a red nobody would ever find the cause of. The fix I had
  #     written turned a silent skip into a misdirecting hard failure; -z emits
  #     raw NUL-delimited paths and removes the parsing step entirely.
  local _lsf="$T/untracked.list"
  if ! git -C "$REPO" ls-files -z $seed_args > "$_lsf" 2>/dev/null; then
    echo "SUBSTRATE ERROR: 'git ls-files $seed_args' failed in $REPO."
    echo "  The untracked overlay cannot be built, so the seeded tree would equal"
    echo "  the pristine one and every comparison would be vacuously 'hermetic'."
    return 2
  fi
  local seeded_n=0 want_n=0 rel
  while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    case "$rel" in .git/*) continue ;; esac
    want_n=$((want_n + 1))
    if ! mkdir -p "$SEEDED/$(dirname "$rel")" 2>/dev/null; then
      echo "SUBSTRATE ERROR: could not create seed directory for '$rel' in the seeded tree"
      return 2
    fi
    if ! cp -a "$REPO/$rel" "$SEEDED/$rel" 2>/dev/null; then
      echo "SUBSTRATE ERROR: could not seed untracked path '$rel' into the seeded tree"
      echo "  Without it the seeded tree equals the pristine tree and every comparison"
      echo "  below would be vacuously 'hermetic'. Refusing to render a verdict."
      return 2
    fi
    seeded_n=$((seeded_n + 1))
  done < "$_lsf"
  if [ "$seeded_n" -ne "$want_n" ]; then
    echo "SUBSTRATE ERROR: seeded $seeded_n of $want_n untracked path(s); the overlay is incomplete."
    return 2
  fi
  local ignored_n; ignored_n=$(git -C "$REPO" ls-files --others --ignored --exclude-standard 2>/dev/null | wc -l)
  echo "   seeded   : same tracked files + $seeded_n of $want_n untracked path(s) from the working tree"
  if [ "${SELFTEST_HERMETIC_SEED_IGNORED:-0}" != "1" ] && [ "$ignored_n" -gt 0 ]; then
    echo "   NOT seeded: $ignored_n .gitignore'd path(s) — a fixture hidden in one would be MISSED here"
    echo "              (SELFTEST_HERMETIC_SEED_IGNORED=1 includes them)"
  fi
  echo ""

  # Normalise absolute paths out of a self-test's output so the only differences
  # left are differences in WORK.
  #
  # ⚑ THE /tmp RULE IS DELIBERATELY NARROW, on a reviewer finding. It used to be
  # `s|/tmp/[A-Za-z0-9._-]*|<TMP>|g`, which erased ANY /tmp path — so a guard
  # printing "phase /tmp/skipped-path" in one tree and "phase /tmp/did-real-work"
  # in the other normalised to the same string and the difference vanished. Only
  # the mktemp shape is collapsed now, because that is the only one that
  # legitimately varies per run.
  #
  # ⚑ FBR FINDING F1 (second, independent fail-open), 2026-08-16. The tree paths
  # were interpolated RAW into `s|…|…|`. A `|` or `\` or `&` in a tmpdir path
  # makes sed exit non-zero, norm_out emits NOTHING — and it does so for BOTH
  # sides, so the two normalised outputs are equal and the comparison silently
  # reports hermetic. A normaliser that fails identically on both inputs is
  # indistinguishable from agreement.
  #
  # Two countermeasures, because escaping alone is a promise and not a check:
  #   1. the paths are ESCAPED for sed (delimiter, backslash, ampersand),
  #   2. norm_out is PROBED before it is trusted — a known string must survive
  #      it and a known tree path must actually normalise. If either fails this
  #      is a SUBSTRATE ERROR, not a verdict.
  local _norm_pri _norm_seed
  _sed_esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
  norm_out() { sed -e "s|$_norm_pri|<TREE>|g" -e "s|$_norm_seed|<TREE>|g" \
                   -e 's|/tmp/tmp\.[A-Za-z0-9]\{6,\}|<TMP>|g' -e 's|[[:space:]]*$||'; }
  _norm_pri="$(_sed_esc "$PRISTINE")"; _norm_seed="$(_sed_esc "$SEEDED")"

  # PROBE norm_out before trusting it (see the F1 note above). It must (a) not
  # destroy ordinary text, and (b) actually collapse a real tree path.
  local _probe_in _probe_out
  _probe_in="keepme $PRISTINE/x $SEEDED/y"
  _probe_out="$(printf '%s\n' "$_probe_in" | norm_out 2>/dev/null)"
  if [ -z "$_probe_out" ] || case "$_probe_out" in *keepme*) false ;; *) true ;; esac; then
    echo "SUBSTRATE ERROR: the output normaliser dropped its input (probe -> '${_probe_out}')."
    echo "  A normaliser that empties both sides makes every comparison look equal."
    return 2
  fi
  if case "$_probe_out" in *"$PRISTINE"*|*"$SEEDED"*) true ;; *) false ;; esac; then
    echo "SUBSTRATE ERROR: the output normaliser did not collapse a tree path (probe -> '${_probe_out}')."
    echo "  Unnormalised tree paths would make every self-test look DIVERGENT."
    return 2
  fi

  # ── FBR FINDING F2, 2026-08-16 — THE OTHER HALF OF THE CLASS ────────────────
  # Divergence between the two trees detects a self-test that depends on an
  # UNTRACKED PATH INSIDE the repository. It is structurally blind to one that
  # depends on an ABSOLUTE PATH OUTSIDE it — the shape of the 2026-08-11 defect
  # this file's own header cites (a guard resolved through $HOME/Documents/…,
  # a private repo no runner checks out). Such a self-test behaves IDENTICALLY
  # in both trees on the author's machine, so divergence is silent and the
  # verdict was `hermetic`, exit 0.
  #
  # MEASURED on a scratch repo with a committed decoy reading an absolute path
  # outside the repo: "hermetic  outside-path-guard.sh (clean checkout: pass)",
  # HERMETIC 2/2, exit 0 — while deleting that outside file makes the decoy exit 1.
  #
  # THE INSTRUMENT: watch what the self-test actually TOUCHES (§0 — the
  # instrument is part of the measurement). Any successful file access to an
  # absolute path that is outside the checkout, outside system/toolchain
  # prefixes, and outside the run's OWN fresh TMPDIR is a dependency a runner
  # will not have.
  #
  # WHY THE FRESH TMPDIR MATTERS: guards legitimately BUILD fixtures in a
  # tmpdir. Pointing TMPDIR at a per-run directory and excluding that prefix
  # separates "made its own fixture" from "read something that was already
  # there" mechanically, with no allowlist of names to be spoofed.
  #
  # HONEST BOUND, ENFORCED IN CODE: this needs `strace`. Where it is absent the
  # sub-class is reported UNCHECKED and the summary says so — it is NOT folded
  # into a green. A guard that skips when it cannot check is the anti-loom.
  # SELFTEST_HERMETIC_NO_TRACE=1 forces the no-strace path. It exists so the
  # UNCHECKED branch can be exercised on a machine that HAS strace — an
  # untested fallback is not a fallback.
  local _HAVE_TRACE=0
  if [ "${SELFTEST_HERMETIC_NO_TRACE:-0}" != "1" ]; then
    command -v strace >/dev/null 2>&1 && _HAVE_TRACE=1
  fi
  # The git object store backing the checkout. A LINKED WORKTREE keeps its
  # objects in the ORIGINAL clone's .git, so any guard that shells out to git
  # legitimately reads a path outside its own tree — an artifact of the
  # instrument (a worktree), not of the guard. On a real `actions/checkout` the
  # common dir IS the checkout's own .git and this excludes nothing extra.
  # Computed with git, not guessed from the path shape.
  local _GITCOMMON; _GITCOMMON="$(git -C "$PRISTINE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  # The machine's own declaration of where its tools live. See rule (b) below.
  local _PATHDIRS; _PATHDIRS="$(printf '%s' "${PATH:-}" | tr ':' ' ')"
  # ⚑ REWRITTEN 2026-08-16 ON FBR ROUND-3, WHICH RETURNED CONFIRMED-DOWNGRADED
  # ON THIS FUNCTION. The first cut of this check was fail-open in FOUR
  # independent ways, and every one was silent and green. FBR named the root in
  # one sentence: it reported "no offending paths" and "I could not look"
  # THROUGH THE SAME CHANNEL — empty stdout. That is the exact defect this whole
  # file exists to condemn, written into the detector that closes it.
  # Measured by FBR against a committed outside-reading decoy:
  #   (i)   strace present but ptrace denied (container without CAP_SYS_PTRACE,
  #         yama/ptrace_scope>=2) -> `HERMETIC 2/2`, exit 0, no note at all.
  #   (ii)  `mkdir -p "$rt" || return 0` on ENOSPC/EROFS  -> `HERMETIC 2/2`, exit 0.
  #   (iii) strace roughly DOUBLES runtime (1.607s -> 3.223s measured), so the
  #         traced run is the only one that can hit the timeout; a truncated
  #         trace is non-empty, passed `-s`, and stopped before the read -> green.
  #   (iv)  `$HOME` unset under `set -u` killed the pipeline subshell: it PRINTED
  #         `HOME: unbound variable` AND RENDERED A GREEN ANYWAY.
  # It is a THREE-STATE ANSWER now, because two states cannot express it:
  #   0 = looked, nothing outside      1 = looked, offenders on stdout
  #   2 = COULD NOT LOOK               (never silently 0)
  # Vision 4: a machine works only when it can stop on its own judgment.
  outside_deps() {  # $1=guard basename ; offenders on stdout ; 0 clean / 1 found / 2 could-not-look
    local base="$1" rt="$T/trace/$base" tf="$T/trace/$base.strace" rc raw
    mkdir -p "$rt" 2>/dev/null || return 2
    [ -d "$rt" ] && [ -w "$rt" ] || return 2
    # BOUNDED, like the other two invocations — the first version had no timeout
    # and broke case [9] (10/10 -> 9/10, 69s). But a bound that fires is
    # COULD-NOT-LOOK, not clean: FBR proved a truncated trace read green twice.
    local _TO="" _tmo=0
    if command -v timeout >/dev/null; then _TO="timeout ${SELFTEST_HERMETIC_TIMEOUT:-300}"; else _tmo=1; fi
    ( cd "$PRISTINE" && TMPDIR="$rt" $_TO strace -f -qq -e trace=file -o "$tf" \
        bash "tool/$base" --self-test ) >/dev/null 2>&1
    rc=$?
    # 124/137 = the bound fired. 126/127 = strace could not exec. Any of these
    # means the trace is partial or absent, and partial is not clean.
    case "$rc" in 124|125|126|127|137) return 2 ;; esac
    [ "$_tmo" -eq 1 ] && return 2   # unbounded run: we cannot certify it completed
    [ -s "$tf" ] || return 2        # was `return 0` — the ptrace-denied fail-open
    # An strace log always records the exec of the traced program. If that line
    # is missing, strace never attached and what we have is not a trace.
    command grep -q 'execve\|exec_arg\|+++ exited' "$tf" 2>/dev/null || return 2
    raw="$(
      command grep -vE 'ENOENT|EACCES|ENOTDIR|= -1' "$tf" 2>/dev/null \
        | command grep -oE '"(/[^"]*)"' | tr -d '"' \
        | command grep -vE '^/(usr|lib|lib64|lib32|etc|proc|sys|dev|bin|sbin|var|opt|run|snap)/' \
        | command grep -vxF -e /tmp -e /home -e / \
        | while IFS= read -r p; do
            case "$p" in
              "$PRISTINE"|"$PRISTINE"/*) continue ;;
              "$SEEDED"|"$SEEDED"/*)     continue ;;
              "$T"|"$T"/*)               continue ;;
            esac
            # ⚑ `"$REPO"/*` USED TO BE EXCLUDED HERE AND IS NOT ANY MORE. FBR:
            # that exclusion covered the LIVE CHECKOUT, which is exactly where
            # untracked fixtures live — so a self-test reading
            # `/abs/path/to/repo/assets/tiles/gunma_offline.mbtiles` was
            # invisible to BOTH halves of this guard. That is this file's OWN
            # FOUNDING DEFECT, written by absolute path instead of relative,
            # and it read green. The git common dir below still covers the
            # object store, which is the only part of $REPO a guard has any
            # business touching.
            if [ -n "$_GITCOMMON" ]; then
              case "$p" in "$_GITCOMMON"|"$_GITCOMMON"/*) continue ;; esac
            fi
            # TOOLCHAIN, by a MECHANICAL rule and not a name list. Two rules,
            # because FBR broke the first one on this very machine:
            #   (a) dot-paths under $HOME — ~/.local/lib/python*/site-packages,
            #       ~/.gitconfig, ~/.pub-cache: the toolchain being itself.
            #   (b) ⚑ ANY PATH UNDER A DIRECTORY ON $PATH. The dot rule assumed
            #       toolchains install into dot-directories. This machine's
            #       Flutter SDK is /home/komada/flutter/bin/flutter — NO DOT —
            #       so an entirely honest self-test that shells out to the real
            #       SDK was reported OUTSIDE-REPO, a hard RED on a healthy
            #       guard, on the developer's machine, green in CI. That
            #       inverts this check's purpose and is the deletion-within-a-
            #       week mode. $PATH is the machine's own declaration of where
            #       its tools live; using it needs no list from us.
            case "${HOME:-}" in "") : ;; *) case "$p" in "$HOME"/.*) continue ;; esac ;; esac
            local _d _hit=0
            for _d in $_PATHDIRS; do
              case "$p" in "$_d"/*) _hit=1; break ;; esac
            done
            [ "$_hit" -eq 1 ] && continue
            # REGULAR FILES ONLY. Measured: the invoking process's own cwd
            # appears in every trace as a DIRECTORY stat and made this flag two
            # provably-hermetic guards. What breaks on a runner is a FILE READ.
            # BOUND: a dependence on an outside DIRECTORY merely existing is
            # not detected. Stated, not assumed away.
            [ -f "$p" ] && printf '%s\n' "$p"
          done | sort -u
    )"
    [ -n "$raw" ] && { printf '%s\n' "$raw"; return 1; }
    return 0
  }

  local g
  for g in "$PRISTINE"/tool/*.sh; do
    [ -f "$g" ] || continue
    local base; base="$(basename "$g")"
    [ "$base" = "$SELF_BASENAME" ] && continue

    # ADVERSARIAL-REVIEW C6, 2026-08-16. Discovery was `grep -q -- '--self-test'`, a
    # TEXT match that also hits comments and usage strings. The reviewer built a guard
    # whose only mention of --self-test was a usage comment and whose main path
    # had a side effect: this script RAN THE MAIN PATH with --self-test as a
    # positional argument, the side effect landed in the LIVE repo, and the
    # verdict was `hermetic`. Discovery must therefore ask whether the script
    # BRANCHES on the flag, not whether it mentions it. Comment lines are
    # stripped first; all five guards here use `[[ "${1:-}" == "--self-test" ]]`
    # or `[ "${1:-}" = "--self-test" ]` or a `--self-test)` case arm.
    #
    # And a script that ADVERTISES the flag without implementing it is not
    # silently skipped either — that is a guard nobody can invoke, which is the
    # same "never actually ran" class this file exists for. It is a finding.
    # NOT a pipeline, deliberately. Written first as
    #   grep -v '^[[:space:]]*#' "$g" | grep -qE '…' && branches=1
    # which is WRONG under `set -o pipefail`: `grep -qE` exits at the first
    # match, `grep -v` takes SIGPIPE, the pipeline status becomes 141, and
    # `&& branches=1` never fires. It is also NONDETERMINISTIC — it depends on
    # whether the writer finished before the reader exited, so it passed for
    # four guards and misreported the fifth (preflight_play_upload.sh, whose
    # match sits ~70 lines into the filtered stream) as ADVERTISED. Caught by
    # re-running against the real repo after the self-test went 7/7: the
    # self-test's fixtures were all too small to trip it. Substituting the
    # intermediate result removes the pipe and the race together.
    # ⚑ THE PREDICATE WAS REWRITTEN 2026-08-16, second adversarial round, because
    # the first version REOPENED the very finding it closed. It was
    #   (\[\[|\[)[^]]*--self-test|--self-test[[:space:]]*\)
    # and the `\[` alternative matches the bracket in a USAGE STRING:
    #   echo "usage: $0 [--self-test] <archive>"
    # That line is not a comment, so comment-stripping cannot save it, and
    # `usage: cmd [--flag]` is the single most idiomatic way anyone writes an
    # optional flag. Measured: such a script was classified as branching, its
    # MAIN path executed in both trees, and the verdict was `hermetic`, exit 0.
    # The same regex ALSO rejected two working implementations —
    # `case "${1:-}" in "--self-test")` and `test "${1:-}" = --self-test` —
    # as ADVERTISED, a hard RED on a healthy guard, which is the cry-wolf mode
    # case [2] of this file's self-test exists to prevent.
    #
    # A branch is not a bracket. It is a COMPARISON against the flag, or a CASE
    # ARM whose pattern IS the flag. Pure-output lines are dropped alongside
    # comments, because echo/printf/cat name flags without branching on them.
    # Proven against a 17-case corpus of real implementations and real prose,
    # which is carried as case [8] of this script's own --self-test.
    local mentions=0 branches=0 logic
    grep -q -- '--self-test' "$g" && mentions=1
    logic=$(grep -vE '^[[:space:]]*#' "$g" 2>/dev/null | grep -vE '^[[:space:]]*(echo|printf|cat)\b') || logic=""
    if grep -qE '(\[\[|\[|\btest\b)[^#]*(==|=)[[:space:]]*("|'"'"')?--self-test' <<<"$logic"; then
      branches=1
    elif grep -qE '(^|[[:space:]]|\|)("|'"'"')?--self-test("|'"'"')?[[:space:]]*\)' <<<"$logic"; then
      branches=1
    fi
    if [ "$branches" -eq 0 ]; then
      if [ "$mentions" -eq 1 ]; then
        printf '   ADVERTISED     %-36s (names --self-test but never branches on it)\n' "$base"
        advertised=$((advertised + 1))
      fi
      continue
    fi
    found=$((found + 1))

    # ADVERSARIAL-REVIEW C10, 2026-08-16: a hung self-test hung the whole CI job, since
    # nothing bounded these two invocations. `timeout` where available.
    local TO=""; command -v timeout >/dev/null && TO="timeout ${SELFTEST_HERMETIC_TIMEOUT:-300}"
    local p_exit s_exit p_out s_out p_out2 p_exit2
    p_out=$(  cd "$PRISTINE" && $TO bash "tool/$base" --self-test 2>&1 ); p_exit=$?
    s_out=$(  cd "$SEEDED"   && $TO bash "tool/$base" --self-test 2>&1 ); s_exit=$?
    # Run the pristine side TWICE. If a self-test is not stable against itself —
    # $$, $RANDOM, a timestamp, a hash-ordered loop — then a difference between
    # trees proves nothing, and reporting DIVERGENT on it would be a flake that
    # gets this whole check deleted within a week. Instability is its own
    # verdict. (Reviewer finding: latent here, all five guards stable, but the
    # check costs one extra run and removes the failure mode.)
    p_out2=$( cd "$PRISTINE" && $TO bash "tool/$base" --self-test 2>&1 ); p_exit2=$?
    if [ "$p_exit" -ne "$p_exit2" ] || [ "$(norm_out <<<"$p_out")" != "$(norm_out <<<"$p_out2")" ]; then
      printf '   UNSTABLE       %-36s (two runs in the SAME tree disagree — divergence is unreadable)\n' "$base"
      unstable=$((unstable + 1))
      continue
    fi

    # F2 — outside-the-repo dependency check, before the divergence branches,
    # because divergence is structurally blind to this class.
    # Gated on p_exit==0 deliberately. This class is about a self-test that
    # PASSES on this machine because a path only this machine has is present.
    # One that fails or hangs here is already caught by the branches below, and
    # tracing it would add a fourth unbounded-ish run for no verdict — which is
    # exactly how the first version of this check broke case [9].
    if [ "$_HAVE_TRACE" -eq 1 ] && [ "$p_exit" -eq 0 ]; then
      local _od _odrc
      _od="$(outside_deps "$base")"; _odrc=$?
      if [ "$_odrc" -eq 1 ]; then
        printf '   OUTSIDE-REPO   %-36s (self-test reads path(s) no runner checks out)\n' "$base"
        printf '%s\n' "$_od" | head -5 | sed 's/^/                    /'
        outside=$((outside + 1))
        continue
      elif [ "$_odrc" -eq 2 ]; then
        # COULD NOT LOOK. Reported on its own line and counted, never folded
        # into the green — this is the whole point of the third state.
        printf '   trace-UNCHECKED %-35s (could not trace it; outside-repo class NOT checked)\n' "$base"
        outside_unchecked=$((outside_unchecked + 1))
      fi
    else
      outside_unchecked=$((outside_unchecked + 1))
    fi

    if [ "$p_exit" -eq 0 ] && [ "$s_exit" = "0" ]; then
      # ADVERSARIAL-REVIEW C5, 2026-08-16. Exit codes alone cannot tell "ran and passed"
      # from "SKIPPED because its fixture was absent, and exited 0". The reviewer built
      # exactly that guard — `[ -f fixture ] || { echo skipping; exit 0; }` with
      # an untracked fixture — and this script called it `hermetic`, exit 0.
      # That is the anti-loom this file's own remediation text forbids, and it
      # is the single most likely WRONG FIX a future author applies in response
      # to a NON-HERMETIC verdict from this very guard. A self-test that did the
      # same work in both trees says the same thing in both trees; one that
      # skipped in the clean checkout cannot. Compare the WORK, not just the code.
      # Both pass. Same script, and the ONLY difference between the trees is the
      # untracked content — so a difference in output is a dependence on it.
      # This is the skip-on-absence signature, and there is no exemption here to
      # switch off: uncommitted source edits are invisible to both runs.
      if [ "$(norm_out <<<"$p_out")" != "$(norm_out <<<"$s_out")" ]; then
        printf '   DIVERGENT      %-36s (passes in BOTH trees but does DIFFERENT work with untracked files present)\n' "$base"
        divergent=$((divergent + 1))
      else
        printf '   hermetic       %-36s (clean checkout: pass)\n' "$base"
        hermetic=$((hermetic + 1))
      fi
    elif [ "$p_exit" -eq 0 ]; then
      printf '   hermetic       %-36s (clean checkout: pass; FAILS with untracked files present, exit=%s)\n' "$base" "$s_exit"
      hermetic=$((hermetic + 1)); livebroken=$((livebroken + 1))
    elif [ "$s_exit" = "0" ]; then
      printf '   NON-HERMETIC   %-36s (clean checkout: FAIL exit=%s · with untracked files: pass)\n' "$base" "$p_exit"
      nonhermetic=$((nonhermetic + 1))
    else
      printf '   UNDETERMINED   %-36s (fails in BOTH trees; clean=%s seeded=%s)\n' "$base" "$p_exit" "$s_exit"
      undetermined=$((undetermined + 1))
    fi
  done

  echo ""
  if [ "$found" -eq 0 ]; then
    echo "FAIL — no tool/*.sh that BRANCHES on --self-test was found in the clean checkout."
    echo "       A guard that is not IN the checkout cannot run on a runner. That is the"
    echo "       shape of the 2026-08-11 private-path defect; treat it as RED."
    return 1
  fi

  if [ "$advertised" -gt 0 ]; then
    echo "ADVERTISED-NOT-IMPLEMENTED: $advertised script(s) name --self-test but never"
    echo "              branch on it, so invoking it runs the script's MAIN path with"
    echo "              --self-test as an argument. Nobody can actually self-test them,"
    echo "              and a caller who tries gets a side effect instead of a check."
    return 1
  fi

  if [ "$outside" -gt 0 ]; then
    cat <<'MSG'
OUTSIDE-REPO: a --self-test reads an absolute path that is not in the checkout,
           is not a system path, and is not a fixture it built itself. It passes
           here because that path exists on THIS machine. A runner has no such
           file, so the self-test either fails or — worse — skips and exits 0.
           This is the 2026-08-11 defect's own shape: a guard resolved through a
           private path no runner ever checks out.
           FIX: vendor the fixture into the repository, or have the self-test
           BUILD it. Do not make the self-test tolerate the absence.
MSG
    return 1
  fi

  if [ "$divergent" -gt 0 ]; then
    cat <<'MSG'
DIVERGENT: a --self-test passes in BOTH trees but produces different output in
           each, so it did DIFFERENT WORK in a clean checkout than it does here.
           The usual cause is a self-test that SKIPS when its fixture is absent
           and exits 0 — which is green for a reason no runner reproduces, and
           is precisely the anti-loom named below. Do not "fix" this by
           silencing the difference; make the self-test do the same work in
           every checkout, by BUILDING what it needs.
MSG
    return 1
  fi

  if [ "$nonhermetic" -gt 0 ]; then
    cat <<'MSG'
NON-HERMETIC: a --self-test passes on this machine and FAILS in a clean checkout.
              It is reading something that is not in the repository — an untracked
              fixture, a generated artifact, an absolute path into another tree.
              On a runner it can only ever be red, or (worse) it was green for a
              reason no one cloning this repo can reproduce.
              Fix it by BUILDING the fixture, not by finding it: write it into
              `mktemp -d` the way assert_manifest_perms.sh does, or reconstruct it
              from git history the way loom_mutation_gate.sh does. Do NOT soften
              the self-test into skipping when its fixture is absent — a gate that
              skips when it cannot check is the anti-loom.
MSG
    return 1
  fi

  if [ "$unstable" -gt 0 ]; then
    echo "UNSTABLE: $unstable self-test(s) disagree with THEMSELVES across two runs in the"
    echo "          same tree, so a difference between trees cannot be read as dependence"
    echo "          on untracked files. Not green: make the self-test deterministic."
    return 3
  fi

  if [ "$undetermined" -gt 0 ]; then
    echo "UNDETERMINED: $undetermined self-test(s) fail in BOTH trees, so hermeticity"
    echo "              cannot be read off them. Not green: a check that could not"
    echo "              check must never report success. Fix the failure, re-run."
    return 3
  fi

  [ "$livebroken" -gt 0 ] && {
    echo "NOTE: $livebroken self-test(s) pass in a clean checkout but FAIL once untracked"
    echo "      files are present — something on the working tree breaks them. Not a"
    echo "      hermeticity defect (a runner never sees it), but worth knowing."
  }
  echo "HERMETIC: $hermetic/$found self-test(s) run from a clean checkout."
  # The outside-repo sub-class is NOT folded into this green when it could not
  # be checked. UNVERIFIED, never *cleared* (OPS-069(A)).
  if [ "$outside_unchecked" -gt 0 ]; then
    echo "   NOTE: the OUTSIDE-REPO sub-class was UNCHECKED for $outside_unchecked self-test(s)"
    echo "         (\`strace\` absent, or the trace could not be taken). Divergence cannot"
    echo "         see that class, so this verdict covers untracked-INSIDE-the-repo only."
    # ⚑ FBR ROUND-3: "UNVERIFIED that clears the gate is cleared." The note above
    # is prose scrolling past in a log, and ci.yml reads the EXIT CODE. Worse,
    # FBR measured that on a real runner checkout there are ZERO
    # untracked-not-ignored paths, so PRISTINE and SEEDED are byte-identical and
    # NON-HERMETIC and DIVERGENT are STRUCTURALLY UNREACHABLE in CI — this check
    # is the only one in this file that can fire there at all.
    # So CI sets SELFTEST_HERMETIC_REQUIRE_TRACE=1 and installs strace, and an
    # UNCHECKED sub-class is then a hard fail-closed 3, exactly like UNDETERMINED.
    # It is opt-in rather than default because a developer machine without strace
    # should still get the other verdicts, not a permanent red.
    if [ "${SELFTEST_HERMETIC_REQUIRE_TRACE:-0}" = "1" ]; then
      echo "   REQUIRE_TRACE=1 and the outside-repo class could not be checked."
      echo "   Fail-closed: a green here would be a verdict nobody took."
      return 3
    fi
  fi
  return 0
}

# --------------------------------------------------------------- --self-test
# Prove this script BITES the real defect before trusting it to judge — the same
# discipline loom_mutation_gate.sh applies to every other guard here: a guard
# nobody has watched fail is not known to guard anything. The mutant below is
# the 2026-08-11 shape exactly: a tracked guard whose --self-test reads a fixture
# that exists on the author's disk and is not in the repository.
if [[ "${1:-}" == "--self-test" ]]; then
  command -v git >/dev/null || { echo "SELF-TEST SUBSTRATE ERROR: git absent"; exit 2; }
  # ADVERSARIAL-REVIEW C1, 2026-08-16 — the same emptiness check as check_repo(). With
  # `mktemp` shimmed to a bare `exit 0`, this proceeded to `mkdir -p /repo/tool`
  # and `git init -q /repo`, and its EXIT trap became `rm -rf ""`.
  T=$(mktemp -d) || { echo "SELF-TEST SUBSTRATE ERROR: mktemp failed"; exit 2; }
  [ -n "$T" ] && [ -d "$T" ] || { echo "SELF-TEST SUBSTRATE ERROR: mktemp produced no usable directory"; exit 2; }
  trap 'rm -rf "$T"' EXIT
  R="$T/repo"
  mkdir -p "$R/tool" "$R/assets" || { echo "SELF-TEST SUBSTRATE ERROR: mkdir failed"; exit 2; }
  git init -q "$R" 2>/dev/null || { echo "SELF-TEST SUBSTRATE ERROR: git init failed"; exit 2; }
  git -C "$R" config user.email selftest@localhost
  git -C "$R" config user.name  selftest

  # A guard in the 2026-08-11 shape: its fixture is FOUND, not BUILT.
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
APP="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
if [[ "${1:-}" == "--self-test" ]]; then
  SRC="$APP/assets/fixture.bin"
  [ -f "$SRC" ] || { echo "SELF-TEST FAILED: fixture absent at $SRC"; exit 1; }
  echo "self-test 1/1 OK"; exit 0
fi
exit 0
GUARD
  chmod +x "$R/tool/fake-guard.sh"
  git -C "$R" add tool/fake-guard.sh
  git -C "$R" commit -qm "a guard whose fixture is found, not built"

  pass=0; total=12

  # ADVERSARIAL-REVIEW C7, 2026-08-16. This self-test had THREE cases against SEVEN
  # verdicts, and the reviewer proved the gap by mutation: neutering the `found==0`
  # branch, the discovery predicate, or the live-exit check each left the
  # self-test reporting 3/3, exit 0. Three surviving mutants in the guard whose
  # entire purpose is to catch checks that never ran. Cases [4]-[7] close them.
  # By this file's own standard a verdict with no case is a verdict nobody has
  # watched fire.
  echo ">> SELF-TEST: does this bite a self-test that reads outside the checkout?"
  echo ""

  # [1] MUTANT — the real defect. Fixture on disk, absent from the repository.
  printf 'fixture bytes' > "$R/assets/fixture.bin"
  echo "   [1] fixture present on disk but UNTRACKED — must be NON-HERMETIC (exit 1):"
  out1=$(check_repo "$R" 2>&1); e1=$?
  grep -E 'NON-HERMETIC|HERMETIC|UNDETERMINED' <<<"$out1" | head -2 | sed 's/^/       /'
  if [ "$e1" -eq 1 ] && grep -q 'NON-HERMETIC   fake-guard.sh' <<<"$out1"; then
    echo "       => BITES. exit=$e1"; pass=$((pass + 1))
  else
    echo "       => MISSED the real defect. exit=$e1 — this script is worthless."
  fi
  echo ""

  # [2] HEALTHY — the same fixture, now tracked. Must NOT cry wolf.
  git -C "$R" add assets/fixture.bin
  git -C "$R" commit -qm "track the fixture"
  echo "   [2] same fixture, now TRACKED — must be HERMETIC (exit 0):"
  out2=$(check_repo "$R" 2>&1); e2=$?
  grep -E 'NON-HERMETIC|HERMETIC|UNDETERMINED' <<<"$out2" | head -2 | sed 's/^/       /'
  if [ "$e2" -eq 0 ]; then
    echo "       => accepts it. exit=$e2"; pass=$((pass + 1))
  else
    echo "       => CRIES WOLF on a hermetic guard. exit=$e2 — it will be suppressed within a day."
  fi
  echo ""

  # [3] FAIL-CLOSED — a self-test that fails everywhere must never be green.
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
if [[ "${1:-}" == "--self-test" ]]; then echo "always fails"; exit 1; fi
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh
  git -C "$R" commit -qm "a self-test that fails everywhere"
  echo "   [3] a self-test failing in BOTH trees — must be UNDETERMINED (exit 3), never 0:"
  out3=$(check_repo "$R" 2>&1); e3=$?
  grep -E 'NON-HERMETIC|HERMETIC|UNDETERMINED' <<<"$out3" | head -2 | sed 's/^/       /'
  if [ "$e3" -eq 3 ]; then
    echo "       => fail-closed. exit=$e3"; pass=$((pass + 1))
  else
    echo "       => did not fail closed. exit=$e3"
  fi
  echo ""

  # [4] SKIP-ON-ABSENCE — the anti-loom this guard's own remediation text
  #     forbids, and the most likely WRONG FIX someone applies after reading a
  #     NON-HERMETIC verdict from this very script. Exit codes cannot see it:
  #     it exits 0 in both trees. Only the WORK differs.
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
APP="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
if [[ "${1:-}" == "--self-test" ]]; then
  SRC="$APP/assets/skipme.bin"
  [ -f "$SRC" ] || { echo "fixture absent - SKIPPING"; exit 0; }
  echo "self-test 1/1 OK"; exit 0
fi
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh
  git -C "$R" commit -qm "a self-test that SKIPS when its fixture is absent"
  printf 'x' > "$R/assets/skipme.bin"     # present on disk, UNTRACKED
  echo "   [4] a self-test that SKIPS on absent fixture (exit 0 in BOTH trees) — must be DIVERGENT (exit 1):"
  out4=$(check_repo "$R" 2>&1); e4=$?
  grep -E 'DIVERGENT|HERMETIC|NON-HERMETIC|UNDETERMINED' <<<"$out4" | head -2 | sed 's/^/       /'
  if [ "$e4" -eq 1 ] && grep -q 'DIVERGENT      fake-guard.sh' <<<"$out4"; then
    echo "       => BITES a green that skipped. exit=$e4"; pass=$((pass + 1))
  else
    echo "       => called a SKIP hermetic. exit=$e4 — the anti-loom passed."
  fi
  rm -f "$R/assets/skipme.bin"
  echo ""

  # [5] ADVERTISED-NOT-IMPLEMENTED — a USAGE STRING, not a comment. Must NOT be
  #     executed (its main path has a side effect) and must be a finding.
  #
  #     ⚑ THIS CASE PASSED FOR THE WRONG REASON until 2026-08-16. It used to
  #     ship a repo whose ONLY script was the advertising one, so when the
  #     ADVERTISED gate was mutated away the run fell through to the `found==0`
  #     branch — which also exits 1 — and the case still passed. The reviewer
  #     proved it by mutating `advertised -gt 0` to `-gt 1` and watching 7/7
  #     survive. In the file that documents that failure class. A REAL guard now
  #     sits beside the advertising one, so `found` is non-zero and only the
  #     ADVERTISED gate can produce the exit, and the assertion names the
  #     ADVERTISED summary line rather than any exit-1.
  #
  #     The usage string is deliberate and is the reviewer's C6(a) repro: the
  #     bracket in `[--self-test]` matched the old predicate's `\[` alternative,
  #     so this script was classified as branching and its main path ran in
  #     BOTH trees, landing two side-effect files, verdict `hermetic`, exit 0.
  cat > "$R/tool/real-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "--self-test" ]]; then echo "self-test 1/1 OK"; exit 0; fi
exit 0
GUARD
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
echo "usage: $0 [--self-test] <archive>"
touch "$(dirname "$0")/../SIDE_EFFECT_ran"
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh tool/real-guard.sh
  git -C "$R" commit -qm "a guard that advertises --self-test in a usage string but never branches"
  rm -f "$R/SIDE_EFFECT_ran"
  echo "   [5] --self-test named only in a USAGE STRING — must be ADVERTISED (exit 1), NOT executed:"
  out5=$(check_repo "$R" 2>&1); e5=$?
  grep -E 'ADVERTISED|HERMETIC|DIVERGENT' <<<"$out5" | head -2 | sed 's/^/       /'
  if [ "$e5" -eq 1 ] && grep -q 'ADVERTISED-NOT-IMPLEMENTED' <<<"$out5" \
     && grep -q 'ADVERTISED     fake-guard.sh' <<<"$out5" \
     && grep -q 'hermetic       real-guard.sh' <<<"$out5" \
     && [ ! -e "$R/SIDE_EFFECT_ran" ]; then
    echo "       => reported via the ADVERTISED gate, real guard still seen, main path NOT run. exit=$e5"
    pass=$((pass + 1))
  else
    echo "       => exit=$e5, side-effect-present=$([ -e "$R/SIDE_EFFECT_ran" ] && echo YES || echo no)"
  fi
  rm -f "$R/SIDE_EFFECT_ran"
  git -C "$R" rm -q tool/real-guard.sh; git -C "$R" commit -qm "drop the companion guard"
  echo ""

  # [6] NO GUARDS AT ALL — the `found==0` branch, whose own message calls it the
  #     2026-08-11 private-path shape. Never once exercised before today.
  git -C "$R" rm -q tool/fake-guard.sh
  git -C "$R" commit -qm "no guard advertising --self-test remains"
  echo "   [6] no tool/*.sh branching on --self-test — must be RED (exit 1), never green:"
  out6=$(check_repo "$R" 2>&1); e6=$?
  grep -E 'FAIL|HERMETIC' <<<"$out6" | head -2 | sed 's/^/       /'
  if [ "$e6" -eq 1 ]; then
    echo "       => RED on an empty checkout. exit=$e6"; pass=$((pass + 1))
  else
    echo "       => an empty checkout reported green. exit=$e6"
  fi
  echo ""

  # [7] LIVE-TREE-ONLY BREAKAGE — pristine passes, live fails. Hermeticity IS
  #     answered, so this must stay exit 0 with a NOTE. Guards the live-exit
  #     read that mutation showed was untested: without it this case would be
  #     indistinguishable from [2] and the NOTE would never appear.
  mkdir -p "$R/tool"   # [6] git-rm'd the last file in tool/, so git removed the dir
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
APP="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
if [[ "${1:-}" == "--self-test" ]]; then
  [ -f "$APP/BREAK_LIVE" ] && { echo "self-test 0/1 broken here"; exit 1; }
  echo "self-test 1/1 OK"; exit 0
fi
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh
  git -C "$R" commit -qm "a guard broken only by an uncommitted local file"
  printf 'x' > "$R/BREAK_LIVE"            # untracked: invisible to the pristine tree
  echo "   [7] pristine passes, LIVE tree broken by an uncommitted file — must be exit 0 + NOTE:"
  out7=$(check_repo "$R" 2>&1); e7=$?
  grep -E 'NOTE|HERMETIC|NON-HERMETIC' <<<"$out7" | head -2 | sed 's/^/       /'
  if [ "$e7" -eq 0 ] && grep -q 'NOTE:' <<<"$out7"; then
    echo "       => distinguishes a dirty tree from a hermeticity defect. exit=$e7"; pass=$((pass + 1))
  else
    echo "       => did not separate the two. exit=$e7"
  fi
  rm -f "$R/BREAK_LIVE"
  echo ""

  # [8] THE DISCOVERY PREDICATE ITSELF, against a corpus. This is the check that
  #     decides whether a script is even LOOKED AT, so a defect here silences
  #     everything downstream — which is exactly what happened: the first
  #     predicate matched the bracket in a usage string and re-opened a closed
  #     finding, while rejecting two working implementations. Real spellings on
  #     one side, prose that merely names the flag on the other.
  echo "   [8] discovery predicate vs a corpus of real branches and mere prose:"
  pred_ok=1
  pred_says() {   # 0 = classified as branching
    local logic
    logic=$(grep -vE '^[[:space:]]*#' <<<"$1" | grep -vE '^[[:space:]]*(echo|printf|cat)\b')
    grep -qE '(\[\[|\[|\btest\b)[^#]*(==|=)[[:space:]]*("|'"'"')?--self-test' <<<"$logic" && return 0
    grep -qE '(^|[[:space:]]|\|)("|'"'"')?--self-test("|'"'"')?[[:space:]]*\)' <<<"$logic" && return 0
    return 1
  }
  chk_pred() {    # want(branch|none)  label  text
    if pred_says "$3"; then got=branch; else got=none; fi
    [ "$got" = "$1" ] || { echo "       MISCLASSIFIED as $got: $2"; pred_ok=0; }
  }
  chk_pred branch 'if [[ "${1:-}" == "--self-test" ]]'   'if [[ "${1:-}" == "--self-test" ]]; then :; fi'
  chk_pred branch 'if [ "${1:-}" = "--self-test" ]'      'if [ "${1:-}" = "--self-test" ]; then :; fi'
  chk_pred branch 'if test "${1:-}" = --self-test'       'if test "${1:-}" = --self-test; then :; fi'
  chk_pred branch '[[ $1 == --self-test ]]'              '[[ $1 == --self-test ]] && run'
  chk_pred branch 'case in "--self-test")'               'case "${1:-}" in "--self-test") run ;; esac'
  chk_pred branch 'case in --self-test)'                 'case "$1" in --self-test) run ;; esac'
  chk_pred branch 'case arm, alternation'                'case "$1" in -t|--self-test) run ;; esac'
  chk_pred none   'echo "usage: $0 [--self-test] ..."'   'echo "usage: $0 [--self-test] <archive>"'
  chk_pred none   'comment usage line'                   '# usage: g.sh --self-test'
  chk_pred none   'help text listing the flag'           'echo "  --self-test    prove the guards fail"'
  chk_pred none   'echo "usage: $0 (--self-test)"'       'echo "usage: $0 (--self-test)"'
  chk_pred none   'heredoc naming the flag'              'cat <<EOF
usage: $0 [--self-test]
EOF'
  if [ "$pred_ok" -eq 1 ]; then
    echo "       => 12/12 classified correctly. exit=0"; pass=$((pass + 1))
  else
    echo "       => the predicate misclassifies; discovery is unsound."
  fi
  echo ""

  # [9] A HUNG SELF-TEST must be bounded, or one guard hangs the whole CI job.
  #     Nothing tested the timeout, so it was free to be deleted.
  mkdir -p "$R/tool"
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "--self-test" ]]; then sleep 60; exit 0; fi
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh
  git -C "$R" commit -qm "a self-test that hangs"
  echo "   [9] a self-test that HANGS — must be bounded and never green:"
  t0=$(date +%s)
  out9=$(SELFTEST_HERMETIC_TIMEOUT=3 check_repo "$R" 2>&1); e9=$?
  t1=$(date +%s)
  if [ "$e9" -ne 0 ] && [ $((t1 - t0)) -lt 45 ]; then
    echo "       => bounded at $((t1 - t0))s, exit=$e9 (not green)"; pass=$((pass + 1))
  else
    echo "       => took $((t1 - t0))s, exit=$e9 — the timeout is not load-bearing."
  fi
  echo ""

  # [10] A SELF-TEST THAT DISAGREES WITH ITSELF. Divergence is a comparison, and
  #      a comparison against a moving value is a coin toss. A flaky DIVERGENT
  #      would get this whole check deleted, so instability is its own verdict.
  cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "--self-test" ]]; then echo "run id $$ $RANDOM"; exit 0; fi
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh
  git -C "$R" commit -qm "a self-test whose output changes every run"
  echo "   [10] a self-test whose own output changes run to run — must be UNSTABLE (exit 3):"
  out10=$(check_repo "$R" 2>&1); e10=$?
  grep -E 'UNSTABLE|HERMETIC|DIVERGENT' <<<"$out10" | head -2 | sed 's/^/       /'
  if [ "$e10" -eq 3 ] && grep -q 'UNSTABLE' <<<"$out10"; then
    echo "       => refuses to read divergence off a coin toss. exit=$e10"; pass=$((pass + 1))
  else
    echo "       => reported a flake as a verdict. exit=$e10"
  fi

  # [11] FBR FINDING F2 — THE OUTSIDE-THE-REPO CLASS, which divergence is
  #      structurally blind to. A self-test reading an ABSOLUTE path outside the
  #      checkout behaves IDENTICALLY in both trees on this machine, so the old
  #      verdict was `hermetic`, exit 0. This is the 2026-08-11 defect's own
  #      shape. Two halves, because a detector that only ever fires is a
  #      cry-wolf: the outside-reader must be CAUGHT, and a guard that builds
  #      its OWN fixture in a tmpdir must NOT be.
  # ⚑ FBR ROUND-3 caught TWO defects in this one line, both written THIS round,
  # in the file that carries a paragraph about carrying countermeasures forward.
  # It was `local OUTDIR; OUTDIR="$(mktemp -d)"` — `local` outside a function,
  # which bash reports on stderr on EVERY run; and an UNCHECKED `mktemp -d`,
  # which is FBR's own round-1 finding reintroduced by the seat that fixed it.
  # Unchecked, `OUTDIR` is empty, the fixture is written to `/fx.txt` and the
  # cleanup becomes `rm -rf ""`.
  OUTDIR="$(mktemp -d 2>/dev/null)" || { echo "   [11] SUBSTRATE: mktemp -d failed; cannot build the fixture."; exit 2; }
  [ -d "$OUTDIR" ] || { echo "   [11] SUBSTRATE: mktemp -d gave '$OUTDIR', not a directory."; exit 2; }
  echo outside > "$OUTDIR/fx.txt"
  cat > "$R/tool/fake-guard.sh" <<GUARD
#!/usr/bin/env bash
set -uo pipefail
if [[ "\${1:-}" == "--self-test" ]]; then
  [ -f "$OUTDIR/fx.txt" ] && { echo "self-test 1/1 OK"; exit 0; }
  echo "SELF-TEST FAILED: fixture absent"; exit 1
fi
exit 0
GUARD
  cat > "$R/tool/honest-tmp-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "--self-test" ]]; then
  d=$(mktemp -d) || exit 2
  echo fixture > "$d/built.txt"
  [ -f "$d/built.txt" ] && echo "self-test 1/1 OK"
  rm -rf "$d"; exit 0
fi
exit 0
GUARD
  git -C "$R" add tool/fake-guard.sh tool/honest-tmp-guard.sh
  git -C "$R" commit -qm "one guard reads outside the repo; one builds its own fixture"
  echo "   [11] a self-test reading an ABSOLUTE PATH OUTSIDE the checkout — must be OUTSIDE-REPO (exit 1):"
  out11=$(check_repo "$R" 2>&1); e11=$?
  grep -E 'OUTSIDE-REPO|HERMETIC|hermetic ' <<<"$out11" | head -3 | sed 's/^/       /'
  if ! command -v strace >/dev/null 2>&1; then
    # UNVERIFIED, never *cleared* — and it does not silently score a point.
    echo "       => SKIPPED: strace absent, so this case cannot run. NOT counted as a pass."
    total=$((total - 1))
  elif [ "$e11" -eq 1 ] \
       && grep -q 'OUTSIDE-REPO   fake-guard.sh' <<<"$out11" \
       && ! grep -q 'OUTSIDE-REPO   honest-tmp-guard.sh' <<<"$out11"; then
    echo "       => bites the outside reader, and does NOT cry wolf on a self-built tmp fixture. exit=$e11"
    pass=$((pass + 1))
  else
    echo "       => MISSED the outside-the-repo dependency, or cried wolf on the honest one. exit=$e11"
  fi
  rm -rf "$OUTDIR"
  rm -f "$R/tool/honest-tmp-guard.sh"

  # [12] FBR ROUND-3 — THE COULD-NOT-LOOK STATE. Every one of the four
  #      fail-opens FBR found reported "no offending paths" and "I could not
  #      look" through the same channel. The third state has to have a case of
  #      its own, or the next author collapses it back to two. `strace` is
  #      shimmed to write the empty -o file it opens before attaching, then
  #      fail — the ptrace-denied shape (container without CAP_SYS_PTRACE,
  #      yama/ptrace_scope>=2), which FBR measured as HERMETIC 2/2 exit 0.
  if ! command -v strace >/dev/null 2>&1; then
    echo "   [12] SKIPPED: strace absent, so the could-not-look state cannot be exercised."
    total=$((total - 1))
  else
    SHIMDIR="$(mktemp -d 2>/dev/null)" || { echo "   [12] SUBSTRATE: mktemp -d failed."; exit 2; }
    cat > "$SHIMDIR/strace" <<'SHIM'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -o) shift; : > "$1";; esac; shift; done
echo "strace: ptrace(PTRACE_TRACEME, ...): Operation not permitted" >&2
exit 1
SHIM
    chmod +x "$SHIMDIR/strace"
    # Case [11] left fake-guard.sh pointing at a fixture it then deleted, so it
    # now fails in both trees and the run exits 3 as UNDETERMINED — the right
    # verdict for the wrong reason, which would have scored this case green by
    # accident. Restore an honest substrate so the ONLY thing under test here is
    # the broken instrument. (Caught by this case failing 11/12 on first run.)
    cat > "$R/tool/fake-guard.sh" <<'GUARD'
#!/usr/bin/env bash
set -uo pipefail
if [[ "${1:-}" == "--self-test" ]]; then echo "self-test 1/1 OK"; exit 0; fi
exit 0
GUARD
    git -C "$R" add tool/fake-guard.sh
    git -C "$R" commit -qm "restore an honest guard for the could-not-look case"
    echo "   [12] strace present but UNABLE TO TRACE — must report UNCHECKED, never a silent green:"
    out12=$(PATH="$SHIMDIR:$PATH" check_repo "$R" 2>&1); e12=$?
    out12b=$(PATH="$SHIMDIR:$PATH" SELFTEST_HERMETIC_REQUIRE_TRACE=1 check_repo "$R" 2>&1); e12b=$?
    grep -E 'trace-UNCHECKED|REQUIRE_TRACE|HERMETIC' <<<"$out12" | head -2 | sed 's/^/       /'
    if grep -q 'trace-UNCHECKED' <<<"$out12" && [ "$e12b" -eq 3 ] && grep -q 'Fail-closed' <<<"$out12b"; then
      echo "       => says it could not look, and REQUIRE_TRACE=1 fails closed (exit $e12b). NOT a silent green."
      pass=$((pass + 1))
    else
      echo "       => a broken instrument rendered a verdict. exit=$e12 require=$e12b"
    fi
    rm -rf "$SHIMDIR"
  fi

  echo ""
  echo ">> SELF-TEST: $pass/$total"
  [ "$pass" -eq "$total" ] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------- main
TARGET="${1:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)}"
check_repo "$TARGET"
exit $?
