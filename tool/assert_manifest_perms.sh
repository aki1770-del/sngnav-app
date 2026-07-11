#!/usr/bin/env bash
# WS8 perm-assert loom (BOD-17) — the WS1 dead-HER-dot blocker can never re-ship.
#
# Why this exists: the 2026-06-30 Android review found sngnav-app was 100% dead
# for HER because the release AndroidManifest was missing INTERNET and
# ACCESS_FINE_LOCATION — so a release build silently fetched nothing and the
# location dot never came alive. WS1 added the perms; this loom asserts they
# stay declared, so a future edit that drops them FAILS CI instead of shipping a
# dead app to HER.
#
# PERM SCOPE (re-authored 2026-07-11, BOD-19 — pending DIA re-certification).
#
#   The prior "DIA-certified SOUND PARTIAL, 2026-07-01" stamp is RETIRED: DIA's own
#   round-3 attacks FALSIFIED it. The certified regex passed a manifest that stripped
#   ACCESS_FINE_LOCATION via tools:node="removeAll" — printing "3 WS1-blocker
#   permissions effectively declared" over HER DEAD LOCATION DOT, which is the very
#   regression of 2026-06-30 that this script was written to make impossible. It also
#   blessed a <uses-permission> misplaced inside <application> or <queries>, where it
#   grants nothing. A stamp that certifies a loom against the failure it then admits
#   is worse than no stamp: it is false comfort with a signature on it.
#
#   CATCHES (now, via the same parser as the voice lane): a deleted perm; a
#   COMMENTED-OUT perm; a perm neutralised by tools:node="remove" OR "removeAll"; a
#   perm misplaced so it is not a direct child of <manifest>; and any multi-line /
#   quote-style / attribute-order formatting (free, from the parser).
#   DOES NOT CATCH: the MERGED manifest (post-build), the debug/profile variants, or
#   runtime behaviour — those are on-device concerns (docs/DEVICE_VERIFICATION.md,
#   OPS-066). See tripwire S2.
#
# VOICE-LANE SCOPE (added 2026-07-11, BOD-19 — AAE Andon; the 2026-07-01 stamp
# above does NOT cover it, and extending a stale certification over uncertified
# code would itself be a false provenance claim — DIA finding):
#   CATCHES: the TTS_SERVICE intent absent, commented-out, declared outside
#   <queries>, wrongly nested (a <queries> block misplaced inside <application>, or
#   nested inside a removed one, grants nothing — only DIRECT children of <manifest>
#   count), or neutralised by tools:node="remove"/"removeAll" on the <queries> /
#   <intent> / <action>. Containment is checked by XML PARSE, not regex — DIA REFUSED
#   a regex version that blessed a dead voice lane (greedy span across two <queries>
#   blocks), then caught FOUR more false PASSes in the parser version (recursive
#   iter(); an unknown "removeAll"). The attacks are the fixtures below.
#   DOES NOT CATCH: the merged manifest (a plugin could strip <queries> at merge);
#   the debug/profile variants; whether a TTS engine is installed on HER device;
#   whether ja voice DATA is present; whether speak() is AUDIBLE. Those are
#   OPS-066 on-device concerns. And the deeper root — our speak() call sits inside
#   a catch that swallows the error — is NOT asserted here. The manifest is only
#   ONE of several ways this lane can die quietly. This loom is a SOUND PARTIAL and
#   must never be sold as proof that HER voice lane works.
#
# Usage:
#   tool/assert_manifest_perms.sh            # assert the app manifest
#   tool/assert_manifest_perms.sh --self-test
# Exit: 0 = all required perms effectively declared | 1 = a required perm is
#       MISSING / commented-out / removed (HALT).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The WS1-blocker set: without these a release build is silently dead for HER.
REQUIRED_PERMS=(
  "android.permission.INTERNET"
  "android.permission.ACCESS_FINE_LOCATION"
  "android.permission.ACCESS_COARSE_LOCATION"
)

# The VOICE-LANE blocker set (BOD-19, 2026-07-11 — AAE Andon).
#
# Android 11+ package visibility: without a <queries> declaration for
# TTS_SERVICE, the engine cannot SEE the system text-to-speech service and
# flutter_tts's speak() fails SILENTLY into our catch block — HER ja black-ice
# warning dies with NO error surfaced. We hit this, fixed the manifest (9aad0d5),
# and did NOT teach the loom to catch it: a regression deleting the block shipped
# silently while this script printed PASS. A green verdict over defective cloth is
# the anti-loom in its exact pre-Sakichi form. This closes it.
#
# The intent MUST live inside <queries> — an action declared anywhere else does
# not grant visibility, so "present in the file" is not the test.
REQUIRED_QUERY_INTENTS=(
  "android.intent.action.TTS_SERVICE"
)

assert_manifest() {
  local manifest="$1"
  if [[ ! -f "$manifest" ]]; then
    echo "FAIL: manifest not found at $manifest" >&2
    return 1
  fi

  # ---------------------------------------------------------------------------
  # ONE PARSER, BOTH LANES.
  #
  # The perms lane used to be a regex, and it carried the SAME half-closed seam
  # twice over (DIA round 3, 2026-07-11):
  #   - value set: `tools:node *= *["']remove["']` CANNOT match `removeAll` — after
  #     `remove` it demands a quote and finds `A`. A manifest stripping
  #     ACCESS_FINE_LOCATION via tools:node="removeAll" therefore PASSED, and the
  #     guard printed "3 WS1-blocker permissions effectively declared" over HER DEAD
  #     LOCATION DOT — the exact 2026-06-30 failure this whole script exists to stop.
  #   - position: not checked at all — a <uses-permission> pasted inside
  #     <application> or <queries> grants nothing, and was blessed.
  #
  # The lesson is the seam, not the typo: the element set was closed and the value
  # set left open — first in the voice lane, then again in the perms lane beside it.
  # So there is now exactly ONE engine, with one removal set and one positional rule,
  # and no second place for the seam to hide. The parser strictly dominates the regex:
  # it drops comments natively, and handles multiline / quote-style / attribute-order
  # for free (the old `cleaned` preprocessing step is gone as redundant).
  # ---------------------------------------------------------------------------
  local report
  report="$(python3 - "$manifest" "${REQUIRED_PERMS[@]}" "--" "${REQUIRED_QUERY_INTENTS[@]}" <<'PY'
import sys, xml.etree.ElementTree as ET

A = '{http://schemas.android.com/apk/res/android}name'
T = '{http://schemas.android.com/tools}node'

path = sys.argv[1]
rest = sys.argv[2:]
split = rest.index('--')
perms, intents = rest[:split], rest[split + 1:]

try:
    root = ET.parse(path).getroot()      # ElementTree drops XML comments for us
except ET.ParseError as e:
    print(f'MANIFEST ({path}) is not parseable XML ({e})')
    sys.exit(0)

def kept(el):
    """A node stripped at merge grants nothing. 'remove' AND 'removeAll' are both
    real, documented manifest-merger removals. 'replace' is NOT a removal."""
    return (el.get(T) or '').strip().lower() not in ('remove', 'removeall')

# --- PERMS lane: <uses-permission> must be a LIVE DIRECT CHILD of <manifest>. ---
for perm in perms:
    live = [e for e in root.findall('uses-permission')
            if e.get(A) == perm and kept(e)]
    if live:
        continue
    declared = [e for e in root.iter('uses-permission') if e.get(A) == perm]
    if not declared:
        print(f'{perm} (absent / commented-out)')
    elif any(not kept(e) for e in declared):
        print(f'{perm} (tools:node="remove"/"removeAll" — stripped from the merged '
              f'manifest; the permission is NOT granted)')
    else:
        print(f'{perm} (declared, but NOT a direct child of <manifest> — misplaced '
              f'inside another element; the permission is NOT granted)')

# --- VOICE lane: the intent must live in a LIVE queries > intent > action. ---
# Android package visibility (API 30+): without this, the engine cannot see the TTS
# service and flutter_tts speak() fails SILENTLY — HER ja warning dies unheard.
blocks = root.findall('queries')     # direct children of <manifest> ONLY; iter() would
                                     # bless a block misplaced inside <application>
live_blocks = [q for q in blocks if kept(q)]
for want in intents:
    found = False
    for q in live_blocks:
        for it in q.findall('intent'):
            if not kept(it):
                continue
            for ac in it.findall('action'):
                if kept(ac) and ac.get(A) == want:
                    found = True
    if found:
        continue
    if not blocks:
        print(f'{want} (no <queries> block — absent or commented-out)')
    elif not live_blocks:
        print(f'{want} (<queries> tools:node="remove"/"removeAll" — stripped at merge)')
    elif any(el.get(A) == want for el in root.iter('action')):
        print(f'{want} (declared, but NOT inside a live <queries><intent> — removed '
              f'node, wrong nesting, or outside <queries>; grants NO package '
              f'visibility, so TTS speak() will fail SILENTLY)')
    else:
        print(f'{want} (not declared inside <queries> — TTS speak() will fail SILENTLY)')
PY
)"

  local missing=()
  if [[ -n "$report" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && missing+=("$line")
    done <<< "$report"
  fi

  if (( ${#missing[@]} > 0 )); then
    echo "FAIL: AndroidManifest is MISSING a required declaration — a release build would be SILENTLY BROKEN for HER:" >&2
    for m in "${missing[@]}"; do echo "  - $m" >&2; done
    echo "  (perm missing => dead location dot / dead network; TTS_SERVICE query missing => dead ja voice lane)" >&2
    echo "Manifest: $manifest" >&2
    return 1
  fi
  echo "PASS: ${#REQUIRED_PERMS[@]} WS1-blocker permissions + ${#REQUIRED_QUERY_INTENTS[@]} voice-lane query intent(s) effectively declared in $manifest"
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  # Shared tail: the perms + the voice-lane <queries> block a healthy manifest has.
  # Every fixture must declare the namespaces a real AndroidManifest declares,
  # or the parser fail-safes on an unbound prefix and the test proves nothing.
  MF='<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">'
  PERMS_OK='<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>'
  QUERIES_OK='<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>'

  cat > "$tmp/good.xml" <<EOF
$MF
$PERMS_OK
$QUERIES_OK</manifest>
EOF
  cat > "$tmp/deleted.xml" <<EOF
$MF
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  cat > "$tmp/commented.xml" <<EOF
$MF
<!-- <uses-permission android:name="android.permission.INTERNET"/> -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  cat > "$tmp/removed.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET" tools:node="remove"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  cat > "$tmp/removed_sq.xml" <<EOF
$MF
<uses-permission android:name='android.permission.INTERNET' tools:node='remove'/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  cat > "$tmp/multiline.xml" <<EOF
$MF
<uses-permission
    android:name = "android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<queries><intent><action
    android:name = 'android.intent.action.TTS_SERVICE' /></intent></queries></manifest>
EOF
  # --- voice-lane fixtures (BOD-19): each of these ships a SILENTLY dead ja voice
  # lane, and every one of them PASSED the pre-BOD-19 guard. ---
  cat > "$tmp/tts_no_queries.xml" <<EOF
$MF
$PERMS_OK</manifest>
EOF
  cat > "$tmp/tts_commented.xml" <<EOF
$MF
$PERMS_OK
<!-- $QUERIES_OK --></manifest>
EOF
  cat > "$tmp/tts_outside_queries.xml" <<EOF
$MF
$PERMS_OK
<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
<queries><intent><action android:name="android.intent.action.PROCESS_TEXT"/></intent></queries></manifest>
EOF
  cat > "$tmp/tts_queries_removed.xml" <<EOF
$MF
$PERMS_OK
<queries tools:node="remove"><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # --- DIA attack fixtures (certification REFUSED 2026-07-11; every one of these
  # produced a FALSE verdict from the regex version). They are permanent now: the
  # attacks that broke the loom become the tests that keep it honest. ---
  # A1 — THE GREEDY TRAP. The intent is outside <queries>, sandwiched between two
  # blocks. A greedy `<queries>.*</queries>` span swallows it and PASSES a dead lane.
  cat > "$tmp/a1_greedy_trap.xml" <<EOF
$MF
$PERMS_OK
<queries><intent><action android:name="android.intent.action.PROCESS_TEXT"/></intent></queries>
<application><activity><intent-filter><action android:name="android.intent.action.TTS_SERVICE"/></intent-filter></activity></application>
<queries><intent><action android:name="android.intent.action.VIEW"/></intent></queries></manifest>
EOF
  # A2 — tools:node="remove" on the <intent> (stripped at merge; grants nothing).
  cat > "$tmp/a2_intent_removed.xml" <<EOF
$MF
$PERMS_OK
<queries><intent tools:node="remove"><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # A3 — tools:node="remove" on the <action> itself.
  cat > "$tmp/a3_action_removed.xml" <<EOF
$MF
$PERMS_OK
<queries><intent><action android:name="android.intent.action.TTS_SERVICE" tools:node="remove"/></intent></queries></manifest>
EOF
  # A6 — healthy lane + an UNRELATED later removed block. Must PASS (the regex
  # version threw a FALSE FAIL here — a confusing CI red on a healthy manifest).
  cat > "$tmp/a6_unrelated_removed.xml" <<EOF
$MF
$PERMS_OK
<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>
<queries tools:node="remove"><intent><action android:name="android.intent.action.VIEW"/></intent></queries></manifest>
EOF
  # A5 — two blocks, first empty, second carries the intent. Must PASS.
  cat > "$tmp/a5_two_blocks_ok.xml" <<EOF
$MF
$PERMS_OK
<queries></queries>
<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # A8 — bare <action> under <queries> with no <intent> wrapper: an invalid shape
  # that grants no visibility. Must be REJECTED, not blessed.
  cat > "$tmp/a8_bare_action.xml" <<EOF
$MF
$PERMS_OK
<queries><action android:name="android.intent.action.TTS_SERVICE"/></queries></manifest>
EOF
  # --- DIA round-2 attacks (certification CONDITIONED 2026-07-11): four more false
  # PASSes, from two root causes — a RECURSIVE iter() that blessed <queries> anywhere
  # in the tree, and a removal set that had never heard of "removeAll". ---
  # P1 — <queries> misplaced INSIDE <application> (a realistic paste-slip). Android
  # requires it as a direct child of <manifest>; there it grants NOTHING.
  cat > "$tmp/p1_queries_in_application.xml" <<EOF
$MF
$PERMS_OK
<application><queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></application></manifest>
EOF
  # P2 — tools:node="removeAll" on <queries>: a REAL merger value that strips it.
  cat > "$tmp/p2_removeall_queries.xml" <<EOF
$MF
$PERMS_OK
<queries tools:node="removeAll"><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # P3 — tools:node="removeAll" on the <intent>.
  cat > "$tmp/p3_removeall_intent.xml" <<EOF
$MF
$PERMS_OK
<queries><intent tools:node="removeAll"><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # P4 — a live <queries> NESTED INSIDE a removed one: the outer is stripped at merge,
  # taking the inner with it.
  cat > "$tmp/p4_nested_in_removed.xml" <<EOF
$MF
$PERMS_OK
<queries tools:node="remove"><queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></queries></manifest>
EOF
  # P9 — tools:node="replace" is NOT a removal. Must still ACCEPT (guards against
  # over-correcting R2 into a false FAIL).
  cat > "$tmp/p9_replace_not_removal.xml" <<EOF
$MF
$PERMS_OK
<queries><intent tools:node="replace"><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # --- DIA round-3 attacks: the PERMS lane carried the same half-closed seam. Every
  # one of these PASSED while shipping a manifest that is dead for HER. X2 is the
  # FOUNDING ANDON of this whole script — the dead location dot — walking straight
  # back in through a removal value the regex had never heard of. ---
  # X1 — INTERNET stripped by removeAll: dead network, guard said PASS.
  cat > "$tmp/x1_perm_removeall.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET" tools:node="removeAll"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  # X2 — ACCESS_FINE_LOCATION stripped by removeAll: HER LOCATION DOT IS DEAD.
  # This is the 2026-06-30 regression the loom was built to make impossible.
  cat > "$tmp/x2_location_removeall.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" tools:node="removeAll"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  # X3 — a perm misplaced inside <application> grants nothing.
  cat > "$tmp/x3_perm_in_application.xml" <<EOF
$MF
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<application><uses-permission android:name="android.permission.INTERNET"/></application>
$QUERIES_OK</manifest>
EOF
  # X5 — a perm misplaced inside <queries> grants nothing.
  cat > "$tmp/x5_perm_in_queries.xml" <<EOF
$MF
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<queries><uses-permission android:name="android.permission.INTERNET"/><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries></manifest>
EOF
  # X6 — perms lane must also honour non-removal 'replace' (no over-correction).
  cat > "$tmp/x6_perm_replace_ok.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET" tools:node="replace"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
$QUERIES_OK</manifest>
EOF
  pass=0; total=0
  check() { # name expected(0=accept,1=reject)
    total=$((total+1))
    local rc=0
    assert_manifest "$tmp/$1" >/dev/null 2>&1 || rc=1
    if [[ "$rc" == "$2" ]]; then echo "self-test $total PASS ($1 → $( [[ $2 == 0 ]] && echo accepted || echo rejected ))"; pass=$((pass+1)); else echo "self-test $total FAIL ($1 expected $( [[ $2 == 0 ]] && echo accept || echo reject ), got rc=$rc)"; fi
  }
  check good.xml 0
  check deleted.xml 1
  check commented.xml 1
  check removed.xml 1
  check removed_sq.xml 1
  check multiline.xml 0
  # voice-lane cases — all four PASSED the pre-BOD-19 guard while shipping a dead
  # ja voice channel. tts_outside_queries is the load-bearing one: the intent is
  # PRESENT in the file, so a naive grep would accept it, but outside <queries> it
  # grants no package visibility and speak() still fails silently.
  check tts_no_queries.xml 1
  check tts_commented.xml 1
  check tts_outside_queries.xml 1
  check tts_queries_removed.xml 1
  # DIA's attack suite — the regex version returned the WRONG verdict on 5 of these 6.
  check a1_greedy_trap.xml 1
  check a2_intent_removed.xml 1
  check a3_action_removed.xml 1
  check a6_unrelated_removed.xml 0
  check a5_two_blocks_ok.xml 0
  check a8_bare_action.xml 1
  # DIA round-2: each of these blessed a DEAD voice lane in the parser version.
  check p1_queries_in_application.xml 1
  check p2_removeall_queries.xml 1
  check p3_removeall_intent.xml 1
  check p4_nested_in_removed.xml 1
  check p9_replace_not_removal.xml 0
  # DIA round-3: the perms lane. X2 is the founding dead-dot Andon.
  check x1_perm_removeall.xml 1
  check x2_location_removeall.xml 1
  check x3_perm_in_application.xml 1
  check x5_perm_in_queries.xml 1
  check x6_perm_replace_ok.xml 0
  echo "SELF-TEST: $pass/$total PASS"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

assert_manifest "${1:-$SCRIPT_DIR/../android/app/src/main/AndroidManifest.xml}"
