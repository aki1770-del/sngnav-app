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
# PERM SCOPE (DIA-certified SOUND PARTIAL, 2026-07-01): a deterministic check on
# the SOURCE main manifest (android/app/src/main). It DOES catch: a deleted perm, a
# COMMENTED-OUT perm, a perm neutralised by tools:node="remove", and multi-line /
# extra-whitespace element formatting. It does NOT verify the MERGED manifest
# (post-build), the debug/profile manifest variants, or runtime behaviour — those
# are on-device concerns (docs/DEVICE_VERIFICATION.md, OPS-066). See tripwire S2.
#
# VOICE-LANE SCOPE (added 2026-07-11, BOD-19 — AAE Andon; the 2026-07-01 stamp
# above does NOT cover it, and extending a stale certification over uncertified
# code would itself be a false provenance claim — DIA finding):
#   CATCHES: the TTS_SERVICE intent absent, commented-out, declared outside
#   <queries>, wrongly nested, or neutralised by tools:node="remove" on the
#   <queries> / <intent> / <action>. Containment is checked by XML PARSE, not
#   regex — DIA REFUSED a regex version that blessed a dead voice lane (greedy
#   span across two <queries> blocks).
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
  # Preprocess: strip XML comments (so a commented-out perm is NOT counted as
  # present) and flatten all whitespace to single spaces (so multi-line or
  # extra-spaced elements still match). python3 is present in CI + locally.
  local cleaned
  cleaned="$(python3 -c "import re,sys; s=open(sys.argv[1],encoding='utf-8').read(); s=re.sub(r'<!--.*?-->','',s,flags=re.S); s=re.sub(r'\s+',' ',s); sys.stdout.write(s)" "$manifest")"

  local missing=()
  local perm esc elems
  for perm in "${REQUIRED_PERMS[@]}"; do
    esc="${perm//./\\.}"
    # every <uses-permission …android:name="<perm>"…> element (attr order free)
    elems="$(printf '%s' "$cleaned" | grep -oE "<uses-permission[^>]*android:name *= *[\"']${esc}[\"'][^>]*>" || true)"
    if [[ -z "$elems" ]]; then
      missing+=("$perm (absent / commented-out)")
    elif printf '%s' "$elems" | grep -qE "tools:node *= *[\"']remove[\"']"; then
      missing+=("$perm (tools:node=\"remove\" — stripped from the merged manifest)")
    fi
  done

  # --- VOICE-LANE assert: the TTS_SERVICE intent must live INSIDE <queries> ---
  #
  # Parsed as XML, NOT grepped. DIA REFUSED certification of a regex version
  # (2026-07-11): `<queries[^>]*>.*</queries>` is GREEDY, and since we flatten the
  # file to one line it spanned from the FIRST `<queries` to the LAST `</queries>`,
  # swallowing everything between — so an action declared OUTSIDE <queries>, but
  # positioned between two blocks, was blessed as inside. A second <queries> block
  # is a realistic near-term event (url_launcher's README instructs adding one).
  # Regex cannot express containment. The parser can.
  #
  # Required shape (Android package visibility): queries > intent > action[name],
  # with tools:node="remove" on NONE of the three (a removed node is stripped from
  # the merged manifest, so it grants nothing). A bare <action> without its <intent>
  # wrapper does not grant visibility either, and is rejected.
  local intent
  for intent in "${REQUIRED_QUERY_INTENTS[@]}"; do
    local why
    why="$(python3 - "$manifest" "$intent" <<'PY'
import sys, xml.etree.ElementTree as ET
A = '{http://schemas.android.com/apk/res/android}name'
T = '{http://schemas.android.com/tools}node'
path, want = sys.argv[1], sys.argv[2]
try:
    root = ET.parse(path).getroot()   # ElementTree drops XML comments for us
except ET.ParseError as e:
    print(f'manifest is not parseable XML ({e})'); sys.exit(0)

def kept(el):
    return (el.get(T) or '').strip().lower() != 'remove'

blocks = [q for q in root.iter('queries')]
if not blocks:
    print('no <queries> block — absent or commented-out'); sys.exit(0)
live = [q for q in blocks if kept(q)]
if not live:
    print('<queries> tools:node="remove" — stripped from the merged manifest'); sys.exit(0)

for q in live:                                  # containment is structural, per block
    for it in q.findall('intent'):
        if not kept(it):
            continue
        for ac in it.findall('action'):
            if kept(ac) and ac.get(A) == want:
                sys.exit(0)                     # found, live, correctly nested -> silent = OK

# Not found. Say WHY precisely — the loom's third property.
for el in root.iter('action'):
    if el.get(A) == want:
        print('declared, but NOT inside a live <queries><intent> — grants no package '
              'visibility (removed node, wrong nesting, or outside <queries>)')
        sys.exit(0)
print('not declared inside <queries> — TTS speak() will fail SILENTLY')
PY
)"
    if [[ -n "$why" ]]; then
      missing+=("$intent ($why)")
    fi
  done

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
  echo "SELF-TEST: $pass/$total PASS"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

assert_manifest "${1:-$SCRIPT_DIR/../android/app/src/main/AndroidManifest.xml}"
