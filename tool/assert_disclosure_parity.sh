#!/usr/bin/env bash
# Manifest <-> disclosure parity gate — every permission we HOLD, she is TOLD.
#
# WHY THIS EXISTS (2026-09-24, AAE).
#
#   tool/assert_manifest_perms.sh asks "is the permission DECLARED?" — it was
#   built after a release shipped with INTERNET and ACCESS_FINE_LOCATION
#   missing, and it is good at that question. It never opens the privacy
#   policy, so it cannot ask the opposite question, and the opposite question
#   is the one that failed:
#
#   On 2026-09-24 the ongoing-drive foreground service landed. It added
#   FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION to the manifest. The
#   IN-APP disclosure was updated in the same change-set. The PRIVACY POLICY —
#   the document Play Console requires, the one she is pointed at before she
#   consents — was not. It went on saying, in both languages, "location is used
#   only while the app is on screen" at the exact moment that stopped being
#   true, and its permission table went on listing four permissions while the
#   manifest declared six.
#
#   The policy had even left the instruction for this case in its own comment:
#   "if it is published without the removal landing, update this page's
#   permission list to match the manifest's actual state." The removal did not
#   land — it was reversed — and nobody executed the instruction. A note to the
#   future is not a loom. This is the loom.
#
# WHAT IT CHECKS: every live <uses-permission> in the app manifest is named in
#   BOTH language halves of docs/store/privacy_policy_ja.md. Both halves,
#   because the policy is one document in two tongues and a driver reads one of
#   them; a permission disclosed only in Japanese is undisclosed to the other
#   reader, and vice versa.
#
# WHAT IT DOES NOT CHECK — say so, rather than let a PASS be read as "honest":
#   whether the stated PURPOSE of a permission is true; whether the prose
#   around the table is true; the merged manifest; the debug/profile variants;
#   or whether the policy as published anywhere matches this file. It catches a
#   permission we hold and do not name. It cannot catch a permission we name
#   and describe wrongly — that is a read, not a grep, and it stays human.
#
# Usage:  tool/assert_disclosure_parity.sh [--self-test]
# Exit:   0 = every declared permission is disclosed in both halves | 1 = not.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${MANIFEST_PATH:-$SCRIPT_DIR/../android/app/src/main/AndroidManifest.xml}"
POLICY="${POLICY_PATH:-$SCRIPT_DIR/../docs/store/privacy_policy_ja.md}"

run() {
python3 - "$1" "$2" <<'PY'
import sys, re, xml.etree.ElementTree as ET

manifest, policy = sys.argv[1], sys.argv[2]
A = '{http://schemas.android.com/apk/res/android}name'
T = '{http://schemas.android.com/tools}node'

try:
    root = ET.parse(manifest).getroot()
except Exception as e:
    print(f"FAIL: manifest not parseable ({e})", file=sys.stderr); sys.exit(1)

def live(el):
    return (el.get(T) or '').strip().lower() not in ('remove', 'removeall')

# Direct children of <manifest> only: a <uses-permission> nested elsewhere
# grants nothing, so it is nothing to disclose either.
declared = [e.get(A) for e in root.findall('uses-permission')
            if live(e) and e.get(A)]

try:
    text = open(policy, encoding='utf-8').read()
except Exception as e:
    print(f"FAIL: policy not readable ({e})", file=sys.stderr); sys.exit(1)

# The document is one page in two tongues, split at the English heading.
m = re.search(r'^#\s+Privacy Policy.*\(English\)\s*$', text, re.M)
if not m:
    print("FAIL: could not find the English half's heading in the policy.",
          file=sys.stderr)
    print("      Parity cannot be claimed over a document whose halves cannot "
          "be told apart.", file=sys.stderr)
    sys.exit(1)
halves = {'ja': text[:m.start()], 'en': text[m.start():]}

# A permission counts as disclosed where its SHORT NAME appears outside an HTML
# comment — comments are notes to us, never to her.
def visible(s):
    return re.sub(r'<!--.*?-->', '', s, flags=re.S)

missing = []
print(f"Declared permissions ({len(declared)}) vs privacy-policy disclosure:")
for perm in declared:
    short = perm.rsplit('.', 1)[-1]
    where = [h for h in ('ja', 'en') if short in visible(halves[h])]
    mark = 'OK ' if len(where) == 2 else 'MISSING'
    print(f"  {mark:7} {short:32} disclosed in: {', '.join(where) or 'NEITHER HALF'}")
    if len(where) != 2:
        absent = [h for h in ('ja', 'en') if h not in where]
        missing.append((short, absent))

if missing:
    print("\nFAIL: the app holds a permission the privacy policy does not name:",
          file=sys.stderr)
    for short, absent in missing:
        print(f"  - {short}: absent from the {' and '.join(absent)} half", file=sys.stderr)
    print("\n  She reads one of these halves before she consents. A permission "
          "we hold\n  and do not name is a consent she did not give.", file=sys.stderr)
    sys.exit(1)
print("\nPASS: every declared permission is named in both halves.")
PY
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  MF='<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">'
  cat > "$tmp/m_two.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
</manifest>
EOF
  cat > "$tmp/m_one.xml" <<EOF
$MF
<uses-permission android:name="android.permission.INTERNET"/>
</manifest>
EOF
  # A policy naming INTERNET in both halves and FOREGROUND_SERVICE in neither —
  # the REAL shape of the 2026-09-24 drift.
  cat > "$tmp/p_drift.md" <<'EOF'
# プライバシーポリシー
| INTERNET | 通信のため |
# Privacy Policy — sngnav-app (English)
| INTERNET | networking |
EOF
  # Named only in the ja half: undisclosed to the English reader.
  cat > "$tmp/p_ja_only.md" <<'EOF'
# プライバシーポリシー
| INTERNET | 通信のため |
| FOREGROUND_SERVICE | 走行中 |
# Privacy Policy — sngnav-app (English)
| INTERNET | networking |
EOF
  # Named only inside an HTML comment: a note to us, not a disclosure to her.
  cat > "$tmp/p_comment_only.md" <<'EOF'
# プライバシーポリシー
| INTERNET | 通信のため |
<!-- FOREGROUND_SERVICE -->
# Privacy Policy — sngnav-app (English)
| INTERNET | networking |
<!-- FOREGROUND_SERVICE -->
EOF
  cat > "$tmp/p_good.md" <<'EOF'
# プライバシーポリシー
| INTERNET | 通信のため |
| FOREGROUND_SERVICE | 走行中 |
# Privacy Policy — sngnav-app (English)
| INTERNET | networking |
| FOREGROUND_SERVICE | during a drive |
EOF
  pass=0; total=0
  check() { total=$((total+1)); local rc=0
    run "$tmp/$1" "$tmp/$2" >/dev/null 2>&1 || rc=1
    if [[ "$rc" == "$3" ]]; then echo "self-test $total PASS ($4)"; pass=$((pass+1));
    else echo "self-test $total FAIL ($4: expected rc=$3, got rc=$rc)"; fi; }
  check m_two.xml p_drift.md        1 "the real 2026-09-24 drift: declared, disclosed nowhere -> rejected"
  check m_two.xml p_ja_only.md      1 "disclosed in ja only -> rejected (the en reader was not told)"
  check m_two.xml p_comment_only.md 1 "named only inside an HTML comment -> rejected"
  check m_two.xml p_good.md         0 "disclosed in both halves -> accepted"
  check m_one.xml p_good.md         0 "policy may say MORE than the manifest holds -> accepted"
  echo "SELF-TEST: $pass/$total PASS"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

run "$MANIFEST" "$POLICY"
