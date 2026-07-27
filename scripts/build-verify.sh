#!/usr/bin/env bash
# build-verify.sh — THE committed build lane for sngnav-app (P2, restructuring
# plan 2026-07-26: "No green is claimable unless the exact invocation + image
# digest + underlay is committed beside the code, same turn").
#
# This is the exact invocation whose green was claimed for commit a900e94
# (2026-07-27): analyze + full test suite (532 tests at that head).
#
# Phases:
#   1. toolchain pin check  — record the real toolchain; WARN loudly on drift
#      from the pinned revision (pixels + shaping are engine-version-specific,
#      so a drifted toolchain invalidates any golden/render claim).
#   2. flutter analyze      — hard gate.
#   3. flutter test         — hard gate (full suite; render_see suites degrade
#      honestly on fontless hosts, see test/render_see/render_see_env.dart).
#
# Optional:
#   --render-see   additionally regenerate the OPS-066 ladder_out/ PNGs
#                  (goldens updated). A green run of this phase is NOT
#                  verification — a HUMAN must LOOK at the PNGs. The script
#                  cannot and does not affirm them.
#
# Honest bounds:
#   - This lane proves code correctness on the host, NOT feature correctness
#     on a device. On-device verification (share sheet, TTS, GNSS) is the
#     device hour's job (OPS-066 / AAE lane) and is NOT claimed here.

set -uo pipefail

# Toolchain pinned at the last claimed green (2026-07-27, commit a900e94):
PINNED_FRAMEWORK_REV="3947205d67"
PINNED_DART="3.11.1"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

RENDER_SEE=0
for arg in "$@"; do
  case "$arg" in
    --render-see) RENDER_SEE=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "=== phase 1: toolchain ==="
VERSION_OUT="$(flutter --version 2>/dev/null)"
echo "$VERSION_OUT"
if ! grep -q "$PINNED_FRAMEWORK_REV" <<<"$VERSION_OUT"; then
  echo "!!! TOOLCHAIN DRIFT: framework revision is not $PINNED_FRAMEWORK_REV." >&2
  echo "!!! Any golden/render claim from this run does NOT reproduce the pinned green." >&2
fi
if ! grep -q "Dart $PINNED_DART" <<<"$VERSION_OUT"; then
  echo "!!! TOOLCHAIN DRIFT: Dart is not $PINNED_DART." >&2
fi

echo "=== phase 2: flutter analyze ==="
flutter analyze || { echo "FAIL: analyze" >&2; exit 1; }

echo "=== phase 3: flutter test ==="
flutter test || { echo "FAIL: test" >&2; exit 1; }

if [ "$RENDER_SEE" -eq 1 ]; then
  echo "=== optional: render-SEE capture (OPS-066) ==="
  flutter test --update-goldens test/render_see/ \
    || { echo "FAIL: render_see capture" >&2; exit 1; }
  echo ">>> PNGs regenerated under ladder_out/."
  echo ">>> A green here is NOT verification: a HUMAN must LOOK at them (OPS-066)."
fi

echo "=== build-verify: GREEN (host lane; on-device claims NOT made) ==="
