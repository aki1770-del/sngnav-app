#!/usr/bin/env bash
# Manifest + egress <-> disclosure parity gate — every permission we HOLD and
# every host we CONTACT, she is TOLD.
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
# WHY THE SECOND FIELD EXISTS (2026-09-24, FBR).
#
#   The permission half above returned PASS 8/8 on a policy in which four
#   sentences were false. The same change-set that added the foreground service
#   also added a FIFTH network destination — raw.githubusercontent.com, the
#   update check — and the policy went on asserting, four times in two tongues,
#   "these four flows are all of it" and "nothing else leaves the device".
#   Nothing bound a new network call to the document that enumerates network
#   calls, so the gate was green about permissions while the page was false
#   about egress.
#
#   A passing gate is evidence about the field the gate reads and nothing else.
#   This is that lesson made mechanical: "these N are all of it" is a TESTABLE
#   PREDICATE and was being treated as prose.
#
# WHAT IT CHECKS
#   (1) every live <uses-permission> in the app manifest, and
#   (2) every host reachable from a URL literal in the app's own Dart source,
#   is named in BOTH language halves of docs/store/privacy_policy_ja.md. Both
#   halves, because the policy is one document in two tongues and a driver reads
#   one of them; a thing disclosed only in Japanese is undisclosed to the other
#   reader, and vice versa.
#
# HOW EGRESS IS DECIDED — and why it is not a grep for "http".
#   A naive URL grep over lib/ reads SIX hosts here and is wrong about two:
#   api.weather.gov sits inside a comment, and github.com sits inside the
#   User-Agent string. A gate wrong on every clean run gets an exclusion list
#   bolted on to quiet it, and that exclusion list is where a future real egress
#   goes to die. So:
#     - Comments are stripped by a SCANNER, not a regex. Dart's '//' appears
#       inside every https:// literal in this repo; a regex comment-stripper
#       mangles the very strings it must read. Block comments nest.
#     - A literal is an egress target only if its value BEGINS with the scheme.
#       A URL embedded mid-string is a contact address, not a request target.
#   Deliberately NOT used as a signal: whether the file imports an HTTP client.
#   That would be a second control, but it can HIDE a real egress in a file that
#   fetches through a helper — and a gate must never err toward seeing less.
#
#   NOTHING IS SILENTLY DROPPED. Every URL literal found is printed with its
#   classification, so a wrong rejection is visible to the next reader instead
#   of being invisible by construction.
#
# THE FLOOR. A parse that yields ZERO permissions, or ZERO egress hosts, is a
#   FAILURE, never a pass. Before 2026-09-24 this script answered a
#   permission-less manifest with "PASS: every declared permission is named in
#   both halves" and exit 0 — a vacuous truth wearing a clearance, which is the
#   exact shape (an instrument returning success-shaped output on an operation
#   that did not happen) this gate exists to catch. Found by FBR in its own
#   instrument while refusing someone else's work.
#
# WHAT IT DOES NOT CHECK — say so, rather than let a PASS be read as "honest":
#   whether the stated PURPOSE of a permission or flow is true; whether the
#   prose around the tables is true; the merged manifest; the debug/profile
#   variants; or whether the policy as published anywhere matches this file.
#   ⚑ EGRESS BLIND SPOT, stated because a PASS must not be read as exhaustive:
#   it reads THIS APP'S OWN Dart source only. A host contacted from inside a pub
#   package is invisible to it — the NWS endpoint (api.weather.gov) is exactly
#   that case, reached through package:condition_aggregator, and appears in lib/
#   only in comments. NWS is disclosed in the policy today; this gate is not what
#   would notice if it stopped being.
#
# Usage:  tool/assert_disclosure_parity.sh [--self-test]
# Exit:   0 = every declared permission AND every egress host is disclosed in
#             both halves | 1 = not.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${MANIFEST_PATH:-$SCRIPT_DIR/../android/app/src/main/AndroidManifest.xml}"
POLICY="${POLICY_PATH:-$SCRIPT_DIR/../docs/store/privacy_policy_ja.md}"
LIBDIR="${LIB_PATH:-$SCRIPT_DIR/../lib}"

# ---------- shared: split the policy into halves, hide HTML comments ----------
read -r -d '' _PY_COMMON <<'PYCOMMON' || true
import sys, re

def halves_of(policy):
    try:
        text = open(policy, encoding='utf-8').read()
    except Exception as e:
        print(f"FAIL: policy not readable ({e})", file=sys.stderr); sys.exit(1)
    m = re.search(r'^#\s+Privacy Policy.*\(English\)\s*$', text, re.M)
    if not m:
        print("FAIL: could not find the English half's heading in the policy.",
              file=sys.stderr)
        print("      Parity cannot be claimed over a document whose halves "
              "cannot be told apart.", file=sys.stderr)
        sys.exit(1)
    return {'ja': text[:m.start()], 'en': text[m.start():]}

# Named inside an HTML comment is a note to us, never a disclosure to her.
def visible(s):
    return re.sub(r'<!--.*?-->', '', s, flags=re.S)
PYCOMMON

# ---------- field 1: permissions ----------
run() {
python3 - "$1" "$2" <<PY
$_PY_COMMON
import xml.etree.ElementTree as ET

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

halves = halves_of(policy)

# THE FLOOR. Zero declared permissions means the input was wrong, not that the
# app is clean. Saying PASS here is the vacuous-truth failure this gate exists
# to catch, and it used to say exactly that.
if not declared:
    print("FAIL: the manifest parsed but declares NO permissions.", file=sys.stderr)
    print("      That is a broken input, not a clean app. A parity claim over "
          "an empty\n      set is vacuously true and tells her nothing.",
          file=sys.stderr)
    sys.exit(1)

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
    sys.stdout.flush()
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

# ---------- field 2: egress ----------
run_egress() {
python3 - "$1" "$2" <<PY
$_PY_COMMON
import os

libdir, policy = sys.argv[1], sys.argv[2]

# Dart's '//' lives inside every https:// literal in this repo, so comments are
# removed by walking the source, never by a regex. Block comments nest in Dart.
def dart_strings(src):
    out, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1; i += 1; continue
        if c == '/' and i + 1 < n and src[i+1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i+1] == '*':
            depth, i = 1, i + 2
            while i < n and depth:
                if src[i] == '\n':
                    line += 1
                if src.startswith('/*', i):
                    depth += 1; i += 2; continue
                if src.startswith('*/', i):
                    depth -= 1; i += 2; continue
                i += 1
            continue
        raw = (c == 'r' and i + 1 < n and src[i+1] in '\'"')
        if c in '\'"' or raw:
            if raw:
                i += 1
            q = src[i]
            delim = q * 3 if src.startswith(q * 3, i) else q
            triple = len(delim) == 3
            i += len(delim)
            start, buf = line, []
            while i < n:
                if src[i] == '\n':
                    line += 1
                    if not triple:
                        break
                    buf.append(src[i]); i += 1; continue
                if not raw and src[i] == '\\\\':
                    buf.append(src[i:i+2]); i += 2; continue
                if src.startswith(delim, i):
                    i += len(delim); break
                buf.append(src[i]); i += 1
            out.append((start, ''.join(buf)))
            continue
        i += 1
    return out

SCHEME = re.compile(r'^(?:https?)://', re.I)
ANY    = re.compile(r'https?://', re.I)

def host_of(lit):
    rest = SCHEME.sub('', lit, count=1)
    host = re.split(r'[/?#]', rest, 1)[0]
    host = host.split('@')[-1].split(':')[0]
    return host

if not os.path.isdir(libdir):
    print(f"FAIL: Dart source root not readable ({libdir})", file=sys.stderr)
    sys.exit(1)

hosts, rejected, unresolved = {}, [], []
for root_dir, _, files in os.walk(libdir):
    for fn in sorted(files):
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root_dir, fn)
        rel = os.path.relpath(path, os.path.dirname(libdir.rstrip('/')))
        try:
            src = open(path, encoding='utf-8').read()
        except Exception as e:
            print(f"FAIL: unreadable Dart source {rel} ({e})", file=sys.stderr)
            sys.exit(1)
        for line, lit in dart_strings(src):
            if not ANY.search(lit):
                continue
            if not SCHEME.match(lit):
                # A URL embedded mid-string is a contact address (a User-Agent,
                # a docs pointer), not a request target. Printed, never hidden.
                rejected.append((rel, line, ANY.split(lit)[0][:28],
                                 host_of(lit[ANY.search(lit).start():]),
                                 'URL embedded mid-string, not a request target'))
                continue
            h = host_of(lit)
            if not h or '\$' in h:
                unresolved.append((rel, line, lit[:60]))
                continue
            hosts.setdefault(h, []).append(f"{rel}:{line}")

halves = halves_of(policy)

# THE FLOOR, same reasoning as the permission half: an empty result set is a
# broken input, not a clean app.
if not hosts and not unresolved:
    print("FAIL: scanned the Dart source and found NO egress host at all.",
          file=sys.stderr)
    print("      This app talks to the network. Zero is a broken scan, not a "
          "clean app,\n      and a parity claim over an empty set is vacuously "
          "true.", file=sys.stderr)
    sys.exit(1)

print(f"\nEgress hosts in app source ({len(hosts)}) vs privacy-policy disclosure:")
missing = []
for h in sorted(hosts):
    where = [x for x in ('ja', 'en') if h in visible(halves[x])]
    mark = 'OK ' if len(where) == 2 else 'MISSING'
    print(f"  {mark:7} {h:32} disclosed in: {', '.join(where) or 'NEITHER HALF'}")
    print(f"          {'; '.join(hosts[h])}")
    if len(where) != 2:
        missing.append((h, [x for x in ('ja', 'en') if x not in where]))

if rejected:
    print(f"  -- read and NOT counted as egress ({len(rejected)}):")
    for rel, line, _, h, why in rejected:
        print(f"     {rel}:{line}  {h}  ({why})")

if unresolved:
    sys.stdout.flush()
    print("\nFAIL: a URL literal whose HOST cannot be resolved statically:",
          file=sys.stderr)
    for rel, line, lit in unresolved:
        print(f"  - {rel}:{line}  {lit}", file=sys.stderr)
    print("\n  An unresolvable host is UNVERIFIED, never clear. It is reported "
          "rather than\n  dropped, because a host this gate cannot read is a "
          "host she was never told.", file=sys.stderr)
    sys.exit(1)

if missing:
    sys.stdout.flush()
    print("\nFAIL: the app contacts a host the privacy policy does not name:",
          file=sys.stderr)
    for h, absent in missing:
        print(f"  - {h}: absent from the {' and '.join(absent)} half", file=sys.stderr)
    print("\n  The page tells her these flows are all of them. One of them is "
          "not on the\n  page. An egress we make and do not name is a consent "
          "she did not give.", file=sys.stderr)
    sys.exit(1)
print("\nPASS: every egress host is named in both halves.")
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
  cat > "$tmp/m_none.xml" <<EOF
$MF
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

  # --- egress fixtures -------------------------------------------------------
  # The REAL 2026-09-24 shape: one disclosed host, one undisclosed update check.
  mkdir -p "$tmp/lib_drift"
  cat > "$tmp/lib_drift/a.dart" <<'EOF'
final u = Uri.parse('https://www.jma.go.jp/bosai/amedas/data/x.json');
final v = Uri.parse('https://raw.githubusercontent.com/o/r/main/u.json');
EOF
  # Same tree, policy naming BOTH — must clear.
  # A URL inside a // comment and inside a /* */ comment: not egress.
  mkdir -p "$tmp/lib_comment"
  cat > "$tmp/lib_comment/a.dart" <<'EOF'
final u = Uri.parse('https://www.jma.go.jp/x.json');
//   `GET https://api.weather.gov/alerts/active?point={lat},{lon}`
/* https://nested.example/a /* still comment */ https://also.example/b */
EOF
  # A URL embedded mid-string — the User-Agent shape: not egress.
  mkdir -p "$tmp/lib_embedded"
  cat > "$tmp/lib_embedded/a.dart" <<'EOF'
final u = Uri.parse('https://www.jma.go.jp/x.json');
const ua = '(sngnav-app, https://github.com/aki1770-del/sngnav)';
EOF
  # THE '//'-IN-STRING TRAP: a regex comment-stripper eats the URL itself and
  # reports a clean zero. Real code follows on the same line.
  mkdir -p "$tmp/lib_trap"
  cat > "$tmp/lib_trap/a.dart" <<'EOF'
final u = Uri.parse('https://raw.githubusercontent.com/o/r/u.json'); // fetch it
EOF
  # Host built by interpolation: unresolvable, must be reported not dropped.
  mkdir -p "$tmp/lib_interp"
  cat > "$tmp/lib_interp/a.dart" <<'EOF'
final u = Uri.parse('https://$host/alerts.json');
EOF
  mkdir -p "$tmp/lib_empty"
  cat > "$tmp/lib_empty/a.dart" <<'EOF'
final x = 1;
EOF
  cat > "$tmp/p_egress_none.md" <<'EOF'
# プライバシーポリシー
| INTERNET | 通信のため |
| FOREGROUND_SERVICE | 走行中 |
www.jma.go.jp
# Privacy Policy — sngnav-app (English)
| INTERNET | networking |
| FOREGROUND_SERVICE | during a drive |
www.jma.go.jp
EOF
  cat > "$tmp/p_egress_all.md" <<'EOF'
# プライバシーポリシー
| INTERNET | 通信のため |
| FOREGROUND_SERVICE | 走行中 |
www.jma.go.jp / raw.githubusercontent.com
# Privacy Policy — sngnav-app (English)
| INTERNET | networking |
| FOREGROUND_SERVICE | during a drive |
www.jma.go.jp / raw.githubusercontent.com
EOF

  pass=0; total=0
  check() { total=$((total+1)); local rc=0
    run "$tmp/$1" "$tmp/$2" >/dev/null 2>&1 || rc=1
    if [[ "$rc" == "$3" ]]; then echo "self-test $total PASS ($4)"; pass=$((pass+1));
    else echo "self-test $total FAIL ($4: expected rc=$3, got rc=$rc)"; fi; }
  checke() { total=$((total+1)); local rc=0
    run_egress "$tmp/$1" "$tmp/$2" >/dev/null 2>&1 || rc=1
    if [[ "$rc" == "$3" ]]; then echo "self-test $total PASS ($4)"; pass=$((pass+1));
    else echo "self-test $total FAIL ($4: expected rc=$3, got rc=$rc)"; fi; }

  check m_two.xml p_drift.md        1 "the real 2026-09-24 drift: declared, disclosed nowhere -> rejected"
  check m_two.xml p_ja_only.md      1 "disclosed in ja only -> rejected (the en reader was not told)"
  check m_two.xml p_comment_only.md 1 "named only inside an HTML comment -> rejected"
  check m_two.xml p_good.md         0 "disclosed in both halves -> accepted"
  check m_one.xml p_good.md         0 "policy may say MORE than the manifest holds -> accepted"
  check m_none.xml p_good.md        1 "FLOOR: zero permissions parsed -> rejected, never a vacuous PASS"

  checke lib_drift    p_egress_none.md 1 "the real egress drift: host contacted, policy names four -> rejected"
  checke lib_drift    p_egress_all.md  0 "same source, policy names both hosts -> accepted"
  checke lib_comment  p_egress_none.md 0 "URL in // and nested /* */ comments -> not egress"
  checke lib_embedded p_egress_none.md 0 "URL embedded mid-string (User-Agent) -> not egress"
  checke lib_trap     p_egress_none.md 1 "'//'-in-string TRAP: scanner still sees the host a regex would eat"
  checke lib_interp   p_egress_all.md  1 "host built by interpolation -> UNVERIFIED, reported not dropped"
  checke lib_empty    p_egress_all.md  1 "FLOOR: zero egress hosts found -> rejected, never a vacuous PASS"

  echo "SELF-TEST: $pass/$total PASS"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

rc=0
run "$MANIFEST" "$POLICY" || rc=1
run_egress "$LIBDIR" "$POLICY" || rc=1
exit "$rc"
