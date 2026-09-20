#!/usr/bin/env bash
# assert_version_identity.sh — a versionCode must name ONE set of bytes.
#
# WHY THIS EXISTS (the reason is written before the act).
# ------------------------------------------------------
# Measured 2026-09-20, on this disk, with aapt2 + apksigner:
#
#   versionCode 9, package dev.aki1770del.sngnav_app, signer
#   6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14
#   (CN=SNGNav Upload) — carried by TWO DIFFERENT SETS OF BYTES:
#
#     1e7a3fad26d5…1582d7   94,655,315 B  arm64 + armeabi-v7a + x86_64  (tree 04ca782)
#     dfac31a4cbef…6d8fff   59,155,229 B  arm64 ONLY                    (tree d6b6880)
#
#   Same package, same certificate, same code. Android holds ONE versionCode per
#   install, so both would report "9" to a phone and NO RECORD CAN SAY WHICH BYTES
#   ARE ON IT. This is the exact collision the +7 -> +8 and +8 -> +9 bumps were minted
#   to prevent, and the second artifact was built 28 minutes AFTER +10 was already
#   minted, on a branch that never took the bump.
#
#   It is not new. versionCode 2 carries FIVE distinct byte-sets under that same
#   certificate — and 2 is a code a device ACTUALLY REPORTED BACK. So "the phone
#   reports 2" never identified which bytes were on it.
#
#   And a second shape, measured the same day:
#     /home/komada/work/aae-r116-15-retained-stale
#       pubspec.yaml:57            version: 0.0.2+10
#       build/app/outputs/apk/release/output-metadata.json   "versionCode": 9
#   The worktree changed branches; `build/` did not. THE DIRECTORY ANSWERS 10 TO A
#   READER AND 9 TO A PHONE — and +10 has never been built, so that directory is
#   exactly where a person or a glob goes looking for "the +10 artifact", and would
#   ship a 9 labelled 10.
#
# WHY NOTHING CAUGHT IT — and why this WIDENS a gate rather than adding one.
#
#   tool/preflight_play_upload.sh gate 4 is the only check in this repo that reads a
#   versionCode at all. It asks exactly one question — "has PLAY consumed this code?"
#   — against tool/play_uploaded_version_codes.txt, which holds ZERO integers. So it
#   passes every artifact above, and reports OK while doing it.
#
#   The missing primitive is not a gate. It is a QUESTION that gate was never asked:
#   does this versionCode identify ONE artifact? Gate 4's SCOPE was wrong, not its
#   absence — so this file widens the question gate 4 already asks, and gate 4 calls
#   it, rather than standing up a second gate beside it.
#
# THE THREE ASSERTIONS
#
#   R1 PARITY       every build/**/output-metadata.json under this repo carries the
#                   versionCode of the pubspec.yaml beside it. A tree that disagrees
#                   with its own build output is REFUSED, not reported — the upload
#                   path will not read an artifact out of it.
#   R2 COLLISION    the artifact under test does not share (versionCode, signer) with
#                   DIFFERENT bytes already recorded in tool/minted_version_identities.txt.
#   R3 RECORD       that ledger is internally consistent: any (code, signer) carrying
#                   more than one sha256 must be marked `ambiguous`, which is a human
#                   acknowledgement that the code can never be uploaded. An UNMARKED
#                   multi-sha code is a fresh collision nobody has seen yet.
#
#   KEYED ON (versionCode, SIGNER) — never on the code alone. Same package + same
#   certificate + same code = mutually substitutable on a device. A debug-signed
#   build at the same code CANNOT install over a release-signed one (certificate
#   mismatch), so it is a different and lesser thing and is NOT a collision. Keying
#   on the code alone over-reports, and inflating a finding is the same class of
#   failure as missing one. This keying came from the 2026-09-20 build-identity
#   review; it is cited here rather than re-derived.
#
# HONEST BOUNDS — what this does NOT prove.
#
#   - It proves a versionCode names one artifact. It proves NOTHING about whether
#     that artifact runs, renders, speaks, or reaches anyone. That is verified on a
#     real device and this is not that.
#   - R2/R3 read a HAND-APPENDED ledger. Empty proves only that nobody appended —
#     the same weakness that left tool/play_uploaded_version_codes.txt at zero
#     integers while nine codes were minted. `--record` appends; nothing forces it.
#     `--scan DIR...` closes the gap from the other side by reading actual bytes off
#     the disk, and is the answer to "what did somebody build and never record".
#   - R1 requires every versionCode in a metadata file to equal the pubspec's. If
#     this repo ever adopts `flutter build apk --split-per-abi`, Gradle emits several
#     elements with OFFSET codes (1009/2009/…) and this assertion will FAIL LOUDLY on
#     a shape it was not written for. That is deliberate: measured 2026-09-20, no
#     split build exists in this repo (`grep -rn split-per-abi .github/ tool/` -> 0),
#     and a guard that returns a success-shaped value on an input it does not
#     understand is exactly the silent failure this file exists to stop.
#   - `--scan` needs aapt2 AND apksigner. Without either it EXITS 2. Signer identity
#     is the whole key; a "uniqueness" answer computed without it would be a
#     different, weaker claim wearing this one's name.
#
# USAGE
#   tool/assert_version_identity.sh                      # R1 + R3 for this repo
#   tool/assert_version_identity.sh --parity             # R1 only (the pre-gate refusal)
#   tool/assert_version_identity.sh --collision --apk F  # R2 + R3 only (what gate 4 calls)
#   tool/assert_version_identity.sh --apk FILE           # R1 + R2 + R3 for that artifact
#   tool/assert_version_identity.sh --scan DIR [DIR...]  # + read real bytes off disk
#   tool/assert_version_identity.sh --record FILE        # append a measured identity
#   tool/assert_version_identity.sh --self-test          # prove the guards FAIL
#
# EXIT 0 clean · 1 finding · 2 could not measure (never silently clean)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${VERSION_IDENTITY_LEDGER:-$REPO_ROOT/tool/minted_version_identities.txt}"

# ------------------------------------------------------------------ extraction
# Pulled out as functions, not inlined in the assertions, for the reason
# min_load_align was pulled out of gate 3 on 2026-08-24: the predicates were
# always proven and THE EXTRACTION WAS NOT, and that is exactly where the defect
# lived. --self-test drives these, not copies of them.

# $1 = pubspec.yaml contents. Echoes the build number (the N in `version: X.Y.Z+N`).
# Anchored at ^version: because this pubspec's comment block discusses "+8", "+9"
# and "+10" at length; an unanchored match reads the changelog, not the version.
pubspec_build_number() {
  printf '%s\n' "$1" | sed -n 's/^version:[[:space:]]*[0-9.]*+\([0-9][0-9]*\)[[:space:]]*$/\1/p' | head -1
}

# $1 = output-metadata.json contents. Echoes EVERY versionCode it declares, one per
# line. Not `head -1`: a split-per-abi build emits several, and taking the first
# would answer a question about one element as though it were about the build.
#
# ⚑ EXTRACTION DEFECT, found by this file's own self-test before it was ever run in
# anger (2026-09-20). This was
#     sed -n 's/.*"versionCode"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
# which is LINE-BASED and GREEDY: given two elements on ONE line — which is exactly
# what a minified metadata file is — `.*` runs to the last match and `s///p`
# substitutes once, so it reported ONE code and silently dropped the other. It
# happened to be right only because Gradle pretty-prints this file today. A guard
# that is correct by the formatting of its input is not correct. grep -o finds every
# occurrence on a line; the second grep takes the integer off each match.
metadata_version_codes() {
  printf '%s\n' "$1" \
    | grep -o '"versionCode"[[:space:]]*:[[:space:]]*[0-9][0-9]*' \
    | grep -o '[0-9][0-9]*$'
}

# $1 = `apksigner verify --print-certs` output. Echoes signer #1's cert sha256.
signer_sha_from_apksigner() {
  printf '%s\n' "$1" | sed -n 's/^Signer #1 certificate SHA-256 digest:[[:space:]]*\([0-9a-f]\{64\}\).*/\1/p' | head -1
}

# $1 = `aapt2 dump badging` first line. Echoes the versionCode.
badging_version_code() {
  printf '%s\n' "$1" | sed -n "s/.*[^a-zA-Z]versionCode='\([0-9][0-9]*\)'.*/\1/p" | head -1
}

# ------------------------------------------------------------------ predicates
# Pure decisions. Every one is exercised by --self-test with input it MUST reject,
# because a guard nobody has watched fail is not known to guard.

# R1. $1 = pubspec build number, $2 = newline-separated metadata versionCodes,
#     $3 = label for the message.
check_tree_parity() {
  local pvc="$1" mvcs="$2" label="$3" bad=0 v
  [ -n "$pvc" ] || { echo "PARITY: no build number readable from pubspec.yaml ($label)"; return 1; }
  [ -n "$mvcs" ] || { echo "PARITY: no versionCode readable from build metadata ($label)"; return 1; }
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    [ "$v" = "$pvc" ] || { echo "PARITY: $label -> pubspec says +$pvc, build output says $v"; bad=1; }
  done <<< "$mvcs"
  [ "$bad" -eq 0 ] || {
    echo "        this directory answers $pvc to a reader and $(printf '%s\n' "$mvcs" | tr '\n' ' ')to a phone."
    echo "        the build output is STALE relative to its own tree. run: flutter clean"
    return 1
  }
  return 0
}

# R2. $1 = code, $2 = signer sha, $3 = artifact sha, $4 = ledger body.
#     Rejects when the same (code, signer) is on record carrying DIFFERENT bytes.
check_code_collision() {
  local vc="$1" signer="$2" sha="$3" body="$4" others
  [ -n "$vc" ] || { echo "COLLISION: versionCode not readable — UNVERIFIED, not clear"; return 1; }
  [ -n "$signer" ] || { echo "COLLISION: signer not readable — the key is (code, SIGNER); UNVERIFIED, not clear"; return 1; }
  [ -n "$sha" ] || { echo "COLLISION: artifact sha256 not readable — UNVERIFIED, not clear"; return 1; }
  others="$(printf '%s\n' "$body" | awk -F'\t' -v c="$vc" -v s="$signer" -v h="$sha" \
            '$1==c && $2==s && $3!=h {print $3}' | sort -u)"
  if [ -n "$others" ]; then
    echo "COLLISION: versionCode $vc under signer ${signer:0:16}… is ALREADY on record carrying other bytes:"
    printf '           %s\n' $others
    echo "           this artifact: $sha"
    echo "           both report $vc to a phone. no record can say which bytes are on it."
    echo "           BUMP the build number in pubspec.yaml to a code no artifact carries."
    return 1
  fi
  return 0
}

# R3. $1 = ledger body. Rejects when a (code, signer) carries >1 sha WITHOUT every
#     one of its lines marked `ambiguous`. A marked code is a human saying "this one
#     can never be uploaded"; an UNMARKED one is a collision nobody has seen yet.
#     The distinction is what keeps this assertion SATISFIABLE — bytes that exist
#     cannot be un-made, and a gate that can never go green gets switched off.
check_ledger_consistency() {
  local body="$1" bad=0 key n nmarked total
  [ -n "$body" ] && [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || return 0   # empty ledger is consistent
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    n="$(printf '%s\n' "$body" | awk -F'\t' -v k="$key" '$1"\t"$2==k {print $3}' | sort -u | wc -l)"
    [ "$n" -gt 1 ] || continue
    nmarked="$(printf '%s\n' "$body" | awk -F'\t' -v k="$key" '$1"\t"$2==k && $4=="ambiguous"' | wc -l)"
    total="$(printf '%s\n' "$body" | awk -F'\t' -v k="$key" '$1"\t"$2==k' | wc -l)"
    if [ "$nmarked" -ne "$total" ]; then
      bad=1
      echo "RECORD: versionCode ${key%%$'\t'*} carries $n distinct byte-sets under one signer,"
      echo "        and $((total-nmarked)) of its $total lines are NOT marked \`ambiguous\`."
      echo "        a code that names two artifacts can never be uploaded. mark every line"
      echo "        for that code \`ambiguous\`, or the record claims an identity it has not got."
    fi
  done < <(printf '%s\n' "$body" | awk -F'\t' 'NF>=3 {print $1"\t"$2}' | sort -u)
  [ "$bad" -eq 0 ]
}

# Strip comments and blanks from a ledger file's contents.
ledger_body() {
  printf '%s\n' "$1" | sed 's/[[:space:]]*#.*$//' | awk 'NF'
}

# ---------------------------------------------------------------- measurements
find_aapt2()     { ls "${ANDROID_HOME:-$HOME/android-sdk}"/build-tools/*/aapt2     2>/dev/null | sort -V | tail -1; }
find_apksigner() { ls "${ANDROID_HOME:-$HOME/android-sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1; }

# $1 = apk path. Echoes "code<TAB>signerSha<TAB>artifactSha". rc 2 if unmeasurable.
apk_identity() {
  local f="$1" a2 as code signer sha
  a2="$(find_aapt2)"; as="$(find_apksigner)"
  [ -x "${a2:-}" ] && [ -x "${as:-}" ] || return 2
  code="$(badging_version_code "$("$a2" dump badging "$f" 2>/dev/null | head -1)")"
  signer="$(signer_sha_from_apksigner "$("$as" verify --print-certs "$f" 2>/dev/null)")"
  sha="$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)"
  printf '%s\t%s\t%s\n' "$code" "$signer" "$sha"
}

# R1 over a whole repo root. $1 = root.
parity_over_tree() {
  local root="$1" pvc rc=0 meta seen=0 mvcs
  [ -f "$root/pubspec.yaml" ] || { echo "PARITY: no pubspec.yaml at $root — cannot measure."; return 2; }
  pvc="$(pubspec_build_number "$(cat "$root/pubspec.yaml")")"
  [ -n "$pvc" ] || { echo "PARITY: pubspec.yaml at $root declares no +N build number — cannot measure."; return 2; }
  echo "   pubspec.yaml: +$pvc"
  while IFS= read -r meta; do
    [ -n "$meta" ] || continue
    seen=1
    mvcs="$(metadata_version_codes "$(cat "$meta")")"
    if check_tree_parity "$pvc" "$mvcs" "${meta#$root/}"; then
      echo "   OK  ${meta#$root/} -> $(printf '%s' "$mvcs" | tr '\n' ' ')"
    else
      rc=1
    fi
  done < <(find "$root/build" -maxdepth 6 -name 'output-metadata.json' 2>/dev/null | sort)
  [ "$seen" -eq 1 ] || echo "   (no build output in this tree — nothing to disagree with)"
  return $rc
}

# ------------------------------------------------------------------- self-test
self_test() {
  local pass=0 total=0
  t() { # t <label> <expected-rc> <cmd...>
    local label="$1" want="$2"; shift 2
    total=$((total+1))
    "$@" >/dev/null 2>&1; local rc=$?
    if [ "$rc" -eq "$want" ]; then echo "self-test $total PASS  $label"; pass=$((pass+1))
    else echo "self-test $total FAIL  $label (wanted rc=$want, got rc=$rc)"; fi
  }

  echo ">> assert_version_identity self-test: every guard must REJECT the real defect"
  echo ""

  # The REAL 2026-09-20 identities, measured on this disk with aapt2 + apksigner.
  # These are not illustrative values. They are the bytes that collided.
  local SIGNER="6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14"
  local SHA_HELD="1e7a3fad26d5c7e1e9d457ed0f48453c012b85e4719737db47b229d8ae1582d7"
  local SHA_OTHER="dfac31a4cbef64a7f640cdab5a8de14dcbef78fca61fcba220f0c9c5d36d8fff"
  local SIGNER_DEBUG="8d40d1fc00000000000000000000000000000000000000000000000000000000"

  # ---- R2 COLLISION. Case 1 IS the defect: build dfac31a4 at 9 when 1e7a3fad is
  # already at 9 under the same certificate. If this passes, the guard is decoration.
  local LED_HELD; LED_HELD="$(printf '9\t%s\t%s\tminted\theld release, tree 04ca782' "$SIGNER" "$SHA_HELD")"
  t "THE REAL 2026-09-20 COLLISION rejected"   1 check_code_collision 9 "$SIGNER" "$SHA_OTHER" "$LED_HELD"
  t "the same bytes again are NOT a collision" 0 check_code_collision 9 "$SIGNER" "$SHA_HELD"  "$LED_HELD"
  t "a fresh code accepted"                    0 check_code_collision 10 "$SIGNER" "$SHA_OTHER" "$LED_HELD"
  t "DEBUG signer at code 9 is not a collision" 0 check_code_collision 9 "$SIGNER_DEBUG" "$SHA_OTHER" "$LED_HELD"
  t "unreadable code rejected"                 1 check_code_collision "" "$SIGNER" "$SHA_OTHER" "$LED_HELD"
  t "unreadable signer rejected"               1 check_code_collision 9 "" "$SHA_OTHER" "$LED_HELD"
  t "unreadable artifact sha rejected"         1 check_code_collision 9 "$SIGNER" "" "$LED_HELD"

  # ---- R1 PARITY. Case 1 IS the defect: pubspec +10, build output 9.
  t "THE REAL +10-tree-holding-a-9 rejected" 1 check_tree_parity 10 "9"  "aae-r116-15-retained-stale"
  t "the second instance (+6 / 5) rejected"  1 check_tree_parity 6  "5"  "r115-aae-integration-0bc7351"
  t "a matching tree accepted"               0 check_tree_parity 10 "10" "clean"
  t "one of several codes wrong is rejected" 1 check_tree_parity 10 "$(printf '10\n9')" "mixed"
  t "all of several codes right accepted"    0 check_tree_parity 10 "$(printf '10\n10')" "fat"
  t "unreadable pubspec rejected"            1 check_tree_parity "" "9"  "no-pubspec"
  t "unreadable metadata rejected"           1 check_tree_parity 10 ""   "no-metadata"

  # ---- R3 RECORD consistency.
  local LED_BOTH_UNMARKED LED_BOTH_MARKED LED_HALF
  LED_BOTH_UNMARKED="$(printf '9\t%s\t%s\tminted\ta\n9\t%s\t%s\tminted\tb' "$SIGNER" "$SHA_HELD" "$SIGNER" "$SHA_OTHER")"
  LED_BOTH_MARKED="$(printf '9\t%s\t%s\tambiguous\ta\n9\t%s\t%s\tambiguous\tb' "$SIGNER" "$SHA_HELD" "$SIGNER" "$SHA_OTHER")"
  LED_HALF="$(printf '9\t%s\t%s\tambiguous\ta\n9\t%s\t%s\tminted\tb' "$SIGNER" "$SHA_HELD" "$SIGNER" "$SHA_OTHER")"
  t "an UNACKNOWLEDGED collision on record rejected" 1 check_ledger_consistency "$LED_BOTH_UNMARKED"
  t "a half-marked collision rejected"               1 check_ledger_consistency "$LED_HALF"
  t "a fully acknowledged collision accepted"        0 check_ledger_consistency "$LED_BOTH_MARKED"
  t "a clean record accepted"                        0 check_ledger_consistency "$LED_HELD"
  t "an empty record is consistent"                  0 check_ledger_consistency ""

  # ---- EXTRACTION. The 2026-08-24 lesson: the predicates were proven and the
  # extraction was not, and that is where the defect lived. Real file shapes.
  local PUBSPEC_REAL
  PUBSPEC_REAL="$(printf '%s\n' \
    '# 2026-09-20: +9 -> +10. The 0.0.2+9 APK EXISTS, is signed CN=SNGNav Upload and' \
    '# is held by hash; +9 is NOT withdrawn and still installs. This build is a' \
    'version: 0.0.2+10' \
    "publish_to: 'none'")"
  t "the +10 line is read past a comment block naming +9" 0 \
      test "$(pubspec_build_number "$PUBSPEC_REAL")" = "10"
  t "a pubspec with no +N yields nothing"                 0 \
      test -z "$(pubspec_build_number 'version: 0.0.2')"

  local META_ONE META_SPLIT
  META_ONE='{"elements":[{"versionCode": 9,"versionName":"0.0.2"}],"minSdkVersionForDexing": 24}'
  META_SPLIT='{"elements":[{"versionCode": 1009},{"versionCode": 2009}]}'
  t "one element -> one code"           0 test "$(metadata_version_codes "$META_ONE")" = "9"
  t "minSdkVersionForDexing is not a versionCode" 0 \
      test "$(metadata_version_codes "$META_ONE" | wc -l)" = "1"
  t "a split build yields BOTH codes, not the first" 0 \
      test "$(metadata_version_codes "$META_SPLIT" | tr '\n' ' ')" = "1009 2009 "
  t "an unhandled split build FAILS parity, never passes" 1 \
      check_tree_parity 9 "$(metadata_version_codes "$META_SPLIT")" "split"

  local APKSIGNER_REAL
  APKSIGNER_REAL="$(printf '%s\n' \
    'Signer #1 certificate DN: CN=SNGNav Upload, OU=SNGNav, O=SNGNav, L=Nagoya, ST=Aichi, C=JP' \
    "Signer #1 certificate SHA-256 digest: $SIGNER" \
    'Signer #1 certificate SHA-1 digest: 0000000000000000000000000000000000000000')"
  t "signer sha256 read, not the sha1"  0 test "$(signer_sha_from_apksigner "$APKSIGNER_REAL")" = "$SIGNER"
  t "no signer line -> empty, not junk" 0 test -z "$(signer_sha_from_apksigner 'not signed')"

  # platformBuildVersionCode and compileSdkVersion sit on the SAME line as
  # versionCode in real badging output. Pinned as a regression test, with its own
  # limit stated: today a greedy `.*versionCode='` does NOT capture 36, because
  # platformBuildVersionCode carries a CAPITAL V and the pattern's v is lowercase.
  # That is a property of aapt2's spelling, not of the pattern, and it is the kind
  # of thing that holds until a tool renames a field. This case pins the answer so
  # a rename is caught here rather than in a comparison that then passes for the
  # wrong reason. (Written after asserting the opposite and being refuted by the
  # real line — the claim that this was already broken was wrong.)
  local BADGING_REAL
  BADGING_REAL="package: name='dev.aki1770del.sngnav_app' versionCode='9' versionName='0.0.2' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36'"
  t "versionCode read, not platformBuildVersionCode" 0 test "$(badging_version_code "$BADGING_REAL")" = "9"
  t "no badging -> empty, not junk"                  0 test -z "$(badging_version_code 'nothing')"

  # ---- END TO END, hermetic: a throwaway tree with a real mismatch on disk.
  local WT; WT="$(mktemp -d)"
  mkdir -p "$WT/build/app/outputs/apk/release"
  printf 'version: 0.0.2+10\n' > "$WT/pubspec.yaml"
  printf '%s\n' "$META_ONE" > "$WT/build/app/outputs/apk/release/output-metadata.json"
  t "a real stale build directory is REFUSED end to end" 1 parity_over_tree "$WT"
  printf 'version: 0.0.2+9\n' > "$WT/pubspec.yaml"
  t "the same directory passes once the tree agrees"     0 parity_over_tree "$WT"
  rm -rf "$WT"
  local WT2; WT2="$(mktemp -d)"
  printf 'version: 0.0.2+10\n' > "$WT2/pubspec.yaml"
  t "a tree with no build output is clean, not skipped"  0 parity_over_tree "$WT2"
  t "a tree with no pubspec CANNOT MEASURE (rc 2)"       2 parity_over_tree "$WT2/nope"
  rm -rf "$WT2"

  echo ""
  echo "self-test: $pass/$total passed"
  [ "$pass" -eq "$total" ] || { echo "SELF-TEST FAILED — this guard is not known to guard."; return 1; }
  return 0
}

# ------------------------------------------------------------------------ main
MODE="full"; APK_ARG=""; SCAN_DIRS=(); RECORD_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) MODE="self-test"; shift ;;
    --parity)    MODE="parity"; shift ;;
    --collision) MODE="collision"; shift ;;
    --apk)       APK_ARG="${2:-}"; shift 2 || shift ;;
    --record)    MODE="record"; RECORD_ARG="${2:-}"; shift 2 || shift ;;
    --scan)      shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do SCAN_DIRS+=("$1"); shift; done ;;
    -h|--help)   sed -n '2,95p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1 — refusing rather than ignoring it in silence."; exit 2 ;;
  esac
done

[ "$MODE" = "self-test" ] && { self_test; exit $?; }

echo "== version identity =="
echo "repo:   $REPO_ROOT"
echo "ledger: $LEDGER"
LEDGER_RAW="$( [ -f "$LEDGER" ] && cat "$LEDGER" || printf '' )"
BODY="$(ledger_body "$LEDGER_RAW")"
rc=0

if [ "$MODE" != "collision" ]; then
  echo "-- R1 parity (build output vs the pubspec beside it)"
  parity_over_tree "$REPO_ROOT"; prc=$?
  [ "$prc" -eq 0 ] || rc=$prc
fi
if [ "$MODE" = "parity" ]; then
  case $rc in
    0) echo "PARITY OK." ;;
    2) echo "VERDICT: COULD NOT MEASURE. UNVERIFIED, never cleared." ;;
    *) echo "VERDICT: FINDING." ;;
  esac
  exit $rc
fi

if [ "$MODE" = "record" ]; then
  [ -f "$RECORD_ARG" ] || { echo "--record: no such file: $RECORD_ARG"; exit 2; }
  ident="$(apk_identity "$RECORD_ARG")" || { echo "--record: need aapt2 AND apksigner. UNVERIFIED, never cleared."; exit 2; }
  IFS=$'\t' read -r c s h <<< "$ident"
  [ -n "$c" ] && [ -n "$s" ] && [ -n "$h" ] || { echo "--record: could not measure identity of $RECORD_ARG"; exit 2; }
  printf '%s\t%s\t%s\tminted\t%s\n' "$c" "$s" "$h" "$(basename "$RECORD_ARG")" >> "$LEDGER"
  echo "recorded: code $c  signer ${s:0:16}…  sha $h"
  echo "COMMIT the ledger. An unrecorded artifact is one nothing can compare against."
  exit 0
fi

echo "-- R3 record consistency"
if check_ledger_consistency "$BODY"; then
  echo "   OK  $(printf '%s\n' "$BODY" | awk 'NF' | wc -l) recorded identities, no unacknowledged collision"
else
  rc=1
fi

if [ -n "$APK_ARG" ]; then
  echo "-- R2 collision (the artifact under test against the record)"
  if [ ! -f "$APK_ARG" ]; then
    echo "   FAIL: no such artifact: $APK_ARG"; rc=1
  else
    ident="$(apk_identity "$APK_ARG")"; irc=$?
    if [ "$irc" -eq 2 ]; then
      echo "   CANNOT MEASURE: need aapt2 AND apksigner. Signer identity is the whole key."
      echo "   UNVERIFIED, never cleared."
      rc=2
    else
      IFS=$'\t' read -r c s h <<< "$ident"
      echo "   $APK_ARG"
      echo "   code=$c  signer=${s:0:16}…  sha256=$h"
      if check_code_collision "$c" "$s" "$h" "$BODY"; then
        echo "   OK  versionCode $c names these bytes and no others on record"
      else
        rc=1
      fi
    fi
  fi
fi

if [ "${#SCAN_DIRS[@]}" -gt 0 ]; then
  echo "-- scan: reading real bytes off disk (answers 'what did somebody build and never record')"
  a2="$(find_aapt2)"; as="$(find_apksigner)"
  if [ ! -x "${a2:-}" ] || [ ! -x "${as:-}" ]; then
    echo "   CANNOT MEASURE: need aapt2 AND apksigner. UNVERIFIED, never cleared."; rc=2
  else
    inv="$(mktemp)"; n=0
    while IFS= read -r f; do
      line="$("$a2" dump badging "$f" 2>/dev/null | head -1)"
      case "$line" in *"name='dev.aki1770del.sngnav_app'"*) ;; *) continue ;; esac
      c="$(badging_version_code "$line")"; [ -n "$c" ] || continue
      s="$(signer_sha_from_apksigner "$("$as" verify --print-certs "$f" 2>/dev/null)")"
      [ -n "$s" ] || s="UNSIGNED-OR-UNREADABLE"
      printf '%s\t%s\t%s\tdisk\t%s\n' "$c" "$s" "$(sha256sum "$f" | cut -d' ' -f1)" "$f" >> "$inv"
      n=$((n+1))
    done < <(find "${SCAN_DIRS[@]}" -maxdepth 8 -name '*.apk' 2>/dev/null)
    if [ "$n" -eq 0 ]; then
      echo "   CANNOT MEASURE: 0 artifacts of this package found under ${SCAN_DIRS[*]}."; rc=2
    else
      echo "   artifacts read: $n"
      if check_ledger_consistency "$(cat "$inv")"; then
        echo "   OK  no unacknowledged collision among the bytes actually on disk"
      else
        echo "   ^ these are REAL FILES, not a record. Nothing acknowledged them."
        rc=1
      fi
    fi
    rm -f "$inv"
  fi
fi

echo ""
case $rc in
  0) echo "VERDICT: a versionCode names one artifact, everywhere this run could see."
     echo "         (Not a clearance of anyone's work — this reads bytes, not people.)" ;;
  2) echo "VERDICT: COULD NOT MEASURE. UNVERIFIED, never cleared." ;;
  *) echo "VERDICT: FINDING above." ;;
esac
exit $rc
