#!/usr/bin/env bash
# offline_voice_render_guard.sh — does every bundled offline clip still say the
# words its catalog entry holds?
#
# WHY THIS EXISTS (2026-09-18)
# ----------------------------
# The offline voice finds a clip by the exact words the app is about to speak:
# lib/voice/offline_safety_voice.dart maps an id to those words, and
# assets/audio/ja/<id>.wav is the audio. The words come from
# navigation_safety_core. Core 0.11.9 changed two wet-ice sentences. With the
# two catalog values moved to the new words and both clips left as they were,
# all 1251 tests of `flutter test` and `bash tool/render_offline_voice.sh
# --check` were green on exactly that tree, because none of them opens a clip:
#   - test/voice/runtime_voice_coverage_test.dart, offline_safety_voice_test.dart
#     and test/dead_zone/c2_offline_survival_test.dart compare words with words,
#     and check that each clip exists and is larger than 8000 bytes;
#   - `render_offline_voice.sh --check` checks that each clip exists;
#   - the phoneme oracle renders the words to a scratch file and never opens the
#     committed clip;
#   - tool/check_bundled_audio_in_apk.py (CI, after an APK build) reads clip
#     NAMES in the APK.
# Nothing asked what a clip says. Offline, the new sentence would have been
# answered with the old sentence's audio.
#
# WHAT IT DOES
#   Copies the render tool and the catalog into an empty temporary directory,
#   renders every clip there with tool/render_offline_voice.sh exactly as it is
#   in this checkout, and compares each rendered clip byte for byte with the
#   clip in assets/audio/ja/. Per id it reports:
#     match    the clip is what its words render to
#     DIFF     the clip exists and is not what its words render to
#     MISSING  the catalog has words for the id and there is no clip
#     ORPHAN   there is a clip for an id the catalog does not render
#   This works because the renderer is deterministic: on 2026-09-17 and again
#   on 2026-09-18 the render tool reproduced all 40 committed clips byte for
#   byte with open-jtalk 1.11-5, open-jtalk-mecab-naist-jdic 1.11-5 and
#   hts-voice-nitech-jp-atr503-m001 1.05-8 (Ubuntu 24.04 packages).
#
# HONEST BOUNDS
#   - Equal bytes mean "this is what the engine renders from these words". They
#     do not mean the clip sounds right. Nothing here listens; a person does.
#   - The clips are bytes of ONE engine build. Another engine version, another
#     dictionary or another resampler gives other bytes for the same words, and
#     this guard then reports clips as DIFF. The engine versions are printed
#     first, so a red in which every clip differs is read as an engine change
#     before it is read as a change of words.
#   - If the clips are replaced by human recordings (the catalog header plans
#     that), this check no longer fits them. It fails loudly; it does not pass.
#   - It judges the files on disk in the checkout it sits in, uncommitted edits
#     included. In CI that is the commit.
#   - The render tool writes intermediates to /tmp/_oj_<id>.wav. Two renders of
#     the same id at the same moment can overwrite each other. That can make a
#     false DIFF, never a false match.
#   - Anything it cannot evaluate (no open_jtalk, no python3 with audioop, a
#     render that fails) exits 3. Never 0.
#
# Usage:
#   bash tool/offline_voice_render_guard.sh              # check this checkout
#   bash tool/offline_voice_render_guard.sh --self-test  # prove it bites
# Exit: 0 every clip is what its words render to
#       1 at least one DIFF, MISSING or ORPHAN
#       3 could not evaluate: nothing was compared, so nothing is cleared
set -uo pipefail

# Resolved with shell builtins only, so the no-engine case can run with no PATH.
_src="${BASH_SOURCE[0]}"
case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir="." ;; esac
ROOT="$(cd "$_dir/.." && pwd)" || { echo "UNDETERMINED: cannot resolve the checkout from $_src"; exit 3; }
SELF_NAME="${_src##*/}"

TOOL_REL="tool/render_offline_voice.sh"
CATALOG_REL="lib/voice/offline_safety_voice.dart"
CLIPS_REL="assets/audio/ja"
ENGINE_PKGS="open-jtalk open-jtalk-mecab-naist-jdic hts-voice-nitech-jp-atr503-m001"

nothing_cleared() { echo "  Nothing was compared, so nothing is cleared."; }

# Renders the catalog of <root> into <tmp>/copy and compares with <root>'s clips.
render_and_compare() {
  local root="$1" tmp="$2"
  local copy="$tmp/copy"

  mkdir -p "$copy/tool" "$copy/lib/voice" \
    && cp "$root/$TOOL_REL" "$copy/$TOOL_REL" \
    && cp "$root/$CATALOG_REL" "$copy/$CATALOG_REL" \
    || { echo "UNDETERMINED: could not build the clean copy."; nothing_cleared; return 3; }
  if [ -e "$copy/$CLIPS_REL" ]; then
    echo "UNDETERMINED: the clean copy already holds a clip directory."; nothing_cleared; return 3
  fi

  echo ">> offline voice render guard: does every clip in $CLIPS_REL say its catalog words?"
  local p v engine=""
  for p in $ENGINE_PKGS; do
    v="$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)" || v=""
    engine="$engine $p ${v:-unknown},"
  done
  echo "   engine  :${engine%,}"
  echo "   python3 : $(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || echo unknown)"

  if ! bash "$copy/$TOOL_REL" > "$tmp/render.out" 2>&1; then
    echo "UNDETERMINED: $TOOL_REL failed in the clean copy. Its last lines:"
    tail -5 "$tmp/render.out" | sed -e "s|$tmp|<clean copy>|g" -e 's/^/     /'
    nothing_cleared
    return 3
  fi

  local said rendered_n=0 f
  said="$(sed -n 's/^Rendering \([0-9][0-9]*\) ja safety phrases.*/\1/p' "$tmp/render.out" | head -1)"
  for f in "$copy/$CLIPS_REL"/*.wav; do [ -f "$f" ] && rendered_n=$((rendered_n + 1)); done
  if [ -z "$said" ] || [ "$said" -eq 0 ] || [ "$said" -ne "$rendered_n" ]; then
    echo "UNDETERMINED: the render tool announced '${said:-nothing}' phrases and left $rendered_n clips."
    nothing_cleared
    return 3
  fi
  echo "   rendered: $rendered_n clips from $CATALOG_REL in a clean copy, with $TOOL_REL"

  local ids id c r total=0 match=0 differ=0 missing=0 orphan=0
  ids="$(for f in "$copy/$CLIPS_REL"/*.wav "$root/$CLIPS_REL"/*.wav; do
           [ -f "$f" ] || continue
           f="${f##*/}"; printf '%s\n' "${f%.wav}"
         done | LC_ALL=C sort -u)"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    total=$((total + 1))
    c="$root/$CLIPS_REL/$id.wav"
    r="$copy/$CLIPS_REL/$id.wav"
    if [ -f "$c" ] && [ -f "$r" ]; then
      # cmp exits 2 when it cannot read: counted as DIFF, the safe direction.
      if cmp -s "$c" "$r"; then
        match=$((match + 1))
        printf '   match    %s\n' "$id"
      else
        differ=$((differ + 1))
        printf '   DIFF     %-40s committed=%s rendered=%s\n' "$id" \
          "$(sha256sum < "$c" | cut -c1-12)" "$(sha256sum < "$r" | cut -c1-12)"
      fi
    elif [ -f "$r" ]; then
      missing=$((missing + 1))
      printf '   MISSING  %-40s (the catalog has words for it; %s has no clip)\n' "$id" "$CLIPS_REL"
    else
      orphan=$((orphan + 1))
      printf '   ORPHAN   %-40s (a clip for an id the catalog does not render)\n' "$id"
    fi
  done <<< "$ids"

  local bad=$((differ + missing + orphan))
  echo ""
  if [ "$bad" -eq 0 ]; then
    echo "OK: $match of $total clips are byte-identical to what their catalog words render to."
    echo "    Byte identity is not a listening test; nobody's ear is in this check."
    return 0
  fi
  echo "FAIL: $bad of $total clips are not what their catalog words render to (DIFF $differ, MISSING $missing, ORPHAN $orphan)."
  echo "  When words move, re-render with 'bash $TOOL_REL', have a person listen to"
  echo "  the clips that changed, and commit the words and the clips together."
  if [ "$differ" -eq "$total" ]; then
    echo "  Every clip differs: compare the engine line above with the engine the"
    echo "  clips were rendered with before suspecting the words."
  fi
  return 1
}

check_checkout() {
  local root="$1"
  if ! command -v open_jtalk >/dev/null 2>&1; then
    echo "UNDETERMINED: open_jtalk is not installed, so no clip can be re-rendered."
    echo "  On Ubuntu 24.04: sudo apt-get install $ENGINE_PKGS"
    nothing_cleared
    return 3
  fi
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -W ignore -c 'import audioop' >/dev/null 2>&1; then
    echo "UNDETERMINED: the render tool needs python3 with the audioop module (removed in Python 3.13)."
    nothing_cleared
    return 3
  fi
  local f
  for f in "$TOOL_REL" "$CATALOG_REL"; do
    if [ ! -f "$root/$f" ]; then
      echo "UNDETERMINED: $f is not in this checkout."; nothing_cleared; return 3
    fi
  done

  local tmp rc
  tmp="$(mktemp -d)" || { echo "UNDETERMINED: mktemp failed."; return 3; }
  if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
    echo "UNDETERMINED: mktemp produced no usable directory."; return 3
  fi
  render_and_compare "$root" "$tmp"; rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# ---------------------------------------------------------------- self-test
SELFTEST_CASES=0
SELFTEST_FAILS=0

# expect <n> <label> <want-exit> <got-exit> <output> <must-match-ERE> <must-not-match-ERE>
expect_case() {
  local ok=1
  SELFTEST_CASES=$((SELFTEST_CASES + 1))
  [ "$4" = "$3" ] || ok=0
  if [ -n "$6" ] && ! grep -qE -- "$6" <<< "$5"; then ok=0; fi
  if [ -n "$7" ] && grep -qE -- "$7" <<< "$5"; then ok=0; fi
  if [ "$ok" -eq 1 ]; then
    printf '   [%s] ok      %s (exit %s)\n' "$1" "$2" "$4"
  else
    printf '   [%s] FAILED  %s: wanted exit %s, got %s\n' "$1" "$2" "$3" "$4"
    printf '%s\n' "$5" | head -14 | sed 's/^/          | /'
    SELFTEST_FAILS=$((SELFTEST_FAILS + 1))
  fi
}

# A two-entry catalog in the shape the render tool parses. Both are real lines
# this app has spoken: the wet-ice line as navigation_safety_core 0.11.8 said
# it (or, when given, the line 0.11.9 says instead), and an ice line that did
# not change. The ids are the fixture's own, so a render of the real catalog
# running at the same moment never shares an intermediate file with this one.
write_fixture_catalog() {
  cat > "$1" <<EOF
// Fixture written by tool/$SELF_NAME --self-test.
library;

const Map<String, String> kOfflineSafetyVoiceJa = <String, String>{
  'guard_selftest_wet_ice':
      '$2',
  'guard_selftest_ice':
      '凍結、30km/h',
};

const Map<String, String> kOfflineSafetyVoiceRenderJa = <String, String>{};
EOF
}

self_test() {
  echo ">> SELF-TEST: does the render guard bite a clip that no longer says its words,"
  echo "   and refuse to pass what it could not render?"
  if ! command -v open_jtalk >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1 \
     || ! python3 -W ignore -c 'import audioop' >/dev/null 2>&1; then
    echo "UNDETERMINED: the self-test renders real clips and needs open_jtalk and python3 with audioop."
    echo "  It proved nothing, so it is not a pass."
    return 3
  fi
  if [ ! -f "$ROOT/$TOOL_REL" ] || [ ! -f "$ROOT/tool/$SELF_NAME" ]; then
    echo "UNDETERMINED: $TOOL_REL or tool/$SELF_NAME is not in this checkout."
    return 3
  fi

  local work
  work="$(mktemp -d)" || { echo "UNDETERMINED: mktemp failed."; return 3; }
  if [ -z "$work" ] || [ ! -d "$work" ]; then
    echo "UNDETERMINED: mktemp produced no usable directory."; return 3
  fi
  local fx="$work/fixture"
  local old_words='アイスバーン、最危険、20km/h以下'
  local new_words='アイスバーン、極めて危険、20km/h以下'

  mkdir -p "$fx/tool" "$fx/lib/voice" \
    && cp "$ROOT/$TOOL_REL" "$fx/$TOOL_REL" \
    && cp "$ROOT/tool/$SELF_NAME" "$fx/tool/$SELF_NAME" \
    || { echo "UNDETERMINED: could not build the fixture."; rm -rf "$work"; return 3; }
  write_fixture_catalog "$fx/$CATALOG_REL" "$old_words"
  # The fixture's committed clips: rendered by the real tool from their own words.
  if ! ( cd "$fx" && bash "$TOOL_REL" ) > /dev/null 2>&1; then
    echo "UNDETERMINED: the render tool could not render the fixture."; rm -rf "$work"; return 3
  fi
  cp -R "$fx/$CLIPS_REL" "$work/golden" || { echo "UNDETERMINED: could not keep the fixture clips."; rm -rf "$work"; return 3; }

  restore() {
    write_fixture_catalog "$fx/$CATALOG_REL" "$old_words"
    rm -rf "$fx/$CLIPS_REL" && cp -R "$work/golden" "$fx/$CLIPS_REL"
  }
  run_guard() { ( cd "$fx" && bash "tool/$SELF_NAME" ) 2>&1; }

  local out rc

  out="$(run_guard)"; rc=$?
  expect_case 1 "clips rendered from their own words pass" 0 "$rc" "$out" \
    '^OK: 2 of 2 clips' '^   (DIFF|MISSING|ORPHAN) '

  write_fixture_catalog "$fx/$CATALOG_REL" "$new_words"
  out="$(run_guard)"; rc=$?
  expect_case 2 "words moved, clip not re-rendered: fails on that id alone" 1 "$rc" "$out" \
    '^   DIFF +guard_selftest_wet_ice +committed=' '^   DIFF +guard_selftest_ice +committed=|^   (MISSING|ORPHAN) |^OK:'

  ( cd "$fx" && bash "$TOOL_REL" ) > /dev/null 2>&1
  out="$(run_guard)"; rc=$?
  expect_case 3 "the same words moved with the clip re-rendered pass" 0 "$rc" "$out" \
    '^OK: 2 of 2 clips' '^   (DIFF|MISSING|ORPHAN) '
  restore

  mv "$fx/$CLIPS_REL/guard_selftest_wet_ice.wav" "$work/swap.wav" \
    && mv "$fx/$CLIPS_REL/guard_selftest_ice.wav" "$fx/$CLIPS_REL/guard_selftest_wet_ice.wav" \
    && mv "$work/swap.wav" "$fx/$CLIPS_REL/guard_selftest_ice.wav"
  out="$(run_guard)"; rc=$?
  expect_case 4 "two clips swapped: the ice id fails" 1 "$rc" "$out" \
    'DIFF +guard_selftest_ice +committed=' '^OK:'
  expect_case 5 "two clips swapped: the wet-ice id fails too" 1 "$rc" "$out" \
    'DIFF +guard_selftest_wet_ice +committed=' '^OK:'
  restore

  rm -f "$fx/$CLIPS_REL/guard_selftest_ice.wav"
  out="$(run_guard)"; rc=$?
  expect_case 6 "a clip deleted: MISSING" 1 "$rc" "$out" \
    'MISSING +guard_selftest_ice ' '^OK:'
  restore

  cp "$fx/$CLIPS_REL/guard_selftest_ice.wav" "$fx/$CLIPS_REL/guard_selftest_retired.wav"
  out="$(run_guard)"; rc=$?
  expect_case 7 "a clip no catalog entry renders: ORPHAN" 1 "$rc" "$out" \
    'ORPHAN +guard_selftest_retired ' '^OK:'
  restore

  out="$(cd "$fx" && PATH="/nonexistent-offline-voice-guard" "$BASH" "tool/$SELF_NAME" 2>&1)"; rc=$?
  expect_case 8 "no open_jtalk: UNDETERMINED, never a pass" 3 "$rc" "$out" \
    '^UNDETERMINED: open_jtalk' '^OK:|^FAIL:'

  mkdir -p "$work/shim_python" "$work/shim_jtalk"
  printf '#!/bin/sh\nexit 1\n' > "$work/shim_python/python3"
  printf '#!/bin/sh\nexit 1\n' > "$work/shim_jtalk/open_jtalk"
  chmod +x "$work/shim_python/python3" "$work/shim_jtalk/open_jtalk"

  out="$(cd "$fx" && PATH="$work/shim_python:$PATH" bash "tool/$SELF_NAME" 2>&1)"; rc=$?
  expect_case 9 "python3 without audioop: UNDETERMINED, never a pass" 3 "$rc" "$out" \
    '^UNDETERMINED: the render tool needs python3' '^OK:|^FAIL:'

  out="$(cd "$fx" && PATH="$work/shim_jtalk:$PATH" bash "tool/$SELF_NAME" 2>&1)"; rc=$?
  expect_case 10 "a render that fails: UNDETERMINED, nothing compared" 3 "$rc" "$out" \
    "^UNDETERMINED: $TOOL_REL failed" '^OK:|^FAIL:|^   (match|DIFF|MISSING|ORPHAN) '

  out="$(run_guard)"; rc=$?
  expect_case 11 "the restored fixture passes again" 0 "$rc" "$out" \
    '^OK: 2 of 2 clips' '^   (DIFF|MISSING|ORPHAN) '

  rm -rf "$work"
  echo ""
  if [ "$SELFTEST_FAILS" -eq 0 ]; then
    echo "SELF-TEST OK: $SELFTEST_CASES/$SELFTEST_CASES cases behaved."
    return 0
  fi
  echo "SELF-TEST FAILED: $SELFTEST_FAILS of $SELFTEST_CASES cases misbehaved. Do not trust this guard until they pass."
  return 1
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi
check_checkout "$ROOT"
exit $?
