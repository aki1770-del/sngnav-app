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
# SCOPE (DIA-certified SOUND PARTIAL, 2026-07-01): a deterministic check on the
# SOURCE main manifest (android/app/src/main). It DOES catch: a deleted perm, a
# COMMENTED-OUT perm, a perm neutralised by tools:node="remove", and multi-line /
# extra-whitespace element formatting. It does NOT verify the MERGED manifest
# (post-build), the debug/profile manifest variants, or runtime behaviour — those
# are on-device concerns (docs/DEVICE_VERIFICATION.md, OPS-066). See tripwire S2.
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

  if (( ${#missing[@]} > 0 )); then
    echo "FAIL: AndroidManifest is MISSING required permission(s) — a release build would be DEAD for HER (WS1 blocker class):" >&2
    for m in "${missing[@]}"; do echo "  - $m" >&2; done
    echo "Manifest: $manifest" >&2
    return 1
  fi
  echo "PASS: all ${#REQUIRED_PERMS[@]} WS1-blocker permissions effectively declared in $manifest"
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/good.xml" <<'EOF'
<manifest xmlns:tools="http://schemas.android.com/tools">
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/></manifest>
EOF
  cat > "$tmp/deleted.xml" <<'EOF'
<manifest><uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/></manifest>
EOF
  cat > "$tmp/commented.xml" <<'EOF'
<manifest><!-- <uses-permission android:name="android.permission.INTERNET"/> -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/></manifest>
EOF
  cat > "$tmp/removed.xml" <<'EOF'
<manifest xmlns:tools="http://schemas.android.com/tools">
<uses-permission android:name="android.permission.INTERNET" tools:node="remove"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/></manifest>
EOF
  cat > "$tmp/removed_sq.xml" <<'EOF'
<manifest xmlns:tools="http://schemas.android.com/tools">
<uses-permission android:name='android.permission.INTERNET' tools:node='remove'/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/></manifest>
EOF
  cat > "$tmp/multiline.xml" <<'EOF'
<manifest>
<uses-permission
    android:name = "android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/></manifest>
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
  echo "SELF-TEST: $pass/$total PASS"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

assert_manifest "${1:-$SCRIPT_DIR/../android/app/src/main/AndroidManifest.xml}"
