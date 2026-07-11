#!/usr/bin/env bash
# L34 — THE MUTATION GATE. A guard is not INSERTED until it has been PROVEN to FAIL.
#
# WHY THIS EXISTS (BOD-19 recursive 5-Whys terminus, 2026-07-11)
# --------------------------------------------------------------
# On 2026-07-11 VAA shipped four green verdicts that were each defective, and every
# one was caught by a different agent — never by VAA. The recursive 5-Whys bottomed
# out here:
#
#   The unit gates ARTIFACTS at tool boundaries, and grades those gates against the
#   BUILDER'S OWN MODEL of the failure — which is precisely what the builder cannot
#   model. A passing self-test written by the builder is not evidence. It is the
#   builder's imagination, rendered in green.
#
# Measured, three times in ONE file (tool/assert_manifest_perms.sh):
#   * self-test 10/10 — while the guard blessed a DEAD ja voice lane (greedy regex)
#   * self-test 26/26 — while the guard passed `tools:node="removeAll"` on
#     ACCESS_FINE_LOCATION, printing "PASS: 3 WS1-blocker permissions effectively
#     declared" over HER DEAD LOCATION DOT — the exact regression the guard was
#     written to make impossible. It carried a DIA certification stamp while doing it.
#
# Both greens were over defective cloth. Neither was caught by running the guard.
# Both were caught only by someone MUTATING the input and demanding the guard bite.
#
# THE PRINCIPLE (Sakichi): the loom is not proven by weaving good cloth. It is proven
# by BREAKING THE THREAD and watching the machine STOP. A guard that has never been
# shown to fail is a green light with no thread behind it.
#
# WHAT THIS GATE DOES
#   Runs <guard> against a corpus of MUTANTS (inputs carrying a real, known defect)
#   and HEALTHY inputs. The guard is CERTIFIED only if it REJECTS every mutant AND
#   ACCEPTS every healthy input. A guard that PASSES a mutant is BLIND, and this gate
#   exits non-zero: NOT INSERTED.
#
# WHO WRITES THE CORPUS — the load-bearing rule (OPS-RULE-064(C), one tier down)
#   The mutants MUST NOT be authored by the pen that wrote the guard. A builder's
#   mutants encode the builder's model — the same blind spot, one level up. Corpus
#   provenance is asserted from git: if the corpus and the guard share their last
#   author, this gate WARNS loudly. (It cannot prove independence — that is judgement,
#   and a gate claiming to adjudicate it would itself be the failure this exists to
#   stop. It CAN refuse to let the fact go unstated.)
#
# Usage:
#   tool/loom_mutation_gate.sh <guard> <corpus-dir>
#   tool/loom_mutation_gate.sh --self-test        # PROVE this gate bites the REAL blind guard
#
# Corpus layout:
#   <corpus-dir>/mutants/*   — each MUST be rejected (guard exits != 0). A pass = BLIND.
#   <corpus-dir>/healthy/*   — each MUST be accepted (guard exits 0). A fail = CRIES WOLF.
#
# Exit: 0 = CERTIFIED (bit every mutant, accepted every healthy)
#       1 = NOT INSERTED (the guard is blind to a real defect, or cries wolf)
set -uo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_corpus() {
  local guard="$1" corpus="$2" quiet="${3:-}"
  local blind=0 wolf=0 bit=0 ok=0

  if [[ ! -x "$guard" && ! -f "$guard" ]]; then
    echo "FAIL: guard not found: $guard" >&2
    return 1
  fi

  # --- MUTANTS: each carries a REAL defect. The guard MUST bite. ---
  if compgen -G "$corpus/mutants/*" > /dev/null; then
    for m in "$corpus"/mutants/*; do
      [[ -f "$m" ]] || continue
      if bash "$guard" "$m" >/dev/null 2>&1; then
        # exit 0 on a mutant = the guard looked at a real defect and said PASS.
        blind=$((blind + 1))
        [[ -n "$quiet" ]] || echo "   BLIND   $(basename "$m")  -> guard said PASS over a real defect"
      else
        bit=$((bit + 1))
        [[ -n "$quiet" ]] || echo "   bit     $(basename "$m")"
      fi
    done
  fi

  # --- HEALTHY: the guard MUST NOT cry wolf. An ignored gate is no gate. ---
  if compgen -G "$corpus/healthy/*" > /dev/null; then
    for h in "$corpus"/healthy/*; do
      [[ -f "$h" ]] || continue
      if bash "$guard" "$h" >/dev/null 2>&1; then
        ok=$((ok + 1))
        [[ -n "$quiet" ]] || echo "   ok      $(basename "$h")"
      else
        wolf=$((wolf + 1))
        [[ -n "$quiet" ]] || echo "   WOLF    $(basename "$h")  -> guard rejected a HEALTHY input"
      fi
    done
  fi

  echo "$blind $wolf $bit $ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
  # PROVE THE GATE ON THE REAL HISTORICAL DEFECT.
  #
  # This gate's own claim is "I bite a blind guard." So it must be run against a guard
  # that IS REALLY BLIND — not one this pen imagined. We use the unit's own history:
  # the manifest guard as it stood BEFORE 96fd023, whose regex could not match
  # `removeAll` and therefore passed a manifest that killed HER location dot.
  #
  # If this gate cannot bite THAT, it is exactly the thing it condemns.
  echo ">> SELF-TEST: does the mutation gate BITE the real, historically blind guard?"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/corpus/mutants" "$tmp/corpus/healthy"

  MF='<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">'
  PERMS='<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>'
  QUERIES='<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>'

  # MUTANT — the real one. HER location dot, killed by a documented merger directive.
  cat > "$tmp/corpus/mutants/location_removeall.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" tools:node="removeAll"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES</manifest>
EOF
  # MUTANT — the real one. HER ja voice lane, killed by moving the intent out of <queries>.
  cat > "$tmp/corpus/mutants/voice_lane_dead.xml" <<EOF
$MF
$PERMS
<queries><intent><action android:name="android.intent.action.PROCESS_TEXT"/></intent></queries>
<application><activity><intent-filter><action android:name="android.intent.action.TTS_SERVICE"/></intent-filter></activity></application>
<queries><intent><action android:name="android.intent.action.VIEW"/></intent></queries></manifest>
EOF
  # HEALTHY — must be accepted, or the gate teaches everyone to ignore it.
  cat > "$tmp/corpus/healthy/good.xml" <<EOF
$MF
$PERMS
$QUERIES</manifest>
EOF

  # Reconstruct the REAL blind guard from the unit's own git history.
  blind_guard="$tmp/blind_guard.sh"
  if git -C "$APP_DIR" show '96fd023^:tool/assert_manifest_perms.sh' > "$blind_guard" 2>/dev/null; then
    echo "   (reconstructed the pre-96fd023 guard from git — the one that really was blind)"
  else
    echo "   FAIL: could not reconstruct the historical guard from git." >&2
    exit 1
  fi

  pass=0; total=2

  echo ""
  echo "   [1] The REAL blind guard (pre-96fd023) — the gate MUST refuse it:"
  read -r b w bt o <<< "$(run_corpus "$blind_guard" "$tmp/corpus" | tail -1)"
  # Show the detail line-by-line for the record.
  run_corpus "$blind_guard" "$tmp/corpus" | sed '$d' | sed 's/^/   /'
  if [[ "$b" -gt 0 ]]; then
    echo "       => gate REFUSES it ($b blind spot(s)). CORRECT — this guard really did ship."
    pass=$((pass + 1))
  else
    echo "       => gate CERTIFIED a guard we KNOW was blind. The gate is worthless."
  fi

  echo ""
  echo "   [2] The CURRENT guard — the gate MUST certify it:"
  read -r b2 w2 bt2 o2 <<< "$(run_corpus "$APP_DIR/tool/assert_manifest_perms.sh" "$tmp/corpus" | tail -1)"
  run_corpus "$APP_DIR/tool/assert_manifest_perms.sh" "$tmp/corpus" | sed '$d' | sed 's/^/   /'
  if [[ "$b2" -eq 0 && "$w2" -eq 0 ]]; then
    echo "       => gate CERTIFIES it (bit $bt2 mutant(s), accepted $o2 healthy). CORRECT."
    pass=$((pass + 1))
  else
    echo "       => gate refuses the CURRENT guard ($b2 blind, $w2 wolf)."
  fi

  echo ""
  echo ">> SELF-TEST: $pass/$total"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

if [[ $# -lt 2 ]]; then
  echo "usage: tool/loom_mutation_gate.sh <guard> <corpus-dir>   |   --self-test" >&2
  exit 2
fi

GUARD="$1"; CORPUS="$2"

echo ">> L34 mutation gate: a guard is not INSERTED until it has been PROVEN to FAIL"
echo "   guard:  $GUARD"
echo "   corpus: $CORPUS"
echo ""

# Corpus provenance — state it, never adjudicate it (adjudicating independence is
# judgement; a gate that CLAIMED to verify it would be the very failure this stops).
g_author="$(git log -1 --format='%an' -- "$GUARD" 2>/dev/null || echo '?')"
c_author="$(git log -1 --format='%an' -- "$CORPUS" 2>/dev/null || echo '?')"
if [[ "$g_author" == "$c_author" && "$g_author" != "?" ]]; then
  echo "   !! WARNING: guard and mutation corpus share their last author ($g_author)."
  echo "      A builder's mutants encode the builder's model — the same blind spot, one"
  echo "      level up. This gate CANNOT prove independence; it refuses to let the fact"
  echo "      go unstated. Have a non-builder add a mutant."
  echo ""
fi

read -r blind wolf bit ok <<< "$(run_corpus "$GUARD" "$CORPUS" | tail -1)"
run_corpus "$GUARD" "$CORPUS" | sed '$d'

echo ""
if [[ "$blind" -gt 0 ]]; then
  echo "NOT INSERTED: the guard is BLIND to $blind real defect(s) — it said PASS over cloth"
  echo "              we KNOW is broken. Its own self-test proves nothing; it only proves the"
  echo "              builder's imagination. Fix the guard, then come back."
  exit 1
fi
if [[ "$wolf" -gt 0 ]]; then
  echo "NOT INSERTED: the guard CRIES WOLF on $wolf healthy input(s). It will be suppressed"
  echo "              within a day, and an ignored gate is no gate at all."
  exit 1
fi
if [[ "$bit" -eq 0 ]]; then
  echo "NOT INSERTED: the corpus contains NO mutants. A guard proven against nothing is"
  echo "              proven of nothing. Write the mutant that carries the real defect."
  exit 1
fi
echo "CERTIFIED: bit $bit/$bit mutant(s), accepted $ok healthy input(s)."
echo "           The thread was broken and the machine stopped."
exit 0
