#!/usr/bin/env bash
# PLAY-UPLOAD PREFLIGHT LOOM (2026-08-10)
#
# WHY THIS EXISTS (the reason is written before the act).
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
# (Gate 5 added 2026-08-10 after a second pass found the defect it catches
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
# HONEST BOUNDS (reach is verified on the device, and
# this is NOT that):
#   - This gate proves the ARTIFACT IS ACCEPTABLE TO UPLOAD. It proves nothing
#     about whether the app works, renders, speaks, or helps anyone. A bundle can
#     pass all five gates and be dead on the driver's phone.
#   - targetSdk/minSdk (gate 2) and the shipped permissions (gate 5) are read
#     from the release APK built from the same tree in the same run. The
#     versionCode (gate 4) is read from the BUNDLE's own manifest, through aapt2
#     (see bundle_badging). Before any gate runs, the bundle's versionCode and
#     versionName are compared with the APK's, and if they differ the run FAILS
#     and gates 2 and 5 say UNVERIFIED: the APK is then another build. That
#     comparison cannot see two trees that stamp the same version, so the
#     script still builds both itself; --skip-build trusts you that far and no
#     further. Gates 2 and 5 could read the bundle the same way; they do not yet.
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
# ⚑ ARGUMENT DEFECT — FOUND 2026-09-16, REPAIRED 2026-09-18.
#
#   Until 2026-09-18 this line read
#       AAB="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
#   with no way to override it, and the script accepted only --self-test and
#   --skip-build. Handed the held release bundle as an argument:
#       tool/preflight_play_upload.sh $HOME/work/r67-.../sngnav-app-...aab
#   it IGNORED THE ARGUMENT IN SILENCE, read a stale DEBUG-SIGNED bundle sitting
#   in the build directory under the same name, and returned
#       PREFLIGHT FAIL — DEBUG-SIGNED: Owner: C=US, O=Android, CN=Android Debug
#   about a file nobody had asked it about. The bundle that was actually passed
#   carried CN=SNGNav Upload and was fine.
#
#   The verdict was maximally loud and about the wrong file. That is worse than
#   silence: a gate that names the wrong artifact teaches its reader to distrust
#   the right answer next time. And the failure is symmetric — the same script
#   would have returned PASS about a stale bundle while a broken one waited
#   upstairs. A gate is only as good as its certainty about WHICH FILE it read.
#
#   Repair: --aab/--apk take explicit paths, a bare path argument is accepted as
#   the AAB, an UNRECOGNISED argument is a hard error instead of being dropped,
#   and the resolved absolute path + sha256 of both artifacts is PRINTED BEFORE
#   THE FIRST GATE RUNS. You can now always see what it read.
#   Recorded outside this repository on 2026-09-16.
#
# ⚑ GATE 4 READ THE APK — FOUND AND REPAIRED 2026-10-02.
#
#   Gate 4 took versionCode from the APK's badging and treated it as the
#   bundle's. Given a July upload-signed bundle at versionCode 2 and an APK
#   built that morning at 12, it printed
#       OK  versionCode=12 not in play_uploaded_version_codes.txt
#       PREFLIGHT PASS — this is the file to upload: .../app-release.aab
#   about the code-2 bundle. Play would have received 2, the ledger would have
#   been told 12, and the gate was green. Gate 5 passed the same pair on the
#   APK's eight permissions; the bundle requests five of them.
#
#   Repair: aapt2 reads the bundle's own manifest (base/manifest/
#   AndroidManifest.xml, a protobuf, with base/resources.pb) as a proto-format
#   APK. Gate 4 checks the bundle's versionCode. The bundle's versionCode and
#   versionName are compared with the APK's before any gate uses the APK, and a
#   difference FAILS the run. --self-test drives the predicate with that pair.
#
# ⚑ GATE 4 PASSED SPENT CODES — FOUND 2026-10-02, REPAIRED 2026-10-03.
#
#   Reading the bundle, gate 4 printed "OK versionCode=2" for the July bundle:
#   true, because Play has never seen code 2, and the wrong question, because
#   code 2 already named several release builds and the phone it was meant for
#   held code 12, so no update at 2 could ever reach it. The Play ledger
#   records Play uploads only, and it stays that way.
#
#   Repair: gate 4 also refuses a code at or below tool/version_code_floor (the
#   highest code spent under any signer), and a code below any code in this
#   host's mint ledger ($HOME/.sngnav/minted_release.tsv, written by the
#   release build itself). Each refusal names the channel that spent the code.
#
# USAGE
#   tool/preflight_play_upload.sh                     # build both here, then gate
#   tool/preflight_play_upload.sh --skip-build        # gate whatever is already built
#   tool/preflight_play_upload.sh <file.aab>          # gate THIS bundle (implies --skip-build)
#   tool/preflight_play_upload.sh --aab A --apk B     # gate these two explicitly
#   tool/preflight_play_upload.sh --self-test         # prove the guards fail
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AAB="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
APK="$REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk"
LEDGER="$REPO_ROOT/tool/play_uploaded_version_codes.txt"
# Codes spent under any signer (a floor), and this host's own mint record. Not
# the Play record: a code can be spent without ever reaching Play.
FLOOR_FILE="$REPO_ROOT/tool/version_code_floor"
MINT_LEDGER="${SNGNAV_MINTED_LEDGER:-$HOME/.sngnav/minted_release.tsv}"

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
# EXTRACTION DEFECT, found + fixed 2026-08-24. This was inline in gate 3 as
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

# $1 = the text of tool/version_code_floor. Echoes its number: the first line
# that is neither blank nor a comment, if it is an integer. Otherwise nothing.
floor_number() {
  printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v -e '^#' -e '^$' | head -1 | grep -E '^[0-9]+$' || true
}

# $1 = candidate versionCode; $2 = the floor; $3 = the floor file's notes on
# what its codes already name (may be empty). A code at or below the floor is
# SPENT, whether or not Play ever saw it.
check_version_code_floor() {
  local vc="$1" floor="$2" notes="$3"
  [ -n "$vc" ] || { echo "versionCode not readable"; return 1; }
  [ -n "$floor" ] || { echo "tool/version_code_floor is missing or holds no number: nothing says which codes are spent. UNVERIFIED, not clear."; return 1; }
  if [ "$vc" -le "$floor" ]; then
    echo "versionCode $vc IS SPENT (channel: tool/version_code_floor): every code up to $floor is already used."
    [ -z "$notes" ] || printf '%s\n' "$notes" | sed 's/^/    /'
    echo "    Play may never have seen it; it is spent all the same. Move pubspec.yaml above $floor."
    return 1
  fi
  return 0
}

# $1 = candidate versionCode; $2 = the text of the host mint ledger
# (code<TAB>kind<TAB>sha256<TAB>git<TAB>utc rows, # comments; may be empty).
# Refuses when this host minted a HIGHER code: this bundle is older than a
# release already made here. A row AT this code is not refused: it is usually
# this very bundle, recorded by the build that made it. A line that is not a
# row is a refusal, never skipped: skipping it could hide a spent code.
check_host_mint_ledger() {
  local vc="$1" ledger="$2" bad newer
  [ -n "$vc" ] || { echo "versionCode not readable"; return 1; }
  bad="$(printf '%s\n' "$ledger" | grep -v -e '^#' -e '^[[:space:]]*$' | grep -vE '^[0-9]+	[^	]+	[^	]+	[^	]+	[^	]+$' || true)"
  if [ -n "$bad" ]; then
    echo "host mint ledger has a line that is not a row — cannot say which codes it spends. UNVERIFIED, not clear:"
    printf '%s\n' "$bad" | head -3 | sed 's/^/    /'
    return 1
  fi
  newer="$(printf '%s\n' "$ledger" | grep -v '^#' | awk -F'\t' -v vc="$vc" '$1 ~ /^[0-9]+$/ && $1+0 > vc+0' | sort -t"$(printf '\t')" -k1,1nr)"
  if [ -n "$newer" ]; then
    echo "versionCode $vc IS BELOW A CODE THIS HOST HAS ALREADY MINTED (channel: host mint ledger):"
    printf '%s\n' "$newer" | tr '\t' ' ' | sed 's/^/    /'
    return 1
  fi
  return 0
}

# $1 = `aapt2 dump badging` output; $2 = versionCode or versionName.
# Echoes that field of the `package:` line, or nothing. The leading space keeps
# it off platformBuildVersionCode / platformBuildVersionName on the same line.
badging_field() {
  printf '%s\n' "$1" | sed -n "s/^package: .* $2='\([^']*\)'.*/\1/p" | head -1
}

# $1 = aapt2; $2 = the AAB; $3 = a scratch .zip path to write.
# Echoes the BUNDLE's own badging. A bundle keeps its manifest as a protobuf at
# base/manifest/AndroidManifest.xml, with its resource table at
# base/resources.pb; aapt2 reads that pair as a proto-format APK when they sit
# at the root of a ZIP. Nothing is written beside the bundle. Proven against a
# real bundle only (HONEST BOUNDS: extraction is not predicate logic).
bundle_badging() {
  local aapt2="$1" aab="$2" out="$3"
  python3 - "$aab" "$out" <<'PY' 2>/dev/null || return 1
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z, zipfile.ZipFile(dst, 'w') as o:
    o.writestr('AndroidManifest.xml', z.read('base/manifest/AndroidManifest.xml'))
    o.writestr('resources.pb', z.read('base/resources.pb'))
PY
  "$aapt2" dump badging "$out" 2>/dev/null
}

# $1/$2 = the bundle's versionCode/versionName; $3/$4 = the APK's.
# Gates 2 and 5 read the APK as the bundle's stand-in. That is true only when
# the two are the same build, and a different versionCode or versionName means
# they are not. An unreadable side is a refusal, never a match.
check_bundle_matches_apk() {
  local bc="$1" bn="$2" ac="$3" an="$4"
  if [ -z "$bc" ] || [ -z "$bn" ]; then
    echo "the BUNDLE's own versionCode/versionName could not be read. UNVERIFIED, not clear."
    return 1
  fi
  if [ -z "$ac" ] || [ -z "$an" ]; then
    echo "the APK's versionCode/versionName could not be read. UNVERIFIED, not clear."
    return 1
  fi
  if [ "$bc" != "$ac" ] || [ "$bn" != "$an" ]; then
    echo "DIFFERENT BUILDS: the bundle is versionCode=$bc versionName=$bn; the APK is versionCode=$ac versionName=$an."
    echo "    The APK is not this bundle's stand-in. What gates 2 and 5 would read from it is about another build."
    return 1
  fi
  return 0
}

# $1 = permissions DECLARED in the manifest we author (newline-separated)
# $2 = permissions actually SHIPPED in the built artifact (newline-separated)
#
# GATE 5 — why this exists, and it is not hygiene (2026-08-10).
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

# $1 = a single CLI token. Echoes its CLASS. "unknown" is a REFUSAL, never a skip.
#
# This function exists because the 2026-09-16 defect was not in a gate — it was in
# the argument handling, the one part of the script nothing exercised. An argument
# the script does not understand is now a class it must NAME, so the live path can
# refuse it instead of dropping it on the floor and gating something else.
classify_arg() {
  case "$1" in
    --self-test)  echo "self-test" ;;
    --skip-build) echo "skip-build" ;;
    --aab)        echo "aab-opt" ;;
    --apk)        echo "apk-opt" ;;
    -h|--help)    echo "help" ;;
    *.aab)        echo "aab-path" ;;
    *.apk)        echo "apk-path" ;;
    *)            echo "unknown" ;;
  esac
}

# $1 = path, $2 = label. Refuses anything that is not a readable, non-empty ZIP.
#
# An AAB and an APK are both ZIP containers ("PK" magic). A path that is not one
# was handed here by mistake, and gating a non-artifact as though it were an
# artifact is how a reassuring verdict gets attached to nothing.
check_artifact_readable() {
  local p="$1" label="$2" magic
  [ -n "$p" ]  || { echo "$label: no path given"; return 1; }
  [ -f "$p" ]  || { echo "$label: not a file: $p"; return 1; }
  [ -s "$p" ]  || { echo "$label: empty file: $p"; return 1; }
  magic="$(head -c2 "$p" 2>/dev/null | tr -d '\0')"
  [ "$magic" = "PK" ] || { echo "$label: not a ZIP container (magic '$magic'): $p"; return 1; }
  return 0
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

  # ARGUMENT-HANDLING tests (2026-09-18). The 2026-09-16 defect lived HERE and
  # nothing exercised it: the script gated a hard-coded path and dropped the
  # argument it was given, in silence. The specific token that was dropped is the
  # first case below.
  t "a bare .aab path is an ARTIFACT"    0 test "$(classify_arg "$HOME/work/r67-release-hold-4d591cf/sngnav-app-0.0.5+2-4d591cf-release.aab")" = "aab-path"
  t "a bare .apk path is an ARTIFACT"    0 test "$(classify_arg build/app/outputs/flutter-apk/app-release.apk)" = "apk-path"
  t "--aab is an option"                 0 test "$(classify_arg --aab)" = "aab-opt"
  t "--apk is an option"                 0 test "$(classify_arg --apk)" = "apk-opt"
  t "--skip-build still understood"      0 test "$(classify_arg --skip-build)" = "skip-build"
  t "--self-test still understood"       0 test "$(classify_arg --self-test)" = "self-test"
  t "a typo'd flag is UNKNOWN not dropped" 0 test "$(classify_arg --skipbuild)" = "unknown"
  t "a stray word is UNKNOWN not dropped"  0 test "$(classify_arg notes.txt)" = "unknown"

  # The artifact must be a real ZIP container before any gate speaks about it.
  NOT_A_ZIP="$(mktemp)"; printf 'this is not a bundle\n' > "$NOT_A_ZIP"
  EMPTY_FILE="$(mktemp)"
  REAL_ZIP="$(mktemp)"; printf 'PK\003\004rest-of-a-zip' > "$REAL_ZIP"
  t "a text file is not an artifact"   1 check_artifact_readable "$NOT_A_ZIP" AAB
  t "an empty file is not an artifact" 1 check_artifact_readable "$EMPTY_FILE" AAB
  t "a missing path is not an artifact" 1 check_artifact_readable /nonexistent/nope.aab AAB
  t "an unset path is not an artifact"  1 check_artifact_readable "" AAB
  t "a ZIP container is accepted"       0 check_artifact_readable "$REAL_ZIP" AAB

  # BUNDLE IDENTITY (2026-10-02). The first case is the real pair: a code-2
  # bundle beside a code-12 APK, which gate 4 passed by reading the APK.
  t "a code-2 bundle beside a code-12 APK rejected" 1 check_bundle_matches_apk 2 0.0.5 12 0.0.2
  t "same code, different name rejected"   1 check_bundle_matches_apk 12 0.0.2 12 0.0.3
  t "same name, different code rejected"   1 check_bundle_matches_apk 10 0.0.2 12 0.0.2
  t "unreadable bundle version rejected"   1 check_bundle_matches_apk "" "" 12 0.0.2
  t "unreadable APK version rejected"      1 check_bundle_matches_apk 12 0.0.2 "" ""
  t "the same build accepted"              0 check_bundle_matches_apk 12 0.0.2 12 0.0.2
  BADGING="package: name='dev.aki1770del.sngnav_app' versionCode='2' versionName='0.0.5' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'"
  t "versionCode read, not platformBuildVersionCode" 0 test "$(badging_field "$BADGING" versionCode)" = "2"
  t "versionName read, not platformBuildVersionName" 0 test "$(badging_field "$BADGING" versionName)" = "0.0.5"
  t "no package line, no versionCode"      0 test -z "$(badging_field "targetSdkVersion:'36'" versionCode)"
  NOT_A_BUNDLE_OUT="$(mktemp)"
  t "a ZIP that is not a bundle yields no manifest" 0 test -z "$(bundle_badging false "$REAL_ZIP" "$NOT_A_BUNDLE_OUT")"
  rm -f "$NOT_A_ZIP" "$EMPTY_FILE" "$REAL_ZIP" "$NOT_A_BUNDLE_OUT"

  # SPENT CODES (2026-10-03). The first case is the real one: the July bundle
  # at code 2, which gate 4 passed because Play had never seen code 2.
  t "a code-2 bundle is refused by the spent floor 12" 1 check_version_code_floor 2 12 ""
  t "the floor itself is spent"            1 check_version_code_floor 12 12 ""
  t "a code above the floor is accepted"   0 check_version_code_floor 13 12 ""
  t "no floor is a refusal, not a pass"    1 check_version_code_floor 13 "" ""
  t "an unreadable code is refused"        1 check_version_code_floor "" 12 ""
  FLOOR_TEXT="$(printf '# a note\n# 12: bytes it names\n\n  12  \n')"
  t "the floor number is read past comments" 0 test "$(floor_number "$FLOOR_TEXT")" = "12"
  t "a floor that is not a number reads as none" 0 test -z "$(floor_number "$(printf '# a note\ntwelve\n')")"
  t "an empty floor file reads as none"    0 test -z "$(floor_number "")"
  t "the tracked floor file holds a number" 0 test -n "$(floor_number "$(cat "$FLOOR_FILE" 2>/dev/null)")"
  ROW14="$(printf '14\taab\t0f00\tabc1234\t2026-10-03T00:00:00Z')"
  ROW13="$(printf '13\taab\t0f13\tabc1234\t2026-10-03T00:00:00Z')"
  t "a bundle below a code this host minted is refused" 1 check_host_mint_ledger 13 "$(printf '# header\n%s\n' "$ROW14")"
  t "a row at the same code (this bundle) is not a refusal" 0 check_host_mint_ledger 13 "$ROW13"
  t "an empty host ledger refuses nothing"  0 check_host_mint_ledger 13 ""
  t "a host ledger line that is not a row is a refusal" 1 check_host_mint_ledger 13 "$(printf '%s\n14 aab spaces-not-tabs' "$ROW13")"

  echo "SELF-TEST: $pass/$total PASS"
  [ "$pass" -eq "$total" ] || exit 1
  exit 0
fi

# ---------------------------------------------------------------- live run
usage() { sed -n '/^# USAGE/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SKIP_BUILD=0
GIVEN_AAB=0
GIVEN_APK=0
while [ $# -gt 0 ]; do
  case "$(classify_arg "$1")" in
    skip-build) SKIP_BUILD=1; shift ;;
    help)       usage; exit 0 ;;
    aab-opt)    shift
                [ $# -gt 0 ] || { echo "FAIL: --aab needs a path"; exit 2; }
                AAB="$1"; GIVEN_AAB=1; SKIP_BUILD=1; shift ;;
    apk-opt)    shift
                [ $# -gt 0 ] || { echo "FAIL: --apk needs a path"; exit 2; }
                APK="$1"; GIVEN_APK=1; SKIP_BUILD=1; shift ;;
    aab-path)   AAB="$1"; GIVEN_AAB=1; SKIP_BUILD=1; shift ;;
    apk-path)   APK="$1"; GIVEN_APK=1; SKIP_BUILD=1; shift ;;
    unknown|*)  echo "FAIL: unrecognised argument '$1' — REFUSING TO RUN."
                echo "  Until 2026-09-18 this script DROPPED arguments it did not"
                echo "  understand and gated a hard-coded path instead, then reported"
                echo "  the verdict as though it were about your file. It will not"
                echo "  do that again. Say what you mean:"
                echo
                usage
                exit 2 ;;
  esac
done

echo "== Play upload preflight =="
echo "repo:   $REPO_ROOT"
echo "commit: $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '(not a git tree)')"
if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
  echo "NOTE:   working tree is DIRTY — the artifact does not correspond to any commit."
fi
if [ "$GIVEN_AAB" -eq 1 ] && [ "$GIVEN_APK" -eq 0 ]; then
  echo "NOTE:   a bundle was given and no APK. Gates 2 and 5 read the APK (see"
  echo "        HONEST BOUNDS) and will report UNVERIFIED rather than pass."
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "-- building bundle + apk from THIS tree (both, so the APK-read fields describe the AAB)"
  ( cd "$REPO_ROOT" && flutter build appbundle --release ) || { echo "FAIL: appbundle build"; exit 1; }
  ( cd "$REPO_ROOT" && flutter build apk --release )       || { echo "FAIL: apk build"; exit 1; }
else
  echo "-- --skip-build: gating pre-existing artifacts. If the AAB and APK came from"
  echo "   different trees, gates 2 and 5 say nothing about the AAB. A different"
  echo "   versionCode or versionName FAILS below; the same version from two trees"
  echo "   cannot be seen. You were told."
fi

# WHICH FILE AM I READING. Printed BEFORE the first gate, always, resolved to an
# absolute path and fingerprinted. The 2026-09-16 defect was invisible precisely
# because this block did not exist: the verdict named a gate, never a file, so a
# loud FAIL about a stale artifact was indistinguishable from a true one.
[ -f "$AAB" ] || { echo "FAIL: no bundle at $AAB"; exit 1; }
check_artifact_readable "$AAB" "AAB" || exit 1
AAB="$(cd "$(dirname "$AAB")" && pwd)/$(basename "$AAB")"
HAVE_APK=0
if [ -f "$APK" ] && check_artifact_readable "$APK" "APK"; then
  APK="$(cd "$(dirname "$APK")" && pwd)/$(basename "$APK")"
  HAVE_APK=1
fi
echo "-- artifacts under test (this is the file this run is about)"
echo "   AAB: $AAB"
echo "        $(stat -c%s "$AAB") bytes  sha256=$(sha256sum "$AAB" | cut -c1-64)"
if [ "$HAVE_APK" -eq 1 ]; then
  echo "   APK: $APK"
  echo "        $(stat -c%s "$APK") bytes  sha256=$(sha256sum "$APK" | cut -c1-64)"
else
  echo "   APK: ABSENT ($APK) — gates 2 and 5 are UNVERIFIED, not clear."
fi

fails=0
note() { echo "  $1"; }
AAPT2="$(ls "${ANDROID_HOME:-$HOME/android-sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- identity: which build IS the bundle, and is the APK the same build?
# Gates 2 and 5 read the APK as the bundle's stand-in, so this is settled
# BEFORE any gate uses it. Until 2026-10-02 nothing compared them, and gate 4
# read its versionCode from the APK as well (see the header).
echo "-- identity  the BUNDLE's own manifest, and the APK beside it"
aab_badging=""; badging=""; APK_IS_BUNDLE=0
if [ -z "$AAPT2" ]; then
  note "no aapt2 found — neither manifest can be read; gates 2, 4 and 5 will say so."
else
  aab_badging="$(bundle_badging "$AAPT2" "$AAB" "$tmp/bundle_manifest.zip")"
  aab_vc="$(badging_field "$aab_badging" versionCode)"
  aab_vn="$(badging_field "$aab_badging" versionName)"
  note "AAB  versionCode=${aab_vc:-UNREADABLE}  versionName=${aab_vn:-UNREADABLE}  (the bundle's own manifest)"
  if [ "$HAVE_APK" -eq 1 ]; then
    badging="$("$AAPT2" dump badging "$APK" 2>/dev/null)"
    apk_vc="$(badging_field "$badging" versionCode)"
    apk_vn="$(badging_field "$badging" versionName)"
    note "APK  versionCode=${apk_vc:-UNREADABLE}  versionName=${apk_vn:-UNREADABLE}"
    if check_bundle_matches_apk "$aab_vc" "$aab_vn" "$apk_vc" "$apk_vn"; then
      APK_IS_BUNDLE=1
      note "OK  same versionCode and versionName: the APK may stand in for the bundle"
    else
      fails=$((fails+1))
    fi
  else
    note "APK  ABSENT"
  fi
fi

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
if [ "$HAVE_APK" -eq 0 ]; then
  note "FAIL: no APK beside this bundle — targetSdk UNVERIFIED, not clear."
  fails=$((fails+1))
elif [ -z "$AAPT2" ]; then
  note "FAIL: no aapt2 found — cannot read targetSdk. UNVERIFIED, not clear."
  fails=$((fails+1))
elif [ "$APK_IS_BUNDLE" -eq 0 ]; then
  note "FAIL: the APK is not the bundle's build (identity, above) — its targetSdk says nothing about the bundle. UNVERIFIED, not clear."
  fails=$((fails+1))
else
  tsdk="$(printf '%s\n' "$badging" | sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p")"
  msdk="$(printf '%s\n' "$badging" | sed -n "s/^minSdkVersion:'\([0-9]*\)'.*/\1/p")"
  if check_target_sdk "$tsdk"; then note "OK  targetSdk=$tsdk  minSdk=$msdk"; else fails=$((fails+1)); fi
fi

# --- gate 3: 16 KB page-size alignment of every 64-bit .so IN THE BUNDLE
echo "-- gate 3/5  16 KB alignment (64-bit ABIs)"
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

# --- gate 4: versionCode not already spent — the BUNDLE's own, which is what
# Play receives. Never the APK's (the 2026-10-02 defect in the header).
echo "-- gate 4/5  versionCode of the BUNDLE (Play record, spent floor, host mint ledger)"
vc="$(badging_field "$aab_badging" versionCode)"
used="$( [ -f "$LEDGER" ] && grep -E '^[0-9]+$' "$LEDGER" || true )"
g4=0
# (1) Play's own record. It says what Play has received, and nothing else.
if check_version_code "$vc" "$used"; then
  note "OK  versionCode=$vc not in $(basename "$LEDGER") (Play has not received it)"
else
  g4=1
fi
# (2) Spent under any signer, before any ledger on this host saw it.
floor_text="$( [ -f "$FLOOR_FILE" ] && cat "$FLOOR_FILE" || true )"
floor="$(floor_number "$floor_text")"
floor_notes="$(printf '%s\n' "$floor_text" | grep -E '^#[[:space:]]*[0-9][0-9-]*:' || true)"
if check_version_code_floor "$vc" "$floor" "$floor_notes"; then
  note "OK  versionCode=$vc is above the spent floor $floor ($(basename "$FLOOR_FILE"))"
else
  g4=1
fi
# (3) Minted on this host by a release build since its ledger began.
if [ -f "$MINT_LEDGER" ]; then
  if check_host_mint_ledger "$vc" "$(cat "$MINT_LEDGER")"; then
    note "OK  versionCode=$vc is not below any code in $MINT_LEDGER"
  else
    g4=1
  fi
else
  note "--  no host mint ledger at $MINT_LEDGER: no release-key build has run on this host since it began; the floor above covers the earlier ones"
fi
if [ "$g4" -eq 0 ]; then
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
# reason) as tool/assert_manifest_perms.sh, which an audit falsified in its regex form.
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
if [ "$HAVE_APK" -eq 1 ] && [ -n "$AAPT2" ] && [ "$APK_IS_BUNDLE" -eq 0 ]; then
  note "FAIL: the APK is not the bundle's build (identity, above) — its permissions say nothing about the bundle. UNVERIFIED, not clear."
  fails=$((fails+1))
elif [ -z "${badging:-}" ]; then
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
