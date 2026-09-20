#!/usr/bin/env bash
# Arms HIE's glance gate on THIS app's declared state surfaces.
#
# WHY, written before the act (OPS-070(B)). Komada-voice ruled `d18-2:b` on
# 2026-09-20: arm the glance gate in the app's ci.yml. The RCA's terminus was
# "it did not go green for eight days; it did not run." Re-measured from the
# source rather than inherited: 0 of 39 crontab rows, 0 references in
# .github/workflows/ci.yml, no invoking script. Our own cron_liveness.log had
# been printing `UNARMED  scripts/hie-glance-gate.py  built, no cron row / no
# hook / no armed caller` on every run -- armed, fired, correct, and unread.
#
# The rules are HIE's (tool/hie_glance_gate.py, vendored byte-identical -- see
# tool/hie_glance_gate.SOURCE). tool/glance_gate_run.py holds the declaration
# list and binds the one machine-dependent constant. This file is the entry
# point and the self-test.
#
# See glance_gate_run.py for why a declaration list rather than `--sweep`, and
# for what a green run here does NOT mean.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${GLANCE_GATE_ROOT:-$(cd "$HERE/.." && pwd)}"

die() { echo "GLANCE GATE: $*" >&2; exit 1; }

# A palette the self-test BUILDS, so no case below reads the Flutter SDK.
# tool/selftest-hermeticity-guard.sh classifies a self-test that reads an
# absolute path outside the checkout as OUTSIDE-REPO -- and it caught exactly
# that in this file's first draft, which read the real colors.dart. The sentinel
# swatch is how case (6) proves the palette actually reached the gate.
write_palette_fixture() {
  cat > "$1" <<'DART'
class Colors {
  static const MaterialColor blue = MaterialColor(_bluePrimaryValue, <int, Color>{
    500: Color(_bluePrimaryValue),
    600: Color(0xFF1E88E5),
  });
  static const int _bluePrimaryValue = 0xFF2196F3;
  static const MaterialColor amber = MaterialColor(_amberPrimaryValue, <int, Color>{
    50: Color(0xFFFFF8E1),
    500: Color(_amberPrimaryValue),
  });
  static const int _amberPrimaryValue = 0xFFFFC107;
  static const MaterialColor grey = MaterialColor(_greyPrimaryValue, <int, Color>{
    500: Color(_greyPrimaryValue),
    900: Color(0xFF212121),
  });
  static const int _greyPrimaryValue = 0xFF9E9E9E;
}
DART
}

# A minimal pixel-sampling guard, so C3b can be discharged without copying a
# real test out of the tree.
write_guard_fixture() {
  printf '// fixture guard\nvoid main() { image.toByteData(); }\n' > "$1"
}

# A tri-state widget. $2 = "hue-only" (one shape, one size) or "distinct".
write_widget_fixture() {
  local out="$1" mode="$2" shape_b size_b
  if [ "$mode" = "hue-only" ]; then shape_b="BoxShape.circle"; size_b="22"; else shape_b="BoxShape.rectangle"; size_b="20"; fi
  cat > "$out" <<DART
import 'x.dart';
class _HerDot extends StatelessWidget {
  Widget build(BuildContext context) {
    if (degraded) {
      return Container(width: 22, height: 22,
        decoration: BoxDecoration(color: Colors.grey.shade900, shape: BoxShape.circle));
    }
    if (isMock) {
      return Container(width: $size_b, height: $size_b,
        decoration: BoxDecoration(color: Colors.amber.shade50, shape: $shape_b));
    }
    return Container(width: 22, height: 22,
      decoration: BoxDecoration(color: Colors.blue.shade600, shape: BoxShape.circle));
  }
}
DART
}

# Builds a throwaway tree that the driver's real declaration list points into.
build_fixture_tree() {
  local dir="$1" mode="$2"
  mkdir -p "$dir/lib" "$dir/test/render_see"
  write_widget_fixture "$dir/lib/akita_map.dart" "$mode"
  write_guard_fixture "$dir/test/render_see/her_dot_glance_capture_test.dart"
}

self_test() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  local fails=0 pal="$tmp/colors.dart"
  write_palette_fixture "$pal"

  run_fixture() {  # $1=tree  (extra env via caller)
    ( GLANCE_GATE_ROOT="$1" GLANCE_SDK_COLORS="${GLANCE_SDK_COLORS_OVERRIDE:-$pal}" \
      python3 "$HERE/glance_gate_run.py" ) 2>&1
  }

  # (1) TEETH. A tri-state surface separated by HUE ALONE must be refused. This
  #     is the real 2026-09-13 defect: _HerDot failed at 1.098:1 with colour as
  #     its only channel, which is why it now differs in shape and size.
  build_fixture_tree "$tmp/red" hue-only
  if run_fixture "$tmp/red" >/dev/null 2>&1; then
    echo "[self-test] HUE-ONLY tri-state: PASS -> WRONG. This guard has no teeth."; fails=1
  else
    echo "[self-test] HUE-ONLY tri-state (the real 2026-09-13 defect): refused -> correct"
  fi

  # (2) NOT ALWAYS RED. The same fixture, states separated by shape AND size,
  #     must PASS -- otherwise (1) proves nothing.
  build_fixture_tree "$tmp/green" distinct
  if run_fixture "$tmp/green" >/dev/null 2>&1; then
    echo "[self-test] SHAPE+SIZE tri-state: accepted -> correct (so (1) is a real refusal, not a guard that fails everything)"
  else
    echo "[self-test] SHAPE+SIZE tri-state: refused -> WRONG. This guard fails closed on everything and says nothing."; fails=1
  fi

  # (3) ABSENCE OF THE GATE. memory a-guard-that-fails-open-is-not-a-guard:
  #     vision.sh gave byte-identical output run vs chmod -x. Test the ABSENCE.
  if ( GLANCE_GATE_PY="$tmp/no-such-gate.py" GLANCE_GATE_ROOT="$tmp/green" \
       GLANCE_SDK_COLORS="$pal" python3 "$HERE/glance_gate_run.py" ) >/dev/null 2>&1; then
    echo "[self-test] MISSING GATE: PASS -> WRONG. It fails open."; fails=1
  else
    echo "[self-test] MISSING GATE (deleted / renamed / chmod -x): refused -> correct"
  fi

  # (4) STALE DECLARATION. A declaration naming a class the file no longer
  #     declares must FAIL, not quietly check nothing.
  build_fixture_tree "$tmp/stale" distinct
  sed -i 's/^class _HerDot extends/class _HerDotRenamed extends/' "$tmp/stale/lib/akita_map.dart"
  if run_fixture "$tmp/stale" >/dev/null 2>&1; then
    echo "[self-test] STALE DECLARATION: PASS -> WRONG. It reports success having checked nothing."; fails=1
  else
    echo "[self-test] STALE DECLARATION (class renamed out from under the list): refused -> correct"
  fi

  # (5) EMPTY LIST. memory gh-search-issues-false-negative: an empty match is
  #     UNMEASURED, never absence.
  if ( GLANCE_GATE_EMPTY=1 GLANCE_GATE_ROOT="$tmp/green" GLANCE_SDK_COLORS="$pal" \
       python3 "$HERE/glance_gate_run.py" ) >/dev/null 2>&1; then
    echo "[self-test] EMPTY DECLARATION LIST: PASS -> WRONG. Zero checks read as a clean run."; fails=1
  else
    echo "[self-test] EMPTY DECLARATION LIST: refused -> correct"
  fi

  # (6) THE PALETTE ACTUALLY REACHES THE GATE. The author's first driver printed
  #     `palette from <path>` while the gate read the HARDCODED SDK path instead,
  #     because load_material_palette's default binds at definition time. A
  #     provenance line that names a file nobody read is a success-shaped value.
  #     Proof: rewrite blue.shade600 to the sentinel and require it in the output.
  #     The sentinel is a bright green whose CONTRAST legitimately fails, so this
  #     case reads the OUTPUT and deliberately ignores the exit status: the
  #     question is whether the palette was read, not whether the surface passed.
  sed -i 's/600: Color(0xFF1E88E5)/600: Color(0xFF00FF00)/' "$pal"
  sentinel_out="$(run_fixture "$tmp/green" || true)"
  if printf '%s' "$sentinel_out" | grep -q '#00FF00'; then
    echo "[self-test] PALETTE BINDING (sentinel swatch reaches the gate): correct"
  else
    echo "[self-test] PALETTE BINDING: the gate did NOT read the palette this driver named -> WRONG."; fails=1
  fi

  # (7) PALETTE ABSENT must FAIL, never resolve silently to nothing.
  if ( GLANCE_SDK_COLORS_OVERRIDE="$tmp/no-such-palette.dart" run_fixture "$tmp/green" ) >/dev/null 2>&1; then
    echo "[self-test] PALETTE ABSENT: PASS -> WRONG. Shade names unresolved and a verdict issued anyway."; fails=1
  else
    echo "[self-test] PALETTE ABSENT (no Flutter SDK on this machine): refused -> correct"
  fi

  if [ "$fails" -ne 0 ]; then
    echo "[self-test] THIS GUARD IS NOT INSERTABLE. It did not refuse what it must refuse."
    return 1
  fi
  echo "[self-test] refuses a hue-only surface, accepts a shape/size one, and fails closed on a missing gate, a stale declaration, an empty list and an unread palette."
  return 0
}

case "${1:-}" in
  --self-test) self_test ;;
  --drift-check)
    # Runs ONLY where both trees exist -- never in CI, because the governance
    # repo has no remote and a runner cannot see the copy this was vendored from.
    src="${GLANCE_GATE_SRC:-$HOME/Documents/LLMnotebooks/toyota flutter masterplan/scripts/hie-glance-gate.py}"
    [ -f "$src" ] || die "no governance copy at $src -- drift UNVERIFIED, never cleared."
    a="$(md5sum "$src" | cut -d' ' -f1)"; b="$(md5sum "$HERE/hie_glance_gate.py" | cut -d' ' -f1)"
    if [ "$a" = "$b" ]; then echo "GLANCE GATE: vendored copy matches the governance copy ($a)."
    else die "DRIFT: governance $a vs vendored $b. Re-vendor from HIE's copy; never edit this one."; fi
    ;;
  "") exec python3 "$HERE/glance_gate_run.py" ;;
  *) die "usage: glance_gate.sh [--self-test | --drift-check]" ;;
esac
