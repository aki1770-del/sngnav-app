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
# is trusted to judge. Operates only on COPIES; the real archives are read-only.
if [[ "${1:-}" == "--self-test" ]]; then
  SELF="$(readlink -f "$0")"
  APP="${TILE_GATE_APP:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
  SRC="$APP/assets/tiles/gunma_offline.mbtiles"
  # FBR-CERT (C1): this exited 0 when the fixture was absent — verbatim the
  # thing the sibling guard condemns twelve lines away ("a gate that skips when
  # it cannot check is the anti-loom"), and absent-fixture is the ONLY state a
  # CI runner is ever in. A self-test that cannot test must be RED.
  [ -f "$SRC" ] || { echo "SELF-TEST FAILED: fixture archive absent at $SRC"; \
                     echo "  A self-test that skips when it cannot check is the anti-loom."; exit 1; }
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  st_fail=0
  echo "self-test: 4 cases — real PASS · centre-outside-bounds FAIL · cut-contradiction FAIL · no-tiles FAIL"

  if "$SELF" "$SRC" >/dev/null 2>&1; then echo "  PASS  real archive accepted"
  else echo "  FAIL  real archive REJECTED"; st_fail=1; fi

  cp "$SRC" "$T/a.mbtiles"
  sqlite3 "$T/a.mbtiles" "UPDATE metadata SET value='140.10000,39.72000,11' WHERE name='center';" 2>/dev/null
  if "$SELF" "$T/a.mbtiles" >/dev/null 2>&1; then
    echo "  FAIL  centre outside bounds NOT caught"; st_fail=1
  else echo "  PASS  centre-outside-bounds correctly REJECTED"; fi

  cp "$SRC" "$T/b.mbtiles"
  sqlite3 "$T/b.mbtiles" "UPDATE metadata SET value='Real OpenStreetMap cartography for Gunma prefecture rendered from the Geofabrik Tohoku extract (cut kanto-260810).' WHERE name='description';" 2>/dev/null
  if "$SELF" "$T/b.mbtiles" >/dev/null 2>&1; then
    echo "  FAIL  description/source_cut contradiction NOT caught"; st_fail=1
  else echo "  PASS  cut-contradiction correctly REJECTED"; fi

  cp "$SRC" "$T/c.mbtiles"
  sqlite3 "$T/c.mbtiles" "DELETE FROM tiles;" 2>/dev/null
  if "$SELF" "$T/c.mbtiles" >/dev/null 2>&1; then
    echo "  FAIL  empty archive NOT caught"; st_fail=1
  else echo "  PASS  empty archive correctly REJECTED"; fi

  [[ $st_fail -eq 0 ]] && { echo "self-test 4/4 OK"; exit 0; } || { echo "SELF-TEST FAILED"; exit 1; }
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
if [ -n "$CUT" ] && [ -n "$DESC" ]; then
  CUTREGION=$(sed -E 's|^geofabrik/||; s|-[0-9]+$||' <<<"$CUT" | tr '[:upper:]' '[:lower:]')
  contradiction=0
  for other in tohoku kanto chubu kansai kyushu shikoku chugoku hokkaido; do
    [ "$other" = "$CUTREGION" ] && continue
    if grep -qiE "Geofabrik ${other} extract" <<<"$DESC"; then
      err "description names 'Geofabrik ${other} extract' but source_cut is '${CUT}'"
      contradiction=1
    fi
  done
  [ "$contradiction" -eq 0 ] && ok "description does not contradict source_cut ($CUTREGION)"
else
  warn "source_cut or description absent — provenance unpinnable"
fi

# 4. name/description coherence (advisory: cosmetic unless surfaced to a user)
if [ -n "$NAME" ] && [ -n "$DESC" ]; then
  REGION=$(awk '{print $1}' <<<"$NAME")
  if grep -qiE "cartography for ${REGION}" <<<"$DESC"; then
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
