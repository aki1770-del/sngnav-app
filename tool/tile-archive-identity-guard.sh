#!/usr/bin/env bash
# tile-archive-identity-guard.sh — fail when an .mbtiles archive LIES ABOUT ITSELF.
#
# WHY THIS EXISTS (2026-08-11): the first Gunma build wrote 777 correct Gunma
# tiles under name="Akita offline basemap", center=Akita (340 km from the data),
# and a description naming "Akita prefecture" and "Geofabrik Tohoku extract"
# while carrying source_cut=kanto-260810 — contradicting itself in one row.
# PYTHON_EXIT was 0. The tiles were right and the archive was a lie, and only
# reading the metadata table caught it.
#
# Consequence ranking is by what it does to the DRIVER, not by tidiness:
#   ERROR  center outside bounds ......... her initial view opens off-map
#   ERROR  description contradicts cut ... the archive misreports its own source
#   ERROR  degenerate/absent bounds ...... the out-of-coverage grey tint breaks
#   WARN   name inconsistent with region . cosmetic unless surfaced in UI
#
# Reads only. Never modifies the archive it inspects.
#
# Usage: tile-archive-identity-guard.sh <archive.mbtiles>
# Exit: 0 self-consistent · 1 archive lies about itself · 2 substrate error
set -uo pipefail

# --self-test: prove the guard FAILS on the real 2026-08-11 D3 defect before it
# is trusted to judge. Operates only on a fixture it BUILDS ITSELF, in a tmpdir.
#
# ⚑ REPAIRED 2026-08-16 (AAE). Recorded at length because the defect is subtler
# than the red it produced, and because TWO repairs of this one red were authored
# hours apart in two different clones of this repository. This is the
# reconciliation of both; neither shipped alone. See the record at
# outputs/operational-records/aae_tile_guard_reconciliation_2026_08_16.md.
#
#   WHAT WAS WRONG. The fixture was `$APP/assets/tiles/gunma_offline.mbtiles`,
#   and absence was made RED (ADVERSARIAL-REVIEW C1) on the correct reasoning that a
#   self-test which skips when it cannot check is the anti-loom. The reasoning
#   was right. The FIXTURE was wrong: gunma_offline.mbtiles is a LOCAL BUILD
#   INTERMEDIATE of the 2026-08-11 multi-region render (render_akita_mbtiles.py
#   :35-37, via SNGNAV_PREF/SNGNAV_CITY). It is not tracked and not ignored
#   (`git check-ignore` exits 1), so it is in NO checkout a runner ever makes.
#
#   ⚑ A CORRECTION TO THE OTHER REPAIR'S ACCOUNT, kept rather than quietly
#   dropped, because it is the same class of error this file exists to catch.
#   The 10:29 commit c20e392 wrote that the fixture is "not on the authoring
#   machine either — it exists nowhere." That is FALSE, measured 2026-08-16:
#   assets/tiles/gunma_offline.mbtiles is present in the clone at
#   /home/komada/tmp/sngnav-app — 11,034,624 bytes, md5 336a9e2e595a4e337881
#   702d9e820092. It is absent only from the OTHER clone, which is the one that
#   commit was authored in. A claim about "the machine" was made from one tree.
#   The operative fact survives the correction and is what matters here: the
#   fixture is untracked in BOTH clones, therefore absent from every CI
#   checkout, therefore these detection cases had NEVER ONCE RUN on a runner.
#
#   Before ae1bcf6 the guard was resolved through a private path a runner never
#   checks out, so it was a no-op that always passed. After ae1bcf6 it was RED
#   on the absent fixture — masked at first by the sibling guard's own red (PIL
#   absent), which bc3a2ea fixed, at which point the failure simply MOVED here.
#   Two runs, zero detection cases. Making a broken thing LOUD is not the same
#   as making it RUNNABLE.
#
#   THE FIX IS NOT TO SOFTEN THE GUARD. Absence-is-RED stays, and now applies to
#   the fixture BUILD: if the fixture cannot be constructed, this is RED. What
#   changes is that the fixture is no longer FOUND — it is CONSTRUCTED, which is
#   the idiom every other self-test in tool/ already uses
#   (assert_manifest_perms.sh heredocs into `mktemp -d`; loom_mutation_gate.sh
#   reconstructs from git history). This guard was the sole outlier.
#
#   WHY BUILT AND NOT THE SHIPPED ARCHIVE. The rejected alternative was to point
#   the fixture at assets/tiles/akita_offline.mbtiles, which IS tracked and IS in
#   every checkout. It works — measured green — and it was rejected for two
#   measured reasons. (1) That archive is IRREPRODUCIBLE: it pins
#   geofabrik/tohoku-260709, a daily snapshot Geofabrik keeps about a week, and
#   it now 404s. Its committed bytes are the only copy that will ever exist, and
#   they are already in a driver's hands; a self-test that copies them on every
#   CI run puts a permanent-loss hazard where none needs to be. (2) A real
#   archive cannot be made to hold the states cases 5-7 require without
#   mutating it anyway, and case 8 needs NO archive at all.
#
#   THE REPLICA-DRIFT OBJECTION, and why it does not bite here. A synthetic
#   fixture is a replica, and a replica drifts from what the renderer really
#   emits — the exact objection that keeps the sibling guard IMPORTING the
#   renderer rather than parsing it. It does not bite because of the division of
#   labour below: this self-test never claims to judge a shipped artifact.
#     --self-test ............ proves the guard DETECTS. Hermetic; touches no
#                              shipped artifact; runs on any checkout.
#     CI "Tile archive identity" step ... judges the REAL shipped archives,
#                              every assets/tiles/*.mbtiles, and REQUIRES at
#                              least one (`test ${#archives[@]} -gt 0`). THAT is
#                              where drift against real renderer output is
#                              caught. A self-test is not an inventory.
#   If that CI step is ever weakened, this reasoning fails with it. They are one
#   design, not two.
#
#   Cases 5-8 are NEW. The guard has ERROR branches for degenerate bounds,
#   absent bounds and absent centre that no case ever exercised, plus a
#   substrate exit for an absent archive. 8 cases that run, versus 4 that never
#   did.
if [[ "${1:-}" == "--self-test" ]]; then
  SELF="$(readlink -f "$0")"
  command -v sqlite3 >/dev/null || {
    echo "SELF-TEST SUBSTRATE ERROR: sqlite3 absent — the fixture cannot be built."
    echo "  A self-test that skips when it cannot check is the anti-loom. RED, not skipped."
    exit 2; }

  # ADVERSARIAL-REVIEW C2 PRESERVED — carried in from the sibling repair 69b7cec, where
  # an independent reviewer found it adversarially. Under `set -uo pipefail` with no `-e`, a failing
  # `mktemp -d` leaves T SET but EMPTY, every path below becomes an absolute
  # path at /, and the whole self-test proceeds against files that do not exist.
  T=$(mktemp -d) || { echo "SELF-TEST FAILED: mktemp -d failed; refusing to test nothing."; exit 1; }
  [ -n "$T" ] && [ -d "$T" ] || { echo "SELF-TEST FAILED: no usable temp dir; refusing to test nothing."; exit 1; }
  trap 'rm -rf "$T"' EXIT
  st_fail=0

  # The fixture reproduces the REAL 2026-08-11 subject: a Gunma archive. Geometry
  # is the measured Gunma extent (render_akita_mbtiles.py:36-37), and source_cut
  # is the ARCHIVAL kanto-260801 the .gitignore correction established as this
  # archive's actual cut. Self-consistent by construction — every defect below is
  # introduced deliberately, one at a time, on a COPY.
  #
  # A note on ADVERSARIAL-REVIEW C1, the SQL-injection defect found in the OTHER repair:
  # there, the mutations were derived from a real archive's own `source_cut`, so
  # archive data reached an UPDATE statement and a crafted fixture could forge a
  # green. Here every value is a literal in this file. That defect is not fixed
  # here — it is structurally absent, which is the stronger property.
  #
  # ⚑ SCOPE OF THAT SENTENCE, corrected 2026-08-16 after the independent reviewer (C9) refuted the
  # over-reading it invited: "structurally absent" is true of THIS SELF-TEST and
  # of nothing else. The guard's MAIN path below reads name/bounds/centre/cut/
  # description straight out of the file under inspection, and one of those did
  # reach a regex — see the -F fix at check 4. A claim about the fixture is not
  # a claim about the guard.
  SRC="$T/fixture.mbtiles"
  sqlite3 "$SRC" <<'SQL'
CREATE TABLE metadata (name text, value text);
CREATE TABLE tiles (zoom_level integer, tile_column integer, tile_row integer, tile_data blob);
INSERT INTO metadata (name, value) VALUES
  ('name',        'Gunma offline basemap'),
  ('bounds',      '138.35000,35.94000,139.72000,37.11000'),
  ('center',      '139.06328,36.38934,11'),
  ('minzoom',     '8'),
  ('maxzoom',     '13'),
  ('version',     '1.0.0'),
  ('type',        'baselayer'),
  ('format',      'png'),
  ('source_cut',  'geofabrik/kanto-260801'),
  ('description', 'Real OpenStreetMap cartography for Gunma prefecture rendered from the Geofabrik Kanto extract (cut kanto-260801).');
INSERT INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES
  (8, 226, 154, X'89504E470D0A1A0A'),
  (8, 227, 154, X'89504E470D0A1A0A');
SQL

  # FIXTURE INTEGRITY — assert the fixture is what we think before trusting any
  # verdict taken against it. A silently-empty fixture would make case 4
  # ("no tiles rejected") pass for the wrong reason: a false green built on a
  # broken fixture is exactly the failure class this guard exists inside.
  fx_tiles=$(sqlite3 "$SRC" "SELECT count(*) FROM tiles;" 2>/dev/null)
  fx_meta=$(sqlite3 "$SRC" "SELECT count(*) FROM metadata WHERE name IN ('name','bounds','center','source_cut','description');" 2>/dev/null)
  # ADVERSARIAL-REVIEW C11: if sqlite3 ever emits non-numeric or multi-line output (a
  # build that reads ~/.sqliterc non-interactively with .headers/.mode set will),
  # BOTH `[` tests below error to rc=2, which reads as false, and the integrity
  # check silently passes — a fixture-validity gate that validates nothing. Not
  # reachable on sqlite3 3.45.1, which ignores the rc file non-interactively;
  # asserted rather than assumed because the next runner's build is not ours.
  case "${fx_tiles:-}" in ''|*[!0-9]*) fx_tiles=-1 ;; esac
  case "${fx_meta:-}"  in ''|*[!0-9]*) fx_meta=-1  ;; esac
  if [ "${fx_tiles:-0}" -lt 1 ] || [ "${fx_meta:-0}" -ne 5 ]; then
    echo "SELF-TEST FAILED: could not build the fixture (tiles=${fx_tiles:-0}, metadata=${fx_meta:-0}/5)."
    echo "  Every verdict below would be taken against a fixture that is not what it claims."
    exit 1
  fi

  # ADVERSARIAL-REVIEW C2 PRESERVED — the exit-code discipline, carried in from 69b7cec.
  # THE FALSE GREEN IT PREVENTS, re-measured on THIS branch 2026-08-16 against
  # the un-hardened 8-case version: with `cp` made to fail (a `cp` shim on PATH
  # standing in for ENOSPC), that version printed "self-test 8/8 OK" and exited
  # 0 having actually exercised ONE of its eight cases. Six reject cases printed
  # "correctly REJECTED" against archives that were never created, because the
  # sub-invocation hit this guard's own "SUBSTRATE ERROR: no such archive" and
  # exited 2, and `if cmd; then FAIL else PASS` reads ANY nonzero as success.
  #
  # This guard's contract has THREE exit codes (0 consistent · 1 lies about
  # itself · 2 substrate error), so a case must assert the EXACT code it means.
  # Cases 2-7 mean 1. Case 8 means 2 — an absent archive is a substrate error by
  # this guard's own contract, and asserting 1 there would be asserting a lie.
  mkcopy() { cp "$SRC" "$1" || { echo "SELF-TEST FAILED: could not copy fixture to $1"; exit 1; }; }
  mutate() { sqlite3 "$1" "$2" || { echo "SELF-TEST FAILED: could not mutate $1"; exit 1; }; }
  expect_exit() { # want  label  archive
    local want="$1" label="$2" arch="$3" rc
    bash "$SELF" "$arch" >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq "$want" ]; then
      echo "  PASS  $label (exit $rc)"
    elif [ "$rc" -eq 0 ]; then
      echo "  FAIL  $label — was ACCEPTED"; st_fail=1
    else
      echo "  FAIL  $label — exited $rc, wanted $want; this case tested NOTHING"; st_fail=1
    fi
  }

  echo "self-test: 12 cases on a SELF-BUILT fixture — 2 accept · 8 reject · 1 substrate · 1 advisory"

  if bash "$SELF" "$SRC" >/dev/null 2>&1; then echo "  PASS  self-consistent archive accepted"
  else echo "  FAIL  self-consistent archive REJECTED (the guard cries wolf)"; st_fail=1; fi

  # [2] THE REAL 2026-08-11 DEFECT: correct Gunma tiles, centre left at Akita.
  #     ~367 km from the data; her initial view opens off-map.
  mkcopy "$T/a.mbtiles"
  mutate "$T/a.mbtiles" "UPDATE metadata SET value='140.10000,39.72000,11' WHERE name='center';"
  expect_exit 1 "centre-outside-bounds correctly REJECTED" "$T/a.mbtiles"

  # [3] THE REAL 2026-08-11 DEFECT: a kanto cut described as a Tohoku extract.
  mkcopy "$T/b.mbtiles"
  mutate "$T/b.mbtiles" "UPDATE metadata SET value='Real OpenStreetMap cartography for Gunma prefecture rendered from the Geofabrik Tohoku extract (cut kanto-260810).' WHERE name='description';"
  expect_exit 1 "cut-contradiction correctly REJECTED" "$T/b.mbtiles"

  # [4] an archive with no tiles is not an archive.
  mkcopy "$T/c.mbtiles"
  mutate "$T/c.mbtiles" "DELETE FROM tiles;"
  expect_exit 1 "empty archive correctly REJECTED" "$T/c.mbtiles"

  # [5] degenerate bounds — the out-of-coverage grey tint has nothing to work from.
  #
  #     ISOLATION MATTERS HERE, and the first draft of this case got it wrong.
  #     It used INVERTED bounds (w>e, s>n), which also puts the centre outside
  #     the range, so the archive was rejected by the CENTRE branch while the
  #     bounds branch was never exercised. Proven by mutation on 2026-08-16:
  #     with the degenerate-bounds `err` neutered, the self-test still reported
  #     8/8 OK — a case passing for a reason other than the one it names.
  #     Degenerate-as-a-POINT with the centre ON that point isolates it: the
  #     centre test is satisfied (x>=w and x<=e both hold at equality), so only
  #     `w<e && s<n` can fail. Re-proven by the same mutation after the fix.
  mkcopy "$T/d.mbtiles"
  mutate "$T/d.mbtiles" "UPDATE metadata SET value='139.06328,36.38934,139.06328,36.38934' WHERE name='bounds';"
  expect_exit 1 "degenerate bounds correctly REJECTED" "$T/d.mbtiles"

  # [6] bounds absent entirely.
  mkcopy "$T/e.mbtiles"
  mutate "$T/e.mbtiles" "DELETE FROM metadata WHERE name='bounds';"
  expect_exit 1 "absent bounds correctly REJECTED" "$T/e.mbtiles"

  # [7] centre absent entirely.
  mkcopy "$T/f.mbtiles"
  mutate "$T/f.mbtiles" "DELETE FROM metadata WHERE name='center';"
  expect_exit 1 "absent centre correctly REJECTED" "$T/f.mbtiles"

  # [8] an archive that is not there at all is a SUBSTRATE error (exit 2), never
  #     a pass. Asserted as exactly 2 — the code this guard's contract assigns
  #     it — so that the assertion still means something if the contract moves.
  expect_exit 2 "absent archive correctly refused as substrate error" "$T/no-such-archive.mbtiles"

  # [9] ADVERSARIAL-REVIEW C8: delete the source_cut and the description's provenance
  #     claim has nothing to corroborate it. This PASSED before 2026-08-16 —
  #     the branch fell through to a `warn` and the archive exited 0, so the
  #     2026-08-11 defect class walked through by dropping one row.
  mkcopy "$T/g.mbtiles"
  mutate "$T/g.mbtiles" "UPDATE metadata SET value='Real OpenStreetMap cartography for Gunma prefecture rendered from the Geofabrik Tohoku extract.' WHERE name='description';
                         DELETE FROM metadata WHERE name='source_cut';"
  expect_exit 1 "uncorroborated provenance claim correctly REJECTED" "$T/g.mbtiles"

  # [10] ADVERSARIAL-REVIEW C8: a region outside the old hardcoded eight. Okinawa was
  #      accepted against a kanto cut purely because nobody had listed it.
  mkcopy "$T/h.mbtiles"
  mutate "$T/h.mbtiles" "UPDATE metadata SET value='Real OpenStreetMap cartography for Gunma prefecture rendered from the Geofabrik Okinawa extract.' WHERE name='description';"
  expect_exit 1 "off-list region contradiction correctly REJECTED" "$T/h.mbtiles"

  # [11] ADVERSARIAL-REVIEW C8: the CRY-WOLF side. A legitimate cut with a suffix after
  #      the date must still be recognised as its own region, or the guard
  #      rejects honest archives — which is how a guard gets switched off.
  mkcopy "$T/i.mbtiles"
  mutate "$T/i.mbtiles" "UPDATE metadata SET value='geofabrik/kanto-260801-rebuild' WHERE name='source_cut';"
  expect_exit 0 "suffixed-but-honest cut correctly ACCEPTED (no cry-wolf)" "$T/i.mbtiles"

  # [12] ADVERSARIAL-REVIEW C9: a crafted `name` must not become a regex that suppresses
  #      the coherence warning. Advisory-only, so the archive still exits 0 —
  #      the assertion is that the WARN survives, checked on stdout.
  mkcopy "$T/j.mbtiles"
  mutate "$T/j.mbtiles" "UPDATE metadata SET value='.* offline basemap' WHERE name='name';"
  # NOT `bash … | grep -q`. Under `set -o pipefail` grep exits at the first match,
  # the writer takes SIGPIPE, and the pipeline status becomes 141 — so the case
  # would report FAIL nondeterministically, depending on which side finished
  # first. Written that way first and caught by mutation testing the same turn,
  # which is the second time this exact race appeared in this commit; the other
  # was in selftest-hermeticity-guard.sh's discovery predicate. Substituting the
  # output removes the pipe.
  j_out=$(bash "$SELF" "$T/j.mbtiles" 2>/dev/null)
  if grep -q 'WARN : name says' <<<"$j_out"; then
    echo "  PASS  regex-shaped name did not suppress the coherence WARN"
  else
    echo "  FAIL  regex-shaped name SUPPRESSED the coherence WARN"; st_fail=1
  fi

  [[ $st_fail -eq 0 ]] && { echo "self-test 12/12 OK"; exit 0; } || { echo "SELF-TEST FAILED"; exit 1; }
fi

M="${1:-}"
[ -n "$M" ] || { echo "usage: $(basename "$0") <archive.mbtiles>"; exit 2; }
[ -f "$M" ] || { echo "SUBSTRATE ERROR: no such archive: $M"; exit 2; }
command -v sqlite3 >/dev/null || { echo "SUBSTRATE ERROR: sqlite3 absent"; exit 2; }

get() { sqlite3 "$M" "SELECT value FROM metadata WHERE name='$1';" 2>/dev/null; }

NAME=$(get name); BOUNDS=$(get bounds); CENTER=$(get center)
CUT=$(get source_cut); DESC=$(get description)
TILES=$(sqlite3 "$M" "SELECT count(*) FROM tiles;" 2>/dev/null)

echo "=== tile archive identity guard ==="
echo "archive : $M"
echo "name    : ${NAME:-<absent>}"
echo "cut     : ${CUT:-<absent>}"
echo "bounds  : ${BOUNDS:-<absent>}"
echo "center  : ${CENTER:-<absent>}"
echo "tiles   : ${TILES:-0}"
echo "---"

fail=0
err()  { echo "  ERROR: $*"; fail=1; }
warn() { echo "  WARN : $*"; }
ok()   { echo "  ok   : $*"; }

# 1. bounds present and non-degenerate
if [ -z "$BOUNDS" ]; then
  err "bounds absent — the out-of-coverage grey tint has nothing to work from"
else
  IFS=, read -r BW BS BE BN <<<"$BOUNDS"
  if awk -v w="$BW" -v s="$BS" -v e="$BE" -v n="$BN" \
      'BEGIN{exit !(w+0<e+0 && s+0<n+0)}'; then
    ok "bounds non-degenerate"
  else
    err "bounds degenerate or inverted: $BOUNDS"
  fi
fi

# 2. centre must lie INSIDE bounds — the defect that puts her view off-map
if [ -z "$CENTER" ]; then
  err "center absent"
elif [ -n "${BW:-}" ]; then
  IFS=, read -r CX CY _CZ <<<"$CENTER"
  if awk -v x="$CX" -v y="$CY" -v w="$BW" -v s="$BS" -v e="$BE" -v n="$BN" \
      'BEGIN{exit !(x+0>=w+0 && x+0<=e+0 && y+0>=s+0 && y+0<=n+0)}'; then
    ok "center lies inside bounds"
  else
    D=$(awk -v x="$CX" -v y="$CY" -v w="$BW" -v s="$BS" -v e="$BE" -v n="$BN" \
        'BEGIN{cx=(w+e)/2; cy=(s+n)/2; dx=(x-cx)*88.9; dy=(y-cy)*111.0;
               printf "%.0f", sqrt(dx*dx+dy*dy)}')
    err "center ($CENTER) is OUTSIDE bounds ($BOUNDS) — roughly ${D} km from the data"
  fi
fi

# 3. the archive must not contradict its own source_cut
#    (Gunma tiles cut from kanto, described as a Tohoku extract, is the real defect)
#
# ⚑ REWRITTEN 2026-08-16 on three defects the reviewer found adversarially (ADVERSARIAL-REVIEW C8).
# The previous shape had the CUT drive the comparison, against a hardcoded list:
#
#   1. DELETE the source_cut row and the whole check fell to `warn`, exit 0 — so
#      an archive describing itself as a "Geofabrik Tohoku extract" with NOTHING
#      to corroborate it PASSED. The header ranks this class ERROR ("the archive
#      misreports its own source"); dropping one row downgraded it to advisory.
#      That is the 2026-08-11 defect class walking straight through.
#   2. The list held eight regions. `Geofabrik Okinawa extract` against a kanto
#      cut was accepted, because Okinawa was not on it.
#   3. `s|-[0-9]+$||` only strips digits at the END, so a legitimate cut like
#      `geofabrik/kanto-260801-rebuild` left CUTREGION as the whole string,
#      matching no region — and an HONEST "Geofabrik Kanto extract" description
#      was then flagged as a contradiction. Cry-wolf on a valid cut format.
#
# Now the DESCRIPTION's own claim drives it: whatever region the description
# names is extracted generically, then checked against the cut. No list to fall
# behind, no silent pass when the corroborating field is missing.
DESCREGION=$(grep -oiE 'Geofabrik[[:space:]]+[A-Za-z-]+[[:space:]]+extract' <<<"${DESC:-}" \
             | head -1 | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
CUTREGION=$(sed -E 's|^geofabrik/||; s|-[0-9]{6,}.*$||' <<<"${CUT:-}" | tr '[:upper:]' '[:lower:]')

if [ -n "$DESCREGION" ]; then
  if [ -z "$CUT" ]; then
    # An unfalsifiable provenance claim in a safety artifact. She cannot go and
    # check where her map came from; the archive is the whole of what she gets.
    err "description claims 'Geofabrik ${DESCREGION} extract' but the archive carries NO source_cut to corroborate it"
  elif [ "$DESCREGION" = "$CUTREGION" ]; then
    ok "description's region ($DESCREGION) agrees with source_cut ($CUT)"
  else
    err "description names 'Geofabrik ${DESCREGION} extract' but source_cut is '${CUT}'"
  fi
elif [ -z "$CUT" ] || [ -z "$DESC" ]; then
  warn "source_cut or description absent, and the description makes no Geofabrik claim — provenance unpinnable"
else
  ok "description makes no Geofabrik-extract claim to contradict (cut: $CUT)"
fi

# 4. name/description coherence (advisory: cosmetic unless surfaced to a user)
if [ -n "$NAME" ] && [ -n "$DESC" ]; then
  REGION=$(awk '{print $1}' <<<"$NAME")
  # ADVERSARIAL-REVIEW C9: -F, not -E. $REGION is DATA READ FROM THE ARCHIVE, and it was
  # interpolated into a regex: a name of `.* offline basemap` made this match
  # anything and permanently suppressed the warning. Advisory-only impact, but
  # the comment at the head of the self-test claims this injection class is
  # "structurally absent" — that is true of the SELF-TEST, whose every value is
  # a literal, and it was not true here, on the main path, where the values come
  # from the file under inspection. Fixed-string match closes it.
  if grep -qiF "cartography for $REGION" <<<"$DESC"; then
    ok "name and description agree on the region ($REGION)"
  else
    warn "name says '$REGION' but description does not name that region"
  fi
fi

# 5. an archive with no tiles is not an archive
[ "${TILES:-0}" -gt 0 ] && ok "$TILES tiles present" || err "archive contains no tiles"

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — this archive misreports itself. The tiles may be correct and the"
  echo "archive still be a lie; a build exiting 0 proves nothing about identity."
  exit 1
fi
echo "PASS — archive is self-consistent."
exit 0
