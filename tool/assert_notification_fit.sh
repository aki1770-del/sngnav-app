#!/usr/bin/env bash
# Ongoing-drive notification fit gate — THE BUDGET IS A WIDTH, NOT A CHARACTER COUNT.
#
# WHY THIS EXISTS (2026-09-24, AAE).
#
#   app_localizations.dart carried one width rule, in a comment:
#   "Keep this under ~45 characters in EN". It was written after a REAL
#   truncation: an English body ran off the collapsed shade and she was shown
#   "...Tap here, then .." — losing the half that tells her how to END it,
#   which is the half the dignity boundary rests on.
#
#   The UNIT of that rule is wrong, and that is what this gate fixes. "Under
#   ~45 characters in EN" cannot see a Japanese string at all: the ja body was
#   22 characters — half the stated limit — and renders WIDER than the
#   38-character English one, because a full-width CJK glyph is about two Latin
#   ones. A character count passes strings a row cannot hold.
#
#   WHETHER THE OLD ja STRING ACTUALLY TRUNCATED IS UNSETTLED, and this gate
#   does not pretend otherwise. HIE measured a real shade screenshot and put
#   the usable run at 755px (an expand-chevron overlapped the text rows),
#   making the 805px ja body overflow. AAE then measured a real truncating row
#   on the one attached device (API 30 AVD, 1080x2340, 440dpi, ja-JP): face
#   ~38-39px, usable run x=57..1013 — about 956px — where that same string
#   is ~838px and FITS. The two captures DIFFER, both are real, and neither is
#   HER phone. So the budget below is the NARROWER of the two, deliberately:
#   sitting under a budget we are unsure of costs a few glyphs, and going over
#   one costs her the half of the sentence that says how to end the drive.
#
#   A Flutter widget/golden test cannot close this: the collapsed notification
#   is drawn by the Android system shade, not by our tree. So the measurement
#   is done here, on the advance widths of the fonts the shade uses.
#
# WHAT IT CHECKS: the rendered width of driveNotificationTitle and
#   driveNotificationBody, in ja and en, read FROM lib/l10n/app_localizations.dart
#   (never a copy — a copy is how the sibling test came to guarantee a string we
#   did not ship).
#
# WHAT IT IS NOT — stated because a guard that oversells itself is worse than none:
#   This is a CALCULATION, not a capture. The budget below comes from HIE's
#   calibrated read of a real shade screenshot (text origin x=180; the
#   expand-chevron bbox overlaps both text rows, so the usable run is 755px, not
#   the ~795px the truncated system rows suggest; both rows calibrate to a 37px
#   face). It has NOT been confirmed against HER phone, and the LOCK SCREEN —
#   the condition these words actually name — has never been looked at at all
#   (geolocator sets VISIBILITY_PRIVATE, BackgroundNotification.java:71).
#   A pass here means "fits by measurement", never "seen".
#
# Usage:  tool/assert_notification_fit.sh [--self-test]
# Exit:   0 = every string fits | 1 = a string overflows, or the instrument is
#         not available (this gate FAILS CLOSED: an unmeasurable string is not
#         a passing one).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L10N="${L10N_PATH:-$SCRIPT_DIR/../lib/l10n/app_localizations.dart}"

python3 - "$L10N" "${1:-}" <<'PY'
import re, sys, os

L10N, MODE = sys.argv[1], sys.argv[2]

# --- the instrument -----------------------------------------------------------
# FAIL CLOSED. A missing font or a missing PIL must never read as "fits".
try:
    from PIL import ImageFont
except Exception as e:
    print(f"FAIL: cannot measure — Pillow is not importable ({e}).", file=sys.stderr)
    print("      An unmeasurable string is NOT a passing string.", file=sys.stderr)
    sys.exit(1)

CJK_CANDIDATES = [
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
]
LATIN_CANDIDATES = [
    os.path.expanduser("~/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf"),
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]

def pick(cands, what):
    for c in cands:
        if os.path.exists(c):
            return c
    print(f"FAIL: cannot measure — no {what} font found. Tried:", file=sys.stderr)
    for c in cands:
        print(f"        {c}", file=sys.stderr)
    sys.exit(1)

CJK, LATIN = pick(CJK_CANDIDATES, "CJK"), pick(LATIN_CANDIDATES, "Latin")
PX = 37                      # calibrated face size of both shade text rows
BODY_BUDGET_PX = 755.0       # usable run for the body row (chevron overlaps it)
TITLE_BUDGET_PX = 676.0      # the title row stops short of the chevron

# --- SECOND FIELD, added 2026-09-25 (AAE) -------------------------------------
# WHY: on 2026-09-25 this gate returned OK at 93.1% for a body that was CUT on a
# real row — 「画面オフでも警告。終了はタップ→停…」, 17 of 19 characters, severing
# 停止 mid-word. 停止 is the only way she ends the drive. A whole-string budget
# cannot catch that: a string can sit under the budget the gate believes in and
# still lose its tail on the row she is actually holding, and the tail is the
# half that matters.
#
# So this field asks a different question, and it asks it about the WORD:
# at the narrowest run we have ever actually observed truncating, is the stop
# word still wholly on screen?
#
# BODY_BUDGET_PX above is DELIBERATELY UNCHANGED. Widening or narrowing the
# budget to settle an argument about a string is how a measurement stops being
# one. This adds a check; it retunes nothing.
OBSERVED_CUT_PX = 629.0      # the 17-char prefix that DID fit on the truncating row
STOP_WORD = {"ja": "停止", "en": "Stop"}

def width(text, path):
    f = (ImageFont.truetype(path, PX, index=0) if path.endswith(".ttc")
         else ImageFont.truetype(path, PX))
    return f.getlength(text)

# --- read the SHIPPED strings from source, never a copy ------------------------
def read_pair(src, getter):
    """Extract the ja and en literals of `String get <getter> => _ja ? 'x' : 'y';`"""
    m = re.search(
        r"String\s+get\s+" + getter + r"\s*=>\s*_ja\s*\?\s*'((?:[^'\\]|\\.)*)'"
        r"\s*:\s*'((?:[^'\\]|\\.)*)'\s*;", src, re.S)
    if not m:
        print(f"FAIL: could not read `{getter}` from {L10N}.", file=sys.stderr)
        print("      The gate reads the shipped source; if its shape changed, "
              "fix the gate rather than deleting it.", file=sys.stderr)
        sys.exit(1)
    return m.group(1), m.group(2)

def check(label, ja, en, budget, failures):
    for lang, text, font in (("ja", ja, CJK), ("en", en, LATIN)):
        px = width(text, font)
        pct = 100.0 * px / budget
        verdict = "OK" if px <= budget else "OVERFLOWS"
        line = (f"  {label:<24} {lang}  {px:7.1f}px  {pct:5.1f}% of {budget:.0f}"
                f"  {verdict}   {text}")
        print(line)
        if px > budget:
            failures.append(
                f"{label} [{lang}] is {px:.0f}px against a {budget:.0f}px row "
                f"({pct:.1f}%) — she is shown a truncated instruction: {text!r}")

if MODE == "--self-test":
    # The fixture is the REAL pre-2026-09-24 ja body. It is 22 characters — well
    # under the old "~45 characters" rule — and it overflowed. If this gate ever
    # accepts it, the gate has reverted to counting characters.
    OLD_JA = '画面を消していても警告します。終了はタップ。'
    # The SHIPPED body. Updated 2026-09-25 with the string itself: this is the
    # instrument's fixture, NOT the budget. The budget constant above was
    # deliberately left alone — the string was cut on a real row while this
    # gate said 93.1% OK, and the honest response to that is a shorter string,
    # never a wider budget.
    NEW_JA = '位置情報を使用中。タップ→停止。'
    ok = 0
    total = 0
    for name, s, expect_reject in (("old ja body (22 chars, overflowed)", OLD_JA, True),
                                   ("new ja body", NEW_JA, False)):
        total += 1
        px = width(s, CJK)
        rejected = px > BODY_BUDGET_PX
        good = rejected == expect_reject
        ok += good
        print(f"self-test {total} {'PASS' if good else 'FAIL'} "
              f"({name}: {px:.0f}px -> {'rejected' if rejected else 'accepted'}, "
              f"expected {'rejected' if expect_reject else 'accepted'})")
    total += 1
    n = len(OLD_JA)
    char_rule_would_pass = n < 45
    print(f"self-test {total} {'PASS' if char_rule_would_pass else 'FAIL'} "
          f"(the retired character rule accepts the overflowing string: "
          f"{n} chars < 45 -> {char_rule_would_pass}) "
          f"— this is the gap this gate exists to close")
    ok += char_rule_would_pass
    print(f"SELF-TEST: {ok}/{total} PASS")
    sys.exit(0 if ok == total else 1)

src = open(L10N, encoding="utf-8").read()
failures = []
print(f"Ongoing-drive notification fit ({PX}px face, measured advance widths):")
check("driveNotificationTitle", *read_pair(src, "driveNotificationTitle"),
      TITLE_BUDGET_PX, failures)
check("driveNotificationBody", *read_pair(src, "driveNotificationBody"),
      BODY_BUDGET_PX, failures)

# --- the stop word must survive the cut, not merely be present ----------------
print("\nStop word survives the narrowest observed row "
      f"({OBSERVED_CUT_PX:.0f}px):")
bja, ben = read_pair(src, "driveNotificationBody")
for lang, text, font in (("ja", bja, CJK), ("en", ben, LATIN)):
    word = STOP_WORD[lang]
    # longest prefix that fits the observed run -- what she would actually read
    visible = ""
    for ch in text:
        if width(visible + ch, font) > OBSERVED_CUT_PX:
            break
        visible += ch
    survives = word in visible
    cut = "" if visible == text else "…"
    print(f"  {lang}  {'OK' if survives else 'CUT OFF':<8} shows: {visible}{cut}")
    if not survives:
        failures.append(
            f"driveNotificationBody [{lang}] loses {word!r} at "
            f"{OBSERVED_CUT_PX:.0f}px — she would read {visible + cut!r}, which "
            f"never names the control that ends the drive")

if failures:
    print("\nFAIL: a notification string overflows the collapsed shade:", file=sys.stderr)
    for f in failures:
        print(f"  - {f}", file=sys.stderr)
    print("\n  The tail is what gets cut, and the tail is how she ends the drive.",
          file=sys.stderr)
    sys.exit(1)
print("\nPASS: every notification string fits by measurement "
      "(NOT a device capture — see the header).")
PY
