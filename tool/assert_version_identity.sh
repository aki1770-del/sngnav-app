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
#   - R2/R3 read a HAND-APPENDED ledger. `--record` appends; nothing forces it, so
#     the record can be INCOMPLETE — the same weakness that left
#     tool/play_uploaded_version_codes.txt at zero integers while nine codes were
#     minted. `--scan DIR...` closes that gap from the other side by reading actual
#     bytes off the disk, and is the answer to "what did somebody build and never
#     record". ⚑ An incomplete record and an ABSENT one are different, and until
#     2026-09-21 this file treated them the same: a missing or empty ledger returned
#     0 with a clean verdict. It now returns 2. See ledger_state() below for the
#     measurement and the refutation that produced it.
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
#   - THE SIGNER AXIS IS CONFIRMED BY A SECOND AND THIRD IMPLEMENTATION.
#     ⚑ THIS BOUND SAID THE OPPOSITE UNTIL 2026-09-21, AND THE CLAIM WAS WRONG.
#     It read: "the signer axis rests on apksigner alone... NO SECOND IMPLEMENTATION
#     IS AVAILABLE HERE... UNVERIFIED by an independent reader." Each premise under
#     it was true -- keytool DOES print "Not a signed jar file" and exit 0, jarsigner
#     IS absent, the artifacts DO carry zero v1 blocks -- and the conclusion did not
#     follow from them. What was surveyed was TOOLS THAT READ APK SIGNATURES. What
#     was never attempted was WRITING THE READ, and python3 with the `cryptography`
#     library sat on this machine the entire time. An absence of tools is not an
#     absence of a second opinion; it is an absence of having looked for one.
#
#     Measured 2026-09-21 over ALL 40 artifacts of this package, two readers that
#     share no code with apksigner and none with each other's central idea:
#       PATH A  EOCD -> central-directory offset -> "APK Sig Block 42" magic ->
#               id-value pairs -> v2 (0x7109871a) / v3 (0xf05368c0) -> signers ->
#               signed data -> certificates -> sha256 of the first DER certificate.
#       PATH B  no structure walk at all: scan the tail for DER SEQUENCE headers and
#               keep whatever an X.509 parser accepts as a certificate.
#     RESULT: 40/40 agree with apksigner on BOTH paths. 0 mismatches, 0 unreadable.
#     Path B is the load-bearing one -- it knows nothing of the signing-block format,
#     so its agreement is not a shared misreading of a spec.
#
#     The residual that REMAINS, stated so this bound does not over-correct in the
#     other direction: all three readers agree on WHICH CERTIFICATE IS PRESENT. None
#     of them verifies that the signature over the APK's contents is VALID -- that
#     the bytes were actually signed by that key rather than a certificate being
#     carried alongside unrelated content. apksigner does check that; this file never
#     asked it to, and the two readers above do not. For THIS guard's question --
#     does one versionCode name one set of bytes under one signing identity -- cert
#     identity is the whole key and that is what is confirmed. A claim that an
#     artifact is VALIDLY signed is a different claim and is NOT made here.
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

# R4. $1 = this tree's pubspec build number, $2 = ledger body.
#     Rejects when the code this tree is ABOUT TO MINT is already on record as
#     `ambiguous` -- a code that is already known to name more than one set of bytes.
#
# ⚑ WHY THIS IS NOT A WIDENING OF R1, ruled 2026-09-21.
#   The nested sngnav-app clone is a live trap: its pubspec reads 0.0.5+2 and a
#   release build from it mints versionCode 2, which already names SIX byte-sets.
#   R1 PARITY is structurally SILENT on it -- measured: its pubspec says 2 and all
#   fourteen of its output-metadata.json files say 2. THEY AGREE. R1 asks whether a
#   tree is consistent WITH ITSELF, the clone is, and R1 returns the true answer to
#   its own question.
#
#   Widening R1 to catch it would make R1's name a lie -- a check called PARITY that
#   fails on a tree with perfect parity is the same class of defect as a function
#   returning a success-shaped value: the name stops describing the behaviour. The
#   re-entrancy test says the primitive already exists under another name, and it
#   does: it is R2's question -- "does this code already name other bytes?" -- asked
#   of a TREE at build time rather than of an ARTIFACT at upload time.
#
#   Bounded on `ambiguous` and not on "present at all", deliberately. A code on
#   record as `minted` is the normal state of the code you just built and recorded;
#   failing on that would redden CI for the whole window between recording a release
#   and bumping past it, and a gate that is red on the honest path gets switched off
#   (V20). A code on record as `ambiguous` can NEVER be legitimately minted again --
#   that is what the marker means -- so this is always-true, not a heuristic.
#
#   ⚑ THE BOUND, stated because it was true from the first line and unwritten until
#   an independent certification asked for it in so many words. R4 catches the
#   RE-MINTING of a code ALREADY MARKED `ambiguous`. IT DOES NOT CATCH THE CREATION
#   OF THE FIRST AMBIGUITY. Build twice at a code that is clean on the record and R4
#   is silent both times: nothing is marked ambiguous until a second byte-set has
#   already been minted and somebody has recorded and acknowledged it. That is
#   INHERENT, not a defect -- `ambiguous` is a human acknowledgement of a collision
#   that already happened, so a check keyed on it is a check on the SECOND offence
#   onward by construction. The first offence is caught by R2 at upload time and by
#   --scan from the byte side, and it is NOT caught at build time by anything here.
#
#   WHAT IT DOES NOT REACH, and no guard in this repo can: a clone that does not
#   HAVE this commit has none of these assertions. The nested clone does not contain
#   assert_version_identity.sh at all. That is a distribution fact, not a design gap,
#   and naming it is the whole available act from inside this repo.
check_mint_target() {
  local pvc="$1" body="$2" n
  [ -n "$pvc" ] || { echo "MINT: no build number readable from pubspec.yaml — UNVERIFIED, not clear"; return 1; }
  [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || return 0
  n="$(printf '%s\n' "$body" | awk -F'\t' -v c="$pvc" '$1==c && $4=="ambiguous" {print $3}' | sort -u | wc -l)"
  [ "$n" -gt 0 ] || return 0
  echo "MINT: this tree declares version +$pvc, and $pvc is on record as \`ambiguous\`"
  echo "      — it already names $n distinct sets of bytes. A build from this tree"
  echo "      mints ANOTHER one, carrying a number that identifies none of them."
  echo "      BUMP pubspec.yaml to a code no artifact carries before building."
  return 1
}

# Strip comments and blanks from a ledger file's contents.
ledger_body() {
  printf '%s\n' "$1" | sed 's/[[:space:]]*#.*$//' | awk 'NF'
}

# $1 = ledger body. Echoes one line per DEFECTIVE row, empty when every row is
# well formed. This is the format predicate, and it is TOTAL with respect to the
# format rather than partial.
#
# ⚑ THE FIFTH DOOR, 2026-09-21. The first version of this check counted FIELDS and
# never looked at their CONTENT, and a field count is a PARTIAL predicate. Three
# single-field edits to one row -- the code to a letter, the signer to empty, the
# hash to empty -- each leave the file splitting into five tab fields on every line
# with ZERO lines under the threshold, and on each the guard returned
#     OK  versionCode 9 is ON RECORD naming exactly these bytes, and no others
# at rc 0. Reproduced here before repairing, with the same surgical signature as the
# delimiter mangle: BLIND to exactly the collider whose row was damaged, still
# biting the other two.
#
# It is not contrived. This file is hand-edited by design, and this seat has already
# recorded running a diff with the wrong awk field index against it -- a script with
# that index that WRITES produces precisely this shape.
#
# ⚑ AND IT IS THE COUNTER-EXAMPLE TO THIS FILE'S OWN ARGUMENT. Round three ruled
# that a second parser is unnecessary because "a broken parser cannot hide from a
# check on its own output shape, because the failure IS the shape". That survives,
# but only to the STRENGTH OF THE SHAPE PREDICATE: a parse failure with the right
# field count and the wrong content wears a CORRECT shape. The argument terminates
# only when the predicate is TOTAL. So the repair is not a second parser -- it is a
# COMPLETE one. Still one parser, still terminating.
#
# Every clause is always true of an honest record, so none can redden a legitimate
# run (V20): the format is defined at the head of the ledger as
#   versionCode <TAB> signer-sha256 <TAB> artifact-sha256 <TAB> status <TAB> note
# a sha256 is 64 lowercase hex characters by construction, a versionCode is an
# integer by Android's own definition, and `status` is a CLOSED set of two words
# this file defines. Length+charclass rather than an interval regex so the check
# does not depend on which awk is installed.
ledger_row_defects() {
  printf '%s\n' "$1" | awk -F'\t' '
    NF < 4 {
      printf "  line %d: %d tab-separated field(s), need at least 4 (code, signer, sha, status)\n", NR, NF; next }
    $1 !~ /^[0-9]+$/ {
      printf "  line %d: versionCode %s is not an integer\n", NR, ($1=="" ? "<empty>" : "\""$1"\"") }
    (length($2) != 64 || $2 !~ /^[0-9a-f]+$/) {
      printf "  line %d: signer is not a 64-char lowercase sha256 (length %d)\n", NR, length($2) }
    (length($3) != 64 || $3 !~ /^[0-9a-f]+$/) {
      printf "  line %d: artifact hash is not a 64-char lowercase sha256 (length %d)\n", NR, length($3) }
    ($4 != "minted" && $4 != "ambiguous") {
      printf "  line %d: status %s is not one of: minted, ambiguous\n", NR, ($4=="" ? "<empty>" : "\""$4"\"") }
  '
}

# ⚑ THE HATCH BOUND, as a PREDICATE rather than an inline test, 2026-09-21.
# $1 = ledger state, $2 = non-empty if an artifact is under test, $3 = scan-dir count.
# Returns 0 when the declared-empty hatch must be REFUSED.
#
# Extracted because the test that guarded this bound COULD NOT FAIL. It drove the
# whole script with `--scan <empty dir>`, and an empty scan directory returns rc 2
# on its own -- so the assertion was satisfied by the empty directory rather than by
# the hatch, and removing the bound entirely left the suite green. It also reached
# find_aapt2/find_apksigner and made this guard the one OUTSIDE-REPO entry in
# selftest-hermeticity-guard.sh. A bound whose test passes for another reason is not
# guarded, and a test that leaves the repo's own hermeticity instrument red is worse
# than no test. Driving the predicate directly fixes both: it fails when the bound is
# removed, and it touches no SDK.
hatch_refused() {
  local state="$1" has_apk="$2" nscan="$3"
  [ "$state" = "declared-empty" ] || return 1
  [ -n "$has_apk" ] || [ "${nscan:-0}" -gt 0 ]
}

# $1 = ledger path. Echoes the state of the RECORD ITSELF, which is a measurement
# and therefore a function --self-test can drive, not an inline test nobody has
# watched fail.
#
# ⚑ FAIL-OPEN, REFUTED 2026-09-21 on V14 by an independent certification and
# reproduced by this seat on the real collider before repairing it. This line was:
#     LEDGER_RAW="$( [ -f "$LEDGER" ] && cat "$LEDGER" || printf '' )"
# which makes a MISSING record read as an EMPTY one — and an empty record is
# trivially consistent and trivially non-colliding. Point the ledger at a path that
# does not exist and the guard printed
#     OK  versionCode 9 names these bytes and no others on record
#     VERDICT: a versionCode names one artifact, everywhere this run could see.
# and exited 0 over dfac31a4…, the exact artifact it was written to refuse. It did
# not cry wolf. It went quietly green. An absent record IS "could not measure", and
# this file's own contract (EXIT ... 2 could not measure, never silently clean) said
# so while the code did the opposite.
#
#   missing         no such file. NOTHING was compared. rc 2.
#   unreadable      it exists and cannot be read. rc 2.
#   empty           it exists and holds no data row, and does not say why. rc 2 --
#                   indistinguishable from a record someone deleted the rows out of.
#   declared-empty  it holds no data row AND affirmatively says so with a
#                   `# NO-IDENTITIES-YET:` line. A HUMAN acknowledgement, exactly as
#                   `ambiguous` is in R3 -- and it is what keeps this satisfiable for
#                   a tree that has genuinely never built an artifact. Without it a
#                   fresh checkout could never go green, and a gate that can never go
#                   green gets switched off (V20).
#   rows            it holds data rows. Measure.
ledger_state() {
  local path="$1" raw body
  [ -e "$path" ] || { echo "missing"; return 0; }
  [ -r "$path" ] || { echo "unreadable"; return 0; }
  raw="$(cat "$path" 2>/dev/null)" || { echo "unreadable"; return 0; }
  body="$(ledger_body "$raw")"
  if [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    # ⚑ THE FOURTH DOOR, 2026-09-21: present, readable, TRACKED -- and UNPARSEABLE.
    # Until this check existed the question asked here was "can I READ this file?"
    # and never "can I PARSE its rows?", while every assertion in this file splits
    # on TAB. Convert the tabs to spaces -- an editor with expandtab, a paste
    # through a terminal -- and the file still DISPLAYS fourteen rows, still carries
    # the release signer on every one of them (grep counts 14), and this function
    # said `rows`. Measured on the real collider at code 9:
    #
    #   committed ledger ...... COLLISION, rc 1
    #   all tabs -> spaces ..... rc 0, "signer appears on NO row of the ledger at
    #                            all" -- false of all fourteen rows
    #   ONE row mangled ........ rc 0, "OK versionCode 9 is ON RECORD naming exactly
    #                            these bytes, and no others" -- the guard's STRONGEST
    #                            POSITIVE state, declaring uniqueness while the row
    #                            that disproves it sits one line away in the SAME FILE
    #
    # It disables R2, R3 and R4 in one stroke. Measured: the whitespace split sees
    # 14 rows, the tab split sees 0 keys, 0 signer matches, 0 ambiguous markers, and
    # NF on the first row is 1.
    #
    # The defect PREDATES the fail-closed repair -- the old guard returns rc 0 on the
    # same mangled file, verified against ee2cc33. What the repair changed is the
    # CONFIDENCE of the false sentence: the `affirmed` state added to cure the
    # previous finding is what delivers this falsehood, with exactly the authority
    # that fix was meant to supply.
    #
    # The check can never be legitimately false. This file's own format is five
    # tab-separated fields and ledger_body has already stripped comments and blanks,
    # so every surviving line MUST split into at least three. A row that does not is
    # not a row this guard can read, whatever it looks like on screen.
    if [ -z "$(ledger_row_defects "$body")" ]; then
      echo "rows"; return 0
    fi
    echo "malformed"; return 0
  fi
  if printf '%s\n' "$raw" | grep -q '^[[:space:]]*#[[:space:]]*NO-IDENTITIES-YET:'; then
    echo "declared-empty"; return 0
  fi
  echo "empty"
}

# $1 = code, $2 = signer sha, $3 = artifact sha, $4 = ledger body.
# Echoes the EPISTEMIC state of this identity in the record.
#
# ⚑ Added 2026-09-21 with the fail-closed repair, on the same certification's second
# finding: R2 printed the SAME sentence -- "OK versionCode N names these bytes and no
# others on record" -- for two different states of knowledge. "The record affirms
# these exact bytes" and "this code is on no row of the record whatsoever" are not
# the same fact, and a reader could not tell them apart from the output.
#
#   affirmed       this exact (code, signer, sha) is ON a row. The record SAYS these bytes.
#   other          (code, signer) is on record carrying DIFFERENT bytes -- the collision.
#   absent         the SIGNER is on record, this CODE under it is not. A genuinely
#                  fresh release code looks exactly like this the first time.
#   absent-signer  the SIGNER appears on NO row at all. Almost always a debug
#                  certificate, which by this ledger's own header does not belong in
#                  it -- so telling the operator to --record it would be wrong advice
#                  in a success-shaped sentence, which is the class of defect this
#                  whole file exists to stop.
#
# `absent` is deliberately NOT a failure: a genuinely fresh versionCode is absent from
# the record the first time it is built, and reddening that would block every
# legitimate release (V20). It is reported as its own state and the operator is told
# to record it -- distinguished, not failed.
identity_record_state() {
  local vc="$1" signer="$2" sha="$3" body="$4"
  if printf '%s\n' "$body" | awk -F'\t' -v c="$vc" -v s="$signer" -v h="$sha" \
       '$1==c && $2==s && $3==h {f=1} END{exit !f}'; then echo "affirmed"; return 0; fi
  if printf '%s\n' "$body" | awk -F'\t' -v c="$vc" -v s="$signer" \
       '$1==c && $2==s {f=1} END{exit !f}'; then echo "other"; return 0; fi
  if printf '%s\n' "$body" | awk -F'\t' -v s="$signer" \
       '$2==s {f=1} END{exit !f}'; then echo "absent"; return 0; fi
  echo "absent-signer"
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
  # NOTE: check_ledger_consistency on an empty BODY is still 0, and that is correct
  # at the predicate level -- a record with no rows contains no unacknowledged
  # collision. The defect was never here. It was that main/ CALLED it on an empty
  # body derived from a file that DID NOT EXIST, and reported the vacuous pass as a
  # clean bill. The fix is at the caller, so the tests for it are below.
  t "an empty record is trivially consistent (vacuous, not clean)" 0 check_ledger_consistency ""

  # ---- THE FAIL-OPEN, 2026-09-21. Proven to FAIL before it is believed fixed.
  # Refuted on V14 by an independent certification and reproduced by this seat on the
  # real collider: with the ledger absent the guard exited 0 over dfac31a4… at code 9.
  local SELF; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  local LD_MISSING LD_EMPTY LD_DECLARED LD_ROWS LD_TMPDIR
  LD_TMPDIR="$(mktemp -d)"
  LD_MISSING="$LD_TMPDIR/there-is-no-such-file.txt"
  LD_EMPTY="$LD_TMPDIR/empty.txt";        : > "$LD_EMPTY"
  LD_DECLARED="$LD_TMPDIR/declared.txt";  printf '# NO-IDENTITIES-YET: nothing built in this tree yet\n' > "$LD_DECLARED"
  LD_ROWS="$LD_TMPDIR/rows.txt";          printf '%s\n' "$LED_HELD" > "$LD_ROWS"
  local LD_COMMENTS="$LD_TMPDIR/comments.txt"; printf '# a header and nothing else\n#\n' > "$LD_COMMENTS"
  t "a MISSING ledger is 'missing', not 'empty'"  0 test "$(ledger_state "$LD_MISSING")"  = "missing"
  t "an EMPTY ledger is 'empty'"                  0 test "$(ledger_state "$LD_EMPTY")"    = "empty"
  t "a comments-only ledger is 'empty', not rows" 0 test "$(ledger_state "$LD_COMMENTS")" = "empty"
  t "a DECLARED-empty ledger is distinguished"    0 test "$(ledger_state "$LD_DECLARED")" = "declared-empty"
  t "a populated ledger is 'rows'"                0 test "$(ledger_state "$LD_ROWS")"     = "rows"

  # ---- THE FOURTH DOOR: present, readable, tracked -- and UNPARSEABLE.
  # A ledger whose tabs became spaces still DISPLAYS its rows and still greps for the
  # signer on every one, while every assertion that splits on tab sees nothing.
  local LD_MANGLED LD_ONEBAD
  LD_MANGLED="$LD_TMPDIR/mangled.txt"; printf '%s\n' "$LED_HELD" | tr '\t' ' ' > "$LD_MANGLED"
  LD_ONEBAD="$LD_TMPDIR/onebad.txt"
  { printf '%s\n' "$LED_BOTH_MARKED" | head -1 | tr '\t' ' '
    printf '%s\n' "$LED_BOTH_MARKED" | tail -1; } > "$LD_ONEBAD"
  t "a TAB-MANGLED ledger is 'malformed', not 'rows'" 0 \
      test "$(ledger_state "$LD_MANGLED")" = "malformed"
  t "ONE mangled row makes the whole file 'malformed'" 0 \
      test "$(ledger_state "$LD_ONEBAD")" = "malformed"
  t "the mangled file still LOOKS like a record (the reason this is invisible)" 0 \
      test "$(grep -c "$SIGNER" "$LD_MANGLED")" = "1"
  # ---- THE FIFTH DOOR: right field COUNT, wrong field CONTENT.
  # Each of these splits into five tab fields on every line with none under the
  # threshold, and each was accepted as `rows` until the predicate became total.
  local LD_OK LD_BADCODE LD_BADSIGNER LD_BADHASH LD_BADSTATUS
  LD_OK="$(printf '9\t%s\t%s\tminted\tnote' "$SIGNER" "$SHA_HELD")"
  t "a well-formed row has NO defects"        0 test -z "$(ledger_row_defects "$LD_OK")"
  LD_BADCODE="$(printf 'X\t%s\t%s\tminted\tnote' "$SIGNER" "$SHA_HELD")"
  LD_BADSIGNER="$(printf '9\t\t%s\tminted\tnote' "$SHA_HELD")"
  LD_BADHASH="$(printf '9\t%s\t\tminted\tnote' "$SIGNER")"
  LD_BADSTATUS="$(printf '9\t%s\t%s\tprobably\tnote' "$SIGNER" "$SHA_HELD")"
  t "THE FIFTH DOOR a: a non-integer versionCode is a defect" 0 \
      test -n "$(ledger_row_defects "$LD_BADCODE")"
  t "THE FIFTH DOOR b: an empty signer is a defect"           0 \
      test -n "$(ledger_row_defects "$LD_BADSIGNER")"
  t "THE FIFTH DOOR c: an empty artifact hash is a defect"    0 \
      test -n "$(ledger_row_defects "$LD_BADHASH")"
  t "a status outside the closed set is a defect"             0 \
      test -n "$(ledger_row_defects "$LD_BADSTATUS")"
  t "a 63-char hash is a defect (length, not just charclass)" 0 \
      test -n "$(ledger_row_defects "$(printf '9\t%s\t%s\tminted\tn' "$SIGNER" "${SHA_HELD:0:63}")")"
  t "an UPPERCASE hash is a defect (the record is lowercase)" 0 \
      test -n "$(ledger_row_defects "$(printf '9\t%s\t%s\tminted\tn' "$SIGNER" "$(printf '%s' "$SHA_HELD" | tr a-f A-F)")")"
  t "the REAL committed ledger has no row defect"             0 \
      test -z "$(ledger_row_defects "$(ledger_body "$(cat "$(dirname "$SELF")/minted_version_identities.txt")")")"
  t "a content-damaged ledger is 'malformed', not 'rows'"     0 \
      test "$(ledger_state <(printf '%s\n' "$LD_BADCODE"))" = "malformed"
  t "a 4-field well-formed row parses (note is optional)"     0 \
      test "$(ledger_state <(printf '9\t%s\t%s\tminted\n' "$SIGNER" "$SHA_HELD"))" = "rows"
  t "THE REFUTED STATE: a mangled ledger -> rc 2, NOT a green run" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_MANGLED" bash "$SELF" --collision --apk "$SELF"
  t "a mangled ledger reddens the record-only run CI makes" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_MANGLED" bash "$SELF" --collision
  # The count that REASSURES must come from the same parser as the counts that DECIDE.
  t "the printed identity count uses the TAB split, not whitespace" 0 \
      test "$(printf '%s\n' "$(ledger_body "$(cat "$LD_MANGLED")")" | awk -F'\t' 'NF>=3' | wc -l)" = "0"

  # END TO END, on the REAL 2026-09-20 collider identity, through main().
  # This is the exact run that printed OK and exited 0 before the repair.
  t "THE REFUTED STATE: missing ledger + the real collider -> rc 2, NOT 0" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_MISSING" bash "$SELF" --collision --apk "$SELF"
  t "empty ledger + an artifact -> rc 2, NOT 0" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_EMPTY" bash "$SELF" --collision --apk "$SELF"
  t "comments-only ledger -> rc 2, NOT 0" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_COMMENTS" bash "$SELF" --collision --apk "$SELF"
  t "missing ledger, no artifact under test -> STILL rc 2 (this is what CI runs)" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_MISSING" bash "$SELF" --collision
  # V20: the repair must not redden a tree that is legitimately empty and says so.
  t "a DECLARED-empty ledger does NOT redden a record-only run (what CI makes)" 0 \
      env VERSION_IDENTITY_LEDGER="$LD_DECLARED" bash "$SELF" --collision
  # ...and the hatch must not become a bypass. Proven BLIND by mutation against this
  # seat's own repair on 2026-09-21 before this case existed.
  t "the DECLARED-empty hatch is REFUSED once an artifact is in hand" 2 \
      env VERSION_IDENTITY_LEDGER="$LD_DECLARED" bash "$SELF" --collision --apk "$SELF"
  # ...and through --scan too, which is the OTHER way an artifact enters evidence.
  #
  # ⚑ DRIVEN AS A PREDICATE, 2026-09-21, because the test that used to sit here
  # COULD NOT FAIL. It ran `--scan <empty dir>`, which returns rc 2 on its own for
  # having found no artifacts -- so the assertion was satisfied by the empty
  # directory and not by the hatch, and deleting the bound left this suite GREEN.
  # It also reached find_aapt2/find_apksigner, which made this guard the single
  # OUTSIDE-REPO entry in selftest-hermeticity-guard.sh while its own record claimed
  # 8/8. These drive the decision itself: delete the `|| [ "${nscan:-0}" -gt 0 ]`
  # clause and case 2 goes red immediately.
  t "hatch REFUSED when an artifact is under test"        0 hatch_refused declared-empty "/some.apk" 0
  t "hatch REFUSED when --scan puts artifacts in evidence" 0 hatch_refused declared-empty "" 3
  t "hatch REFUSED when BOTH"                             0 hatch_refused declared-empty "/some.apk" 3
  t "hatch ALLOWED with no artifact anywhere (V20: fresh tree CI)" 1 hatch_refused declared-empty "" 0
  t "hatch clause does not fire on a populated ledger"     1 hatch_refused rows "/some.apk" 3
  t "hatch clause does not fire on a missing ledger"       1 hatch_refused missing "/some.apk" 3
  # V20 again: a real record must still go green, or the gate gets switched off.
  t "a populated ledger still passes cleanly"       0 \
      env VERSION_IDENTITY_LEDGER="$LD_ROWS" bash "$SELF" --collision

  # ---- THE TWO EPISTEMIC STATES, which used to share one sentence.
  t "the record AFFIRMS these exact bytes"  0 \
      test "$(identity_record_state 9 "$SIGNER" "$SHA_HELD" "$LED_HELD")" = "affirmed"
  t "a code on NO row is 'absent', not affirmed" 0 \
      test "$(identity_record_state 10 "$SIGNER" "$SHA_OTHER" "$LED_HELD")" = "absent"
  t "a signer on NO row at all is 'absent-signer', not 'absent'" 0 \
      test "$(identity_record_state 9 "$SIGNER_DEBUG" "$SHA_HELD" "$LED_HELD")" = "absent-signer"
  t "a known signer at an UNKNOWN code is 'absent'" 0 \
      test "$(identity_record_state 11 "$SIGNER" "$SHA_HELD" "$LED_HELD")" = "absent"
  t "the collision case is 'other', not 'absent'" 0 \
      test "$(identity_record_state 9 "$SIGNER" "$SHA_OTHER" "$LED_HELD")" = "other"
  t "affirmed and absent do not print the same line" 0 \
      test "$(identity_record_state 9 "$SIGNER" "$SHA_HELD" "$LED_HELD")" != "$(identity_record_state 10 "$SIGNER" "$SHA_HELD" "$LED_HELD")"
  rm -rf "$LD_TMPDIR"

  # ---- R4 MINT TARGET. The nested-clone trap, in the shape it actually has.
  local LED_AMBIG
  LED_AMBIG="$(printf '2\t%s\t%s\tambiguous\ta\n2\t%s\t%s\tambiguous\tb\n9\t%s\t%s\tminted\tc' \
      "$SIGNER" "$SHA_HELD" "$SIGNER" "$SHA_OTHER" "$SIGNER" "$SHA_HELD")"
  t "THE NESTED-CLONE SHAPE: a tree declaring an AMBIGUOUS code is refused" 1 \
      check_mint_target 2 "$LED_AMBIG"
  t "a tree declaring a MINTED code is NOT refused (V20: the honest path)" 0 \
      check_mint_target 9 "$LED_AMBIG"
  t "a tree declaring an UNKNOWN code is accepted"  0 check_mint_target 10 "$LED_AMBIG"
  t "an unreadable build number is refused"         1 check_mint_target ""  "$LED_AMBIG"
  t "an empty record cannot refuse a mint target"   0 check_mint_target 2   ""

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
LEDGER_STATE="$(ledger_state "$LEDGER")"
case "$LEDGER_STATE" in
  rows|declared-empty) LEDGER_RAW="$(cat "$LEDGER")" ;;
  *)                   LEDGER_RAW="" ;;
esac
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

# ---- THE RECORD MUST BE THERE BEFORE ANYTHING IS SAID ABOUT IT.
# R2 and R3 are both assertions ABOUT A RECORD. With no record they are not clean,
# they are UNMEASURED -- and this guard's contract says so at the head of this file.
# Everything below this block is skipped when the record cannot be read, because the
# failure being repaired here was not a wrong answer, it was a CONFIDENT answer over
# nothing at all.
LEDGER_USABLE=1
case "$LEDGER_STATE" in
  missing)
    echo "-- ledger"
    echo "   CANNOT MEASURE: no ledger at $LEDGER."
    echo "   An absent record is NOT an empty one, and neither is a clean bill. R2 and"
    echo "   R3 assert things ABOUT this file; with no file there is nothing asserted."
    echo "   Restore it (it is tracked in git), or, for a tree that has genuinely never"
    echo "   built an artifact, create it with a line reading:"
    echo "       # NO-IDENTITIES-YET: <why this tree has minted nothing>"
    rc=2; LEDGER_USABLE=0 ;;
  unreadable)
    echo "-- ledger"
    echo "   CANNOT MEASURE: ledger exists but could not be read: $LEDGER"
    rc=2; LEDGER_USABLE=0 ;;
  malformed)
    echo "-- ledger"
    echo "   CANNOT MEASURE: $LEDGER is present and readable, and its rows DO NOT PARSE."
    echo "   This file is TAB-separated and every assertion here splits on tab. These"
    echo "   rows do not match the format, so they are invisible to R2, R3 and R4"
    echo "   while still LOOKING like a record on screen:"
    ledger_row_defects "$(ledger_body "$(cat "$LEDGER" 2>/dev/null)")" | head -8
    echo "   Most often an editor with expandtab, a paste through a terminal, or a"
    echo "   script writing this file with the wrong field index."
    echo "   Restore the tabs. Do NOT trust a green run over this file."
    rc=2; LEDGER_USABLE=0 ;;
  empty)
    echo "-- ledger"
    echo "   CANNOT MEASURE: ledger $LEDGER holds no identity, and does not say why."
    echo "   A record emptied by accident and a record deliberately empty look the same"
    echo "   from here. If this tree has minted nothing, SAY SO in the file:"
    echo "       # NO-IDENTITIES-YET: <why this tree has minted nothing>"
    rc=2; LEDGER_USABLE=0 ;;
  declared-empty)
    echo "-- ledger"
    # ⚑ BOUND TIGHTENED 2026-09-21. The rationale below says the hatch holds "only
    # where no artifact is under test" -- and the code keyed on $APK_ARG alone,
    # while --scan supplies artifacts through SCAN_DIRS. Measured: with this hatch
    # and `--scan /home/komada/work`, the run printed "measured: 0 identities, and
    # the file declares that deliberately" over 25 artifacts read off the disk.
    # Not a fail-open -- the byte-side consistency check still fired rc 1 -- but the
    # bound did not say what it claimed, and a bound that overstates itself is the
    # thing a later reader trusts instead of checking. Either path putting an
    # artifact in evidence now contradicts the declaration.
    if hatch_refused "$LEDGER_STATE" "$APK_ARG" "${#SCAN_DIRS[@]}"; then
      # ⚑ THE ESCAPE HATCH IS NOT A BYPASS, and it took a mutation run against this
      # seat's OWN repair to see that it was one. A declared-empty ledger silences
      # R2 exactly the way a MISSING one did: re-run the three real colliders with
      # `# NO-IDENTITIES-YET` in the file and the gate goes BLIND to all three again.
      # One line in a file would have re-opened the hole this repair closed.
      #
      # So the declaration is bounded by the thing that contradicts it. "This tree
      # has minted nothing" and "here is an artifact this tree minted" cannot both
      # be true, and when an artifact is under test the ARTIFACT is the measurement
      # and the declaration is the claim. The hatch stays open only where it is
      # actually needed -- a tree that has genuinely built nothing, which is the
      # record-consistency run CI makes and which has no artifact to pass.
      echo "   CANNOT MEASURE: the ledger declares itself empty (# NO-IDENTITIES-YET),"
      echo "   and yet this run has an artifact in evidence:"
      [ -n "$APK_ARG" ] && echo "     under test: $APK_ARG"
      [ "${#SCAN_DIRS[@]}" -gt 0 ] && echo "     scanning:   ${SCAN_DIRS[*]}"
      echo "   Those cannot both be true. A record that has minted nothing cannot"
      echo "   vouch for something that was minted. RECORD what exists and remove"
      echo "   the NO-IDENTITIES-YET line:"
      [ -n "$APK_ARG" ] && echo "     tool/assert_version_identity.sh --record $APK_ARG"
      rc=2; LEDGER_USABLE=0
    else
      echo "   measured: 0 identities, and the file declares that deliberately"
      echo "   (# NO-IDENTITIES-YET). Nothing to collide with YET -- not a clean record."
      echo "   This is the ONLY state in which an empty record is not a finding, and it"
      echo "   holds only while no artifact exists to contradict it."
    fi ;;
esac

if [ "$LEDGER_USABLE" -eq 1 ]; then
echo "-- R3 record consistency"
if check_ledger_consistency "$BODY"; then
  # Counted with the SAME tab split every assertion decides on. It used to be
  # counted with `awk NF` -- a WHITESPACE split -- so the number that reassured a
  # reader came from one parser and every number that decided came from another,
  # and only the reassuring one was ever printed. On a tab-mangled ledger that line
  # read "OK 14 recorded identities" while R2, R3 and R4 were each seeing zero.
  echo "   OK  $(printf '%s\n' "$BODY" | awk -F'\t' 'NF>=3' | wc -l) recorded identities, no unacknowledged collision"
else
  rc=1
fi
fi

if [ "$LEDGER_USABLE" -eq 1 ] && [ "$MODE" != "collision" ] && [ -f "$REPO_ROOT/pubspec.yaml" ]; then
  echo "-- R4 mint target (the code THIS TREE is about to mint)"
  if check_mint_target "$(pubspec_build_number "$(cat "$REPO_ROOT/pubspec.yaml")")" "$BODY"; then
    echo "   OK  +$(pubspec_build_number "$(cat "$REPO_ROOT/pubspec.yaml")") is not on record as ambiguous"
  else
    rc=1
  fi
fi

if [ -n "$APK_ARG" ] && [ "$LEDGER_USABLE" -eq 0 ]; then
  echo "-- R2 collision (the artifact under test against the record)"
  echo "   NOT RUN: there is no record to compare this artifact against."
  echo "   $APK_ARG"
  echo "   UNVERIFIED, never cleared. This is the state that used to print OK."
elif [ -n "$APK_ARG" ]; then
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
        # Two different states of knowledge; they used to share one sentence.
        case "$(identity_record_state "$c" "$s" "$h" "$BODY")" in
          affirmed)
            echo "   OK  versionCode $c is ON RECORD naming exactly these bytes, and no others." ;;
          absent-signer)
            echo "   NOT ON RECORD: signer ${s:0:16}… appears on NO row of the ledger at all."
            echo "       No collision -- and nothing affirmed either. This ledger records"
            echo "       RELEASE identities only (see its header), so a debug-signed"
            echo "       artifact belongs nowhere in it and must NOT be --recorded."
            echo "       It also cannot install over a release build: different certificate." ;;
          *)
            echo "   NEW versionCode $c is on NO ROW of the record. No collision --"
            echo "       and nothing affirmed either: the record has never seen this code."
            echo "       RECORD it before this artifact goes anywhere:"
            echo "         tool/assert_version_identity.sh --record $APK_ARG"
            echo "       and COMMIT the ledger. An unrecorded artifact is one nothing can"
            echo "       compare the NEXT build against." ;;
        esac
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
      # ---- CORROBORATION, both directions. Added 2026-09-21 because this seat
      # typed a PLAUSIBLE BUT INVENTED sha256 tail into the ledger while repairing
      # it, and caught it only by re-reading its own measurement. Nothing in this
      # file could have caught that: every assertion here compares the record
      # against ITSELF or against one artifact, so a row that corresponds to no
      # bytes anywhere is invisible to all three.
      #
      # ⚑ RULED 2026-09-21: THIS CHECK SHARES A PARSER WITH THE THING IT CORROBORATES,
      # AND IT DOES NOT NEED A SECOND ONE. The objection is real -- a value typed in
      # that also destroys the tab delimiters defeats this check in the same stroke
      # it defeats R2. The answer is NOT a duplicate text parser:
      #   - a second parser must agree with the first about what a row IS, so keeping
      #     the two in sync is a fresh defect surface, and the second would itself
      #     need validating. That regresses, it does not terminate.
      #   - the correct primitive is to REFUSE TO TRUST THE PARSE UNTIL ITS SHAPE IS
      #     VALIDATED. ledger_state() now asks the tab split itself whether it yielded
      #     three fields on every surviving row. A broken parser cannot hide from a
      #     check on its own output SHAPE, because the failure IS the shape.
      #   - measured: with the ledger tab-mangled the run exits 2 at the ledger gate
      #     and this block never executes. Corroboration is no longer reachable over
      #     a parse nobody validated.
      #   - and the divergence is gone at the source: the identity count printed by
      #     R3 now comes from the SAME tab split every assertion decides on.
      # WHERE THE REAL INDEPENDENCE LIVES, and it is not in the text: the BYTE side.
      # $inv is built by aapt2 + apksigner + sha256sum and shares nothing with the
      # ledger parser -- it still read artifacts off the disk on the mangled file.
      # This check's whole value is comparing those two populations, so its second
      # opinion is the bytes, and duplicating the text reader would add none.
      #
      # This REPORTS, it does not gate, and the distinction is deliberate: a
      # recorded artifact that has since been deleted or cleaned is the normal case,
      # not a defect, and failing on it would redden honest runs until someone
      # switched the gate off (V20). What it buys is that an uncorroborated row is
      # SAID OUT LOUD in the one mode whose whole job is reading real bytes, instead
      # of sitting in the record looking exactly like a measured one.
      if [ "${LEDGER_USABLE:-0}" -eq 1 ]; then
        corr=0; uncorr=0; uncorr_rows=""
        while IFS= read -r row; do
          [ -n "$row" ] || continue
          lc="$(printf '%s' "$row" | cut -f1)"; lh="$(printf '%s' "$row" | cut -f3)"
          [ -n "$lh" ] || continue
          if awk -F'\t' -v h="$lh" '$3==h {f=1} END{exit !f}' "$inv"; then
            corr=$((corr+1))
          else
            uncorr=$((uncorr+1)); uncorr_rows="$uncorr_rows   code $lc  ${lh:0:16}…"$'\n'
          fi
        done <<< "$BODY"
        echo "   corroborated: $corr of $((corr+uncorr)) recorded identities were found as real bytes under ${SCAN_DIRS[*]}"
        if [ "$uncorr" -gt 0 ]; then
          echo "   NOT corroborated by this scan ($uncorr) — normal if the artifact was cleaned,"
          echo "   and the ONLY signal there is if a row was never measured in the first place:"
          printf '%s' "$uncorr_rows"
        fi
        # And the other direction: bytes on disk that the record has never heard of.
        # Counted ONLY for signers the record actually tracks. This ledger is
        # release-only by its own header, so counting debug-signed artifacts here
        # would report a large number that is correct-by-design and means nothing --
        # noise in the one line a reader would use to find a real gap.
        unrec=0; unrec_rows=""
        while IFS= read -r dl; do
          [ -n "$dl" ] || continue
          dc="$(printf '%s' "$dl" | cut -f1)"; ds="$(printf '%s' "$dl" | cut -f2)"; dh="$(printf '%s' "$dl" | cut -f3)"
          printf '%s\n' "$BODY" | awk -F'\t' -v s="$ds" '$2==s {f=1} END{exit !f}' || continue
          printf '%s\n' "$BODY" | awk -F'\t' -v h="$dh" '$3==h {f=1} END{exit !f}' \
            || { unrec=$((unrec+1)); unrec_rows="$unrec_rows   code $dc  ${dh:0:16}…"$'\n'; }
        done < <(sort -u -t"$(printf '\t')" -k3,3 "$inv")
        if [ "$unrec" -eq 0 ]; then
          echo "   unrecorded: none — every artifact on disk under a RECORDED signer is on a row"
        else
          echo "   ⚑ unrecorded: $unrec artifact(s) on disk under a RECORDED signer are on NO row."
          echo "   These are real bytes nothing can compare the next build against. --record them."
          printf '%s' "$unrec_rows"
        fi
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
