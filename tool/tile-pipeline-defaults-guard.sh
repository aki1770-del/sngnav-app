#!/usr/bin/env bash
# tile-pipeline-defaults-guard.sh — assert the tile pipeline's DEFAULTS still
# reproduce the SHIPPED archive exactly.
#
# WHY THIS EXISTS (2026-08-11): parameterising the renderer for multi-region use
# defaulted `center` to the bbox midpoint (140.30000,39.75000). The shipped
# akita_offline.mbtiles carries 140.10000,39.72000 — the CITY, not the midpoint.
# That silently moves the initial view of an archive already in a beta app.
# It was introduced by the very edit meant to protect the shipped path, and
# caught by hand. Nothing would have caught it. This is that nothing, fixed.
#
# It compares the tool's own build_metadata() + PREF/CITY, with every SNGNAV_*
# UNSET, against the shipped archive's metadata table read as ground truth.
# It calls the REAL renderer code — not a replica of it, which would drift.
#
# Runs in seconds. Renders nothing. Modifies nothing.
#
# Usage:
#   tile-pipeline-defaults-guard.sh [renderer.py] [shipped.mbtiles]
# Exit: 0 all defaults match the shipped archive · 1 any drift · 2 substrate error
set -uo pipefail

SELFTEST=0
if [[ "${1:-}" == "--self-test" ]]; then SELFTEST=1; shift; fi

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
RENDERER="${1:-$REPO/tool/render_akita_mbtiles.py}"
SHIPPED="${2:-$REPO/assets/tiles/akita_offline.mbtiles}"
PY="${SNGNAV_PY:-$(command -v python3)}"

[ -f "$RENDERER" ] || { echo "SUBSTRATE ERROR: renderer not found: $RENDERER"; exit 2; }
[ -f "$SHIPPED" ]  || { echo "SUBSTRATE ERROR: shipped archive not found: $SHIPPED"; exit 2; }
[ -x "$PY" ]       || { echo "SUBSTRATE ERROR: python not executable: $PY"; exit 2; }
command -v sqlite3 >/dev/null || { echo "SUBSTRATE ERROR: sqlite3 absent"; exit 2; }

# --self-test: the guard proves itself FAILING before it is trusted to judge.
# Matches the repo's existing idiom (loom_mutation_gate.sh --self-test,
# assert_manifest_perms.sh --self-test): a guard is not INSERTED until PROVEN
# TO FAIL. Reconstructs the two real 2026-08-11 defects on COPIES; never
# touches the renderer or the shipped archive.
if [[ "$SELFTEST" == "1" ]]; then
  SELF="$(readlink -f "$0")"
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  st_fail=0
  echo "self-test: 3 cases — real PASS · D2 defect FAIL · fail-open FAIL"

  if "$SELF" >/dev/null 2>&1; then echo "  PASS  real renderer accepted"
  else echo "  FAIL  real renderer REJECTED (guard is broken, or a default really drifted)"; st_fail=1; fi

  sed "s|ctr = _os.environ.get('SNGNAV_CENTER', '140.10000,39.72000,11')|ctr = _os.environ.get('SNGNAV_CENTER', f'{(PREF[0]+PREF[2])/2:.5f},{(PREF[1]+PREF[3])/2:.5f},11')|" \
      "$RENDERER" > "$T/d2.py"
  if grep -q 'PREF\[0\]+PREF\[2\]' "$T/d2.py"; then
    if "$SELF" "$T/d2.py" >/dev/null 2>&1; then
      echo "  FAIL  D2 defect (computed-midpoint centre) was NOT caught"; st_fail=1
    else echo "  PASS  D2 defect correctly REJECTED"; fi
  else echo "  FAIL  could not reconstruct D2 (anchor moved) — fixture rotted"; st_fail=1; fi

  if SNGNAV_PY=/bin/true "$SELF" >/dev/null 2>&1; then
    echo "  FAIL  fail-open: guard PASSED having compared nothing"; st_fail=1
  else echo "  PASS  fail-open correctly REJECTED (compared nothing => RED)"; fi

  # FBR-CERT (C2): REQUIRED_FIELDS is half the Defect-1 fix and had no case —
  # deleting it left --self-test still reporting OK. An archive keeping the
  # incidental fields but missing name/bounds/center must be REJECTED.
  cp "$SHIPPED" "$T/partial.mbtiles" 2>/dev/null
  sqlite3 "$T/partial.mbtiles" "DELETE FROM metadata WHERE name IN ('name','bounds','center');" 2>/dev/null
  if "$SELF" "$RENDERER" "$T/partial.mbtiles" >/dev/null 2>&1; then
    echo "  FAIL  archive missing identity fields was ACCEPTED (REQUIRED_FIELDS dead)"; st_fail=1
  else echo "  PASS  archive missing identity fields correctly REJECTED"; fi

  # FBR-CERT (A): a crafted metadata key must not forge a comparison.
  if "$SELF" "$RENDERER" "/nonexistent-archive-$$.mbtiles" >/dev/null 2>&1; then
    echo "  FAIL  absent shipped archive was ACCEPTED"; st_fail=1
  else echo "  PASS  absent shipped archive correctly REJECTED"; fi

  [[ $st_fail -eq 0 ]] && { echo "self-test 5/5 OK"; exit 0; } || { echo "SELF-TEST FAILED"; exit 1; }
fi

echo "=== tile-pipeline defaults guard ==="
echo "renderer : $RENDERER"
echo "shipped  : $SHIPPED"

# Every SNGNAV_* is stripped: we are asserting the DEFAULT path, which is the
# path a plain Akita rebuild takes.
DEFAULTS=$(env -u SNGNAV_BBOX -u SNGNAV_PREF -u SNGNAV_CITY -u SNGNAV_PREF_NAME \
               -u SNGNAV_REGION_NAME -u SNGNAV_REGION_JA -u SNGNAV_WINDOW_NAME \
               -u SNGNAV_SOURCE_NAME -u SNGNAV_CENTER \
  "$PY" - "$RENDERER" <<'PYEOF'
import importlib.util as u, sys
spec = u.spec_from_file_location('renderer', sys.argv[1])
m = u.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
except SystemExit:
    pass
except Exception as e:
    print('LOAD_ERROR|%s' % e); sys.exit(0)
if not hasattr(m, 'build_metadata'):
    print('LOAD_ERROR|renderer exposes no build_metadata(); guard cannot test real code')
    sys.exit(0)
meta = m.build_metadata('unpinned')
for k in ('name', 'bounds', 'center', 'minzoom', 'maxzoom', 'version', 'type'):
    print('%s|%s' % (k, meta.get(k, '<missing>')))
print('CITY|%s' % (','.join('%.5f' % v for v in m.CITY),))
PYEOF
)

if grep -q '^LOAD_ERROR|' <<<"$DEFAULTS"; then
  echo "FAIL: ${DEFAULTS#LOAD_ERROR|}"; exit 1
fi

fail=0
compared=0        # CT-CERT defect 1: a guard that PASSES having compared NOTHING
                  # is a permanently green guard. With SNGNAV_PY=/bin/true the
                  # default block emitted nothing, the loop never ran, and this
                  # script printed PASS. "A gate that skips when it cannot check
                  # is the anti-loom." This counter is the assertion that a
                  # comparison actually happened.
REQUIRED_FIELDS="name bounds center"   # the three that decide the artifact's identity

ALLOWED_FIELDS="name bounds center minzoom maxzoom version type"
check() { # field  default_value
  local field="$1" got="$2" want
  # FBR-CERT (A): $field reached sqlite3 by interpolation, so a crafted key
  # (name' AND 0 UNION SELECT 'X) made the archive echo the guard's own value
  # back at it — a forged PASS needing zero knowledge of the shipped archive.
  # The field name is data from the renderer, not a literal; it is allowlisted.
  case " $ALLOWED_FIELDS " in
    *" $field "*) ;;
    *) echo "  FAIL: refusing unknown metadata key '$field' (not in allowlist)"
       fail=1; return ;;
  esac
  want=$(sqlite3 "$SHIPPED" "SELECT value FROM metadata WHERE name='$field';" 2>/dev/null)
  if [ -z "$want" ]; then
    printf '  %-10s SKIP  (not present in shipped archive)\n' "$field"; return
  fi
  compared=$((compared + 1))
  COMPARED_FIELDS="$COMPARED_FIELDS $field"
  if [ "$got" = "$want" ]; then
    printf '  %-10s OK    %s\n' "$field" "$got"
  else
    printf '  %-10s DRIFT\n            default : %s\n            shipped : %s\n' "$field" "$got" "$want"
    fail=1
  fi
}
COMPARED_FIELDS=""

echo "--- defaults (all SNGNAV_* unset) vs shipped archive ---"
while IFS='|' read -r k v; do
  [ -z "$k" ] && continue
  [ "$k" = "CITY" ] && { printf '  %-10s (no shipped counterpart; informational) %s\n' "$k" "$v"; continue; }
  check "$k" "$v"
done <<<"$DEFAULTS"

echo
# FAIL-CLOSED ASSERTION (CT-CERT defect 1). Silence is not success: if nothing
# was compared, this guard has measured nothing and must say so rather than
# print PASS. Falsifier, re-runnable by anyone:
#     SNGNAV_PY=/bin/true ./scripts/tile-pipeline-defaults-guard.sh; echo $?
# must be non-zero.
if [ "$compared" -eq 0 ]; then
  echo "FAIL — this guard compared NOTHING and therefore verified nothing."
  echo "The renderer produced no default metadata (python broken, module"
  echo "unloadable, or build_metadata() absent). A gate that skips when it"
  echo "cannot check is the anti-loom. Treat as RED, not as green."
  exit 1
fi
for f in $REQUIRED_FIELDS; do
  if ! grep -qw -- "$f" <<<"$COMPARED_FIELDS"; then
    echo "FAIL — required field '${f}' was never compared (absent from the"
    echo "shipped archive, or missing from build_metadata()). Identity fields"
    echo "may not silently drop out of the comparison."
    exit 1
  fi
done

if [ "$fail" -ne 0 ]; then
  cat <<'MSG'
FAIL — a default no longer reproduces the shipped archive.
A rebuild of the shipped region would now produce a DIFFERENT artifact than the
one already in consumers' hands. Fix the default to the shipped literal; do not
"fix" the shipped archive to match a new default.
MSG
  exit 1
fi
echo "PASS — every default reproduces the shipped archive ($compared fields compared)."
exit 0
