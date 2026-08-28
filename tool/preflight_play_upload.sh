#!/usr/bin/env bash
# PLAY-UPLOAD PREFLIGHT LOOM (AAE, 2026-08-10)
#
# WHY THIS EXISTS (OPS-RULE-070(B): the reason is written before the act).
#
#   The Oct 31 in-hands date has one narrow, non-repeating window. Every Play
#   rejection costs a cycle out of it, and the four things Play rejects an upload
#   for are all knowable BEFORE the upload — locally, in seconds. Nothing in this
#   repo checked them:
#
#     - .github/workflows/ci.yml checks that the *APK* is not debug-signed. Play
#       does not take that APK: new apps must ship an ANDROID APP BUNDLE. So the
#       one artifact CI verifies is not the one that gets uploaded, and the one
#       that gets uploaded was verified by nobody.
#     - tool/assert_manifest_perms.sh reads the manifest we hand-author and says
#       so in its own header: "DOES NOT CATCH: the MERGED manifest (post-build)".
#       targetSdk is not in the hand-authored manifest at all — it arrives from
#       the Flutter Gradle plugin, i.e. from the toolchain, i.e. from something
#       that changes without anyone editing this repo.
#
#   So this gate reads the BUILT ARTIFACT, not our intentions about it.
#
# THE FIVE GATES, and why each is a real rejection and not hygiene.
# (Gate 5 added 2026-08-10 after a second AAE pass found the defect it catches
#  was ALREADY LIVE in this repo and had been for a month — see its own header.)
#
#   1. SIGNATURE — android/app/build.gradle.kts:65-69 falls back to DEBUG keys
#      when android/key.properties is absent. That fallback is a development
#      convenience and it is silent. A debug-signed bundle is rejected by Play,
#      and worse, an upload signed by the WRONG release key can never be undone:
#      the first artifact accepted on a track pins the upload identity forever.
#   2. targetSdk — from 2026-08-31 Play requires new apps and updates to target
#      API 36 (measured live 2026-08-10 at
#      support.google.com/googleplay/android-developer/answer/11926878). That is
#      21 days from the day this loom was written. A toolchain change that lowers
#      it would be found at the upload, in October.
#   3. 16 KB PAGE SIZE — required for apps targeting API 35+ on 64-bit devices;
#      enforced for updates from 2027-02-01 (developer.android.com/guide/
#      practices/page-sizes, read live 2026-08-10). We pass today only because
#      NDK r28 aligns by default. A pinned-back NDK silently loses it.
#   4. versionCode — Play refuses a versionCode already used on the track. The
#      discipline is written in pubspec.yaml ("versionCode must never repeat")
#      and, being written, is exactly the kind of thing that does not fire.
#   5. PERMISSION PARITY — what we DECLARE to Google (privacy policy + Data
#      safety) against what the artifact actually REQUESTS. A declaration that
#      contradicts the app is a policy violation, and ours already did: the
#      published policy listed four permissions while the app shipped five,
#      because a plugin injects VIBRATE at manifest-merge time where no human
#      reads it. Rejection here is a suspension risk, not a bounced upload.
#
# HONEST BOUNDS (OPS-RULE-066(A); AAE-1 — reach is verified on the device, and
# this is NOT that):
#   - This gate proves the ARTIFACT IS ACCEPTABLE TO UPLOAD. It proves nothing
#     about whether the app works, renders, speaks, or helps anyone. A bundle can
#     pass all five gates and be dead on HER phone.
#   - targetSdk/minSdk are read from the release APK built from the same tree in
#     the same run, because no bundletool is present in this environment to read
#     the bundle's own protobuf manifest. If you build the AAB and the APK from
#     DIFFERENT trees, this check is meaningless. The script builds both itself
#     to close that gap; --skip-build trusts you and says so.
#   - The predicate logic is proven by --self-test (it must REJECT bad input).
#     The extraction logic is proven only by running against a real artifact.
#     Those are different proofs and this script does not conflate them.
#     For gate 5 BOTH proofs were taken on 2026-08-10: the predicates by
#     --self-test, and the extraction end-to-end by deleting VIBRATE from the
#     authored manifest and confirming this gate FAILED against the real bundle,
#     naming VIBRATE, before the manifest was restored byte-identical.
#   - Gate 5 compares the manifest as it is NOW against the artifact as it was
#     BUILT. Under --skip-build those can be different trees, and then the gate
#     describes neither honestly. The default path (build both here) closes it.
#
# USAGE
#   tool/preflight_play_upload.sh              # build both, then gate
#   tool/preflight_play_upload.sh --skip-build # gate whatever is already built
#   tool/preflight_play_upload.sh --self-test  # prove the guards fail
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AAB="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
APK="$REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk"
LEDGER="$REPO_ROOT/tool/play_uploaded_version_codes.txt"

# The upload identity, pinned. Read from the keystore 2026-08-10:
#   keytool -list -v -keystore android/app/upload-keystore.jks -alias upload
EXPECTED_SIGNER_CN="CN=SNGNav Upload"
MIN_TARGET_SDK=36
MIN_SO_ALIGN=16384   # 0x4000

# ---------------------------------------------------------------- predicates
# Pure decisions. Every one of these is exercised by --self-test with input it
# MUST reject, because a guard nobody has watched fail is not known to guard.

# $1 = signer Owner line as printed by keytool
check_signer() {
  case "$1" in
    *"CN=Android Debug"*) echo "DEBUG-SIGNED: $1"; return 1 ;;
  esac
  case "$1" in
    *"$EXPECTED_SIGNER_CN"*) return 0 ;;
    *) echo "WRONG SIGNER: expected '$EXPECTED_SIGNER_CN', got: $1"; return 1 ;;
  esac
}

# $1 = targetSdk as integer
check_target_sdk() {
  [ -n "$1" ] || { echo "targetSdk not readable"; return 1; }
  if [ "$1" -lt "$MIN_TARGET_SDK" ]; then
    echo "targetSdk $1 < $MIN_TARGET_SDK (Play requires API $MIN_TARGET_SDK from 2026-08-31)"
    return 1
  fi
  return 0
}

# $1 = ELF LOAD alignment (may be hex 0x... or decimal); $2 = lib path (label)
check_so_align() {
  local a="$1"
  [ -n "$a" ] || { echo "no LOAD alignment read for $2"; return 1; }
  local dec=$(( a ))          # bash parses 0x... natively
  if [ "$dec" -lt "$MIN_SO_ALIGN" ]; then
    echo "$2: LOAD align $a ($dec) < $MIN_SO_ALIGN — not 16 KB page-size safe"
    return 1
  fi
  return 0
}

# $1 = readelf -lW output. Echoes the NUMERIC minimum LOAD alignment.
#
# EXTRACTION DEFECT, found + fixed 2026-08-24 (AAE). This was inline in gate 3 as
#   awk '/LOAD/{print $NF}' | sort -u | head -1
# which sorts the hex STRINGS lexically. "0x10000" sorts BEFORE "0x2000", so a .so
# carrying an 8 KB segment beside a 64 KB one reported 0x10000 and PASSED — the gate
# reported the LARGEST alignment while claiming the smallest. It never fired because
# every .so in today's bundle has one uniform alignment (measured: 12/12 have exactly
# 1 distinct LOAD align), so the defect was latent, not live. It is pulled out of the
# gate and into a function precisely so --self-test can drive the SHIPPED code path
# rather than a copy of it — the script's own HONEST BOUNDS note that the predicates
# were proven and the extraction was not. This closes half of that gap.
min_load_align() {
  printf '%s\n' "$1" | awk '/LOAD/{print $NF}' \
    | while read -r a; do case "$a" in 0x*|[0-9]*) printf '%d\n' "$((a))" ;; esac; done \
    | sort -n | head -1
}

# $1 = candidate versionCode; $2 = newline-separated already-uploaded codes
check_version_code() {
  local vc="$1" used="$2"
  [ -n "$vc" ] || { echo "versionCode not readable"; return 1; }
  if printf '%s\n' "$used" | grep -qx "$vc"; then
    echo "versionCode $vc HAS ALREADY BEEN UPLOADED — Play will refuse it. Bump pubspec.yaml (+N)."
    return 1
  fi
  return 0
}

# $1 = permissions DECLARED in the manifest we author (newline-separated)
# $2 = permissions actually SHIPPED in the built artifact (newline-separated)
#
# GATE 5 — why this exists, and it is not hygiene (AAE, 2026-08-10).
#
#   The privacy policy published at
#   raw.githubusercontent.com/aki1770-del/sngnav-app/main/docs/store/privacy_policy_ja.md
#   listed FOUR permissions and said "no other permissions are requested". The
#   shipped app requests FIVE: the `vibration` plugin injects VIBRATE at
#   manifest-MERGE time, so it never appeared in the file a human reads. The page
#   was false for a month, in our favour, which is the worst direction — and a
#   Data safety declaration that contradicts the app is a Play POLICY VIOLATION,
#   not a typo. It would have contradicted it on day one of the beta.
#
#   Nothing in this repo could have caught that: tool/assert_manifest_perms.sh
#   reads the manifest we author and says so in its own header ("DOES NOT CATCH:
#   the MERGED manifest"). So the two documents that must agree — what we declare
#   to Google, and what the APK requests — were compared by nobody.
#
#   This gate compares them mechanically. It fails in BOTH directions, because
#   both are false statements about our own app:
#     - SHIPPED-but-undeclared: an undisclosed permission. The dangerous one; it
#       is exactly the defect above and it recurs every time a plugin is added.
#     - DECLARED-but-unshipped: we claim a capability we do not have, or the
#       merger stripped something we believe we ship (the founding dead-dot
#       Andon's shape).
#
#   Self-defined permissions are excluded by the caller: AndroidX synthesises
#   "<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION", which is a
#   signature-level permission the OS never shows a user and no privacy policy
#   should list.
check_perm_parity() {
  local declared="$1" shipped="$2" only_shipped only_declared rc=0
  [ -n "$declared" ] || { echo "no DECLARED permissions read — cannot compare. UNVERIFIED, not clear."; return 1; }
  [ -n "$shipped"  ] || { echo "no SHIPPED permissions read — cannot compare. UNVERIFIED, not clear."; return 1; }
  only_shipped="$(comm -13 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$shipped" | sort -u))"
  only_declared="$(comm -23 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$shipped" | sort -u))"
  if [ -n "$only_shipped" ]; then
    echo "SHIPPED BUT NOT DECLARED (undisclosed to the store + the privacy page):"
    printf '    %s\n' $only_shipped
    rc=1
  fi
  if [ -n "$only_declared" ]; then
    echo "DECLARED BUT NOT SHIPPED (we claim what the artifact does not request):"
    printf '    %s\n' $only_declared
    rc=1
  fi
  [ "$rc" -eq 0 ] || echo "  → docs/store/privacy_policy_ja.md and docs/store/data_safety_declaration.md are now WRONG. Fix them WITH this change, not after the upload."
  return $rc
}

# ---------------------------------------------------------------- self-test
if [ "${1:-}" = "--self-test" ]; then
  pass=0; total=0
  t() { # t <label> <expected-rc> <cmd...>
    local label="$1" want="$2"; shift 2
    total=$((total+1))
    "$@" >/dev/null 2>&1; local rc=$?
    if [ "$rc" -eq "$want" ]; then
      echo "self-test $total PASS  $label"
      pass=$((pass+1))
    else
      echo "self-test $total FAIL  $label (wanted rc=$want, got rc=$rc)"
    fi
  }

  # Each guard must REJECT the thing it exists to catch...
  t "debug signature rejected"        1 check_signer "Owner: CN=Android Debug, OU=Android, O=Android, C=US"
  t "foreign release signer rejected" 1 check_signer "Owner: CN=Someone Else, O=Other"
  t "empty signer rejected"           1 check_signer ""
  t "targetSdk 35 rejected"           1 check_target_sdk 35
  t "targetSdk 34 rejected"           1 check_target_sdk 34
  t "unreadable targetSdk rejected"   1 check_target_sdk ""
  t "4 KB align rejected"             1 check_so_align 0x1000 libfake.so
  t "8 KB align rejected"             1 check_so_align 0x2000 libfake.so
  t "unreadable align rejected"       1 check_so_align "" libfake.so
  t "reused versionCode rejected"     1 check_version_code 2 "$(printf '1\n2\n3')"
  t "unreadable versionCode rejected" 1 check_version_code "" "1"

  # Gate 5. The FIRST case is the real 2026-08-10 defect, reproduced exactly: the
  # manifest we author declares four, the artifact ships five, and the extra one is
  # VIBRATE arriving from a plugin at merge time. This is the input that was live in
  # this repo, that no gate looked at, and that made the published privacy policy
  # false. A guard nobody has watched fail is not known to guard.
  PERM4="$(printf 'android.permission.ACCESS_COARSE_LOCATION\nandroid.permission.ACCESS_FINE_LOCATION\nandroid.permission.INTERNET\nandroid.permission.WAKE_LOCK')"
  PERM5="$(printf '%s\nandroid.permission.VIBRATE' "$PERM4")"
  t "the real VIBRATE drift rejected"   1 check_perm_parity "$PERM4" "$PERM5"
  t "declared-but-unshipped rejected"   1 check_perm_parity "$PERM5" "$PERM4"
  t "unreadable declared rejected"      1 check_perm_parity "" "$PERM5"
  t "unreadable shipped rejected"       1 check_perm_parity "$PERM5" ""
  t "identical sets accepted"           0 check_perm_parity "$PERM5" "$PERM5"
  t "parity accepted out of order"      0 check_perm_parity "$PERM5" "$(printf '%s\n' "$PERM5" | sort -r)"

  # EXTRACTION tests (2026-08-24). The predicates were always proven; the
  # extraction was not, and that is exactly where the defect lived. Input is real
  # `readelf -lW` output shape with the alignment column last.
  RE_MIXED="$(printf '  LOAD           0x000000 0x00000000 0x00000000 0x001000 0x001000 R E 0x10000\n  LOAD           0x002000 0x00002000 0x00002000 0x000100 0x000100 RW  0x2000\n')"
  RE_UNIFORM="$(printf '  LOAD           0x000000 0x00000000 0x00000000 0x001000 0x001000 R E 0x4000\n  LOAD           0x002000 0x00002000 0x00002000 0x000100 0x000100 RW  0x4000\n')"
  t "8 KB masked by 64 KB is FOUND"   0 test "$(min_load_align "$RE_MIXED")" = "8192"
  t "8 KB masked by 64 KB is REJECTED" 1 check_so_align "$(min_load_align "$RE_MIXED")" libmixed.so
  t "uniform 16 KB extracted"          0 test "$(min_load_align "$RE_UNIFORM")" = "16384"
  t "uniform 16 KB accepted"           0 check_so_align "$(min_load_align "$RE_UNIFORM")" libuniform.so
  t "no LOAD lines -> unreadable"      1 check_so_align "$(min_load_align "nothing here")" libempty.so

  # ...and ACCEPT the real, correct values measured on 2026-08-10, so a guard
  # that rejects everything (equally useless) is caught too.
  t "expected signer accepted"        0 check_signer "Owner: CN=SNGNav Upload, OU=SNGNav, O=SNGNav, L=Nagoya, ST=Aichi, C=JP"
  t "targetSdk 36 accepted"           0 check_target_sdk 36
  t "targetSdk 37 accepted"           0 check_target_sdk 37
  t "16 KB align accepted"            0 check_so_align 0x4000 libdartjni.so
  t "64 KB align accepted"            0 check_so_align 0x10000 libflutter.so
  t "fresh versionCode accepted"      0 check_version_code 4 "$(printf '1\n2\n3')"

  echo "SELF-TEST: $pass/$total PASS"
  [ "$pass" -eq "$total" ] || exit 1
  exit 0
fi

# ---------------------------------------------------------------- live run
SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

echo "== Play upload preflight =="
echo "repo:   $REPO_ROOT"
echo "commit: $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '(not a git tree)')"
if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
  echo "NOTE:   working tree is DIRTY — the artifact does not correspond to any commit."
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "-- building bundle + apk from THIS tree (both, so the APK-read fields describe the AAB)"
  ( cd "$REPO_ROOT" && flutter build appbundle --release ) || { echo "FAIL: appbundle build"; exit 1; }
  ( cd "$REPO_ROOT" && flutter build apk --release )       || { echo "FAIL: apk build"; exit 1; }
else
  echo "-- --skip-build: gating pre-existing artifacts. If the AAB and APK came from"
  echo "   different trees, gate 2 says nothing about the AAB. You were told."
fi

[ -f "$AAB" ] || { echo "FAIL: no bundle at $AAB"; exit 1; }
[ -f "$APK" ] || { echo "FAIL: no apk at $APK"; exit 1; }

fails=0
note() { echo "  $1"; }

# --- gate 1: the BUNDLE's own signature (this is the uploaded artifact)
echo "-- gate 1/5  signature of the BUNDLE"
signer_line="$(keytool -printcert -jarfile "$AAB" 2>/dev/null | grep -m1 '^Owner:')"
if check_signer "$signer_line"; then
  note "OK  $signer_line"
  note "    $(keytool -printcert -jarfile "$AAB" 2>/dev/null | grep -m1 '^Valid from:')"
else
  fails=$((fails+1))
fi

# --- gate 2: targetSdk / minSdk (read from the APK; see HONEST BOUNDS)
echo "-- gate 2/5  targetSdk"
AAPT2="$(ls "${ANDROID_HOME:-$HOME/android-sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
if [ -z "$AAPT2" ]; then
  note "FAIL: no aapt2 found — cannot read targetSdk. UNVERIFIED, not clear."
  fails=$((fails+1))
else
  badging="$("$AAPT2" dump badging "$APK" 2>/dev/null)"
  tsdk="$(printf '%s\n' "$badging" | sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p")"
  msdk="$(printf '%s\n' "$badging" | sed -n "s/^minSdkVersion:'\([0-9]*\)'.*/\1/p")"
  if check_target_sdk "$tsdk"; then note "OK  targetSdk=$tsdk  minSdk=$msdk"; else fails=$((fails+1)); fi
fi

# --- gate 3: 16 KB page-size alignment of every 64-bit .so IN THE BUNDLE
echo "-- gate 3/5  16 KB alignment (64-bit ABIs)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if unzip -q -o "$AAB" 'base/lib/*/*.so' -d "$tmp" 2>/dev/null; then
  checked=0
  for so in "$tmp"/base/lib/*/*.so; do
    [ -e "$so" ] || continue
    abi="$(basename "$(dirname "$so")")"
    case "$abi" in armeabi-v7a|x86) continue ;; esac   # 32-bit: requirement does not apply
    align="$(min_load_align "$(readelf -lW "$so" 2>/dev/null)")"
    checked=$((checked+1))
    if check_so_align "$align" "$abi/$(basename "$so")"; then
      note "OK  $abi/$(basename "$so")  align=$align"
    else
      fails=$((fails+1))
    fi
  done
  [ "$checked" -gt 0 ] || { note "FAIL: no 64-bit .so found to check — that is itself wrong"; fails=$((fails+1)); }
else
  note "FAIL: could not extract libs from the bundle"; fails=$((fails+1))
fi

# --- gate 4: versionCode not already spent
echo "-- gate 4/5  versionCode"
vc="$(printf '%s\n' "${badging:-}" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)"
used="$( [ -f "$LEDGER" ] && grep -E '^[0-9]+$' "$LEDGER" || true )"
if check_version_code "$vc" "$used"; then
  note "OK  versionCode=$vc not in $(basename "$LEDGER")"
  note "    AFTER a successful upload, append $vc to $LEDGER and commit it."
else
  fails=$((fails+1))
fi

# --- gate 5: what we DECLARE vs what the artifact SHIPS
echo "-- gate 5/5  permission parity (authored manifest vs built artifact)"
MANIFEST="$REPO_ROOT/android/app/src/main/AndroidManifest.xml"
PKG="$(printf '%s\n' "${badging:-}" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
# DECLARED: parsed as XML, not grepped — a commented-out <uses-permission> is not a
# declaration, and a regex cannot tell the difference. Same discipline (and the same
# reason) as tool/assert_manifest_perms.sh, which DIA falsified in its regex form.
declared_perms="$(python3 - "$MANIFEST" <<'PY' 2>/dev/null
import sys, xml.etree.ElementTree as ET
NS = '{http://schemas.android.com/apk/res/android}'
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(1)
# Only DIRECT children of <manifest> grant anything; one nested elsewhere is inert.
for e in root.findall('uses-permission'):
    n = e.get(NS + 'name')
    if n:
        print(n)
PY
)"
# SHIPPED: read from the built artifact, which is the thing Google receives.
shipped_perms="$(printf '%s\n' "${badging:-}" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p")"
# Drop the app's own synthesised signature permission (AndroidX
# DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION): never user-visible, never declarable.
if [ -n "$PKG" ]; then
  shipped_perms="$(printf '%s\n' "$shipped_perms" | grep -v "^${PKG}\." || true)"
fi
if [ -z "${badging:-}" ]; then
  note "FAIL: no badging (aapt2 missing above) — parity UNVERIFIED, not clear."
  fails=$((fails+1))
elif check_perm_parity "$declared_perms" "$shipped_perms"; then
  note "OK  $(printf '%s\n' "$shipped_perms" | grep -c .) permission(s) declared and shipped, identical sets:"
  printf '      %s\n' $(printf '%s\n' "$shipped_perms" | sort)
else
  fails=$((fails+1))
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "PREFLIGHT PASS — this is the file to upload:"
  echo "  $AAB"
  echo "  $(du -h "$AAB" | cut -f1)"
  echo
  echo "It is upload-acceptable. It is NOT verified to work on a phone (AAE-1)."
  exit 0
fi
echo "PREFLIGHT FAIL — $fails gate(s) failed. Do not upload."
exit 1
