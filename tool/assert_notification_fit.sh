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
# THE TEXT-SCALE AXIS, added 2026-09-25.
#
#   WHY: a screen review rendered the shipped body on an Android 14 emulator
#   at her width
#   (1080 px, 440 dpi) with the system text scale at 1.3. The collapsed row
#   read 「位置情報を使用中。タップ…」 and "Location in use. Tap, then St…".
#   停止 was gone from the Japanese row, and Stop was cut in the English one.
#   This gate had passed that string, because it only ever measured scale 1.0.
#   Her font scale is recorded nowhere. She is elderly, and Android 14 lets
#   the scale go to 2.0.
#   (The frames and UI dumps are kept with the project's review records, not
#   in this repository.)
#
#   THE ROW MODEL, and why it can be trusted this far. A truncating row draws
#   the longest prefix that fits, then an ellipsis. At scale 1.0 the prefix
#   that fitted was OBSERVED_CUT_PX (629 px), followed by one ellipsis, a
#   full-width glyph (ELLIPSIS_PX, 37 px at the calibrated face). So the row
#   holds OBSERVED_CUT_PX + ELLIPSIS_PX. At text scale s every glyph is s
#   times wider and the row is not, so a prefix P stays visible while
#       (width(P) + ELLIPSIS_PX) * s  <=  OBSERVED_CUT_PX + ELLIPSIS_PX.
#   At s = 1.0 that is exactly the check this gate already made (P <= 629).
#   Nothing already gated is loosened. The self-test proves the model on the
#   one observation that exists: at s = 1.3 it must reproduce the two rows the
#   review saw, character for character, or the self-test fails.
#
#   WHAT IT DOES NOT KNOW. Only 1.0 and 1.3 are observed. Scales above 1.3 are
#   a linear extrapolation. Android 14 scales large text by less than the
#   nominal factor (non-linear font scaling), so linear is the cautious
#   direction: it predicts a cut no later than the device makes one. No MIUI
#   shade, which is HER phone's, has been measured at any scale.
#
# Usage:  tool/assert_notification_fit.sh [--self-test]
# Exit:   0 = every string fits | 1 = a string overflows, or the instrument is
#         not available (this gate FAILS CLOSED: an unmeasurable string is not
#         a passing one).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
L10N="${L10N_PATH:-$SCRIPT_DIR/../lib/l10n/app_localizations.dart}"


python3 - "$L10N" "${1:-}" <<'PY'
import re, sys, os, shutil

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

def sdk_roboto_candidates():
    """Roboto from the Flutter SDK that is actually installed, wherever it is.

    Added 2026-09-25. This list used to name only ~/flutter, which exists on
    one developer's machine. A CI runner keeps its SDK elsewhere, so there the
    gate fell through to DejaVu: a different face, silently. FLUTTER_ROOT
    first, then the `flutter` on PATH, then ~/flutter. The same order the test
    support uses (test/render_see/render_see_env.dart, _sdkMaterialFonts).
    """
    roots = []
    if os.environ.get("FLUTTER_ROOT"):
        roots.append(os.environ["FLUTTER_ROOT"])
    fl = shutil.which("flutter")
    if fl:
        roots.append(os.path.dirname(os.path.dirname(os.path.realpath(fl))))
    roots.append(os.path.expanduser("~/flutter"))
    out = []
    for r in roots:
        p = os.path.join(r, "bin", "cache", "artifacts", "material_fonts",
                         "Roboto-Regular.ttf")
        if p not in out:
            out.append(p)
    return out

# DejaVu stays as the LAST resort, and the run says so when it is used. It is
# wider than Roboto, so under it a string can only look LONGER: a pass under
# DejaVu is a pass under Roboto, while a fail under DejaVu may not be real.
LATIN_CANDIDATES = sdk_roboto_candidates() + [
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
LATIN_IS_ROBOTO = os.path.basename(LATIN) == "Roboto-Regular.ttf"
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

# --- THIRD FIELD, added 2026-09-25: the text-scale axis -----------------------
# See the header. ELLIPSIS_PX is one full-width glyph at the calibrated face:
# the ellipsis a truncating row draws after the prefix. It is used for BOTH
# languages. For English that is stricter than Roboto's own ellipsis, which is
# the cautious direction, and it still reproduces the English row the review
# saw, exactly.
ELLIPSIS_PX = 37.0
SCALES = (1.0, 1.15, 1.3, 1.5, 1.8, 2.0)
OBSERVED_SCALES = {1.0: "observed (API 30 row)", 1.3: "observed (API 34 emulator, 2026-09-25)"}

_FONTS = {}
def width(text, path):
    if path not in _FONTS:
        _FONTS[path] = (ImageFont.truetype(path, PX, index=0) if path.endswith(".ttc")
                        else ImageFont.truetype(path, PX))
    return _FONTS[path].getlength(text)

def visible_at(text, font, scale, run_px=OBSERVED_CUT_PX):
    """What a truncating row shows of `text` at text scale `scale`.

    The longest prefix P with (width(P) + ELLIPSIS_PX) * scale <=
    run_px + ELLIPSIS_PX. At scale 1.0 this is width(P) <= run_px, the check
    this gate made before the axis existed.
    """
    limit = run_px + ELLIPSIS_PX
    shown = ""
    for ch in text:
        if (width(shown + ch, font) + ELLIPSIS_PX) * scale > limit:
            break
        shown += ch
    return shown

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

print(f"faces: CJK {CJK}")
print(f"       Latin {LATIN}"
      + ("" if LATIN_IS_ROBOTO else
         "   (NOT Roboto: the calibrated Latin face was not found; this face is"
         " wider, so an English pass holds and an English fail may not be real)"))

if MODE == "--self-test":
    ok = 0
    total = 0
    def report(good, text):
        global ok, total
        total += 1
        ok += bool(good)
        print(f"self-test {total} {'PASS' if good else 'FAIL'} ({text})")

    # The fixture is the REAL pre-2026-09-24 ja body. It is 22 characters — well
    # under the old "~45 characters" rule — and it overflowed. If this gate ever
    # accepts it, the gate has reverted to counting characters.
    OLD_JA = '画面を消していても警告します。終了はタップ。'
    # The SHIPPED body, as a fixture. Updated 2026-09-25 (twice) with the string
    # itself: this is the instrument's fixture, NOT the budget. The budget
    # constants above were deliberately left alone both times — each time the
    # string was cut on a real row, and the honest response to that is a
    # shorter string, never a wider budget.
    NEW_JA = 'タップ→「停止」で終了'
    NEW_EN = 'Tap, then Stop, to end.'
    for name, s, expect_reject in (("old ja body (22 chars, overflowed)", OLD_JA, True),
                                   ("new ja body", NEW_JA, False)):
        px = width(s, CJK)
        rejected = px > BODY_BUDGET_PX
        report(rejected == expect_reject,
               f"{name}: {px:.0f}px -> {'rejected' if rejected else 'accepted'}, "
               f"expected {'rejected' if expect_reject else 'accepted'}")
    n = len(OLD_JA)
    report(n < 45,
           f"the retired character rule accepts the overflowing string: "
           f"{n} chars < 45 -> {n < 45} — this is the gap this gate exists to close")

    # --- the text-scale axis, proven on the one observation that exists --------
    # The body that shipped before 2026-09-25, and the review's two rows of it
    # at text scale 1.3 on an Android 14 emulator at her width (1080 px,
    # 440 dpi).
    PRE_JA = '位置情報を使用中。タップ→停止。'
    PRE_EN = 'Location in use. Tap, then Stop.'
    SEEN_JA_13 = '位置情報を使用中。タップ'
    SEEN_EN_13 = 'Location in use. Tap, then St'
    got_ja = visible_at(PRE_JA, CJK, 1.3)
    report(got_ja == SEEN_JA_13,
           f"row model reproduces the observed ja row at 1.3: model {got_ja!r}, "
           f"seen {SEEN_JA_13!r}")
    got_en = visible_at(PRE_EN, LATIN, 1.3)
    if LATIN_IS_ROBOTO:
        report(got_en == SEEN_EN_13,
               f"row model reproduces the observed en row at 1.3: model {got_en!r}, "
               f"seen {SEEN_EN_13!r}")
    else:
        # A wider face may show LESS than the device did, never more.
        report(SEEN_EN_13.startswith(got_en),
               f"row model shows no more than the observed en row at 1.3 under a "
               f"non-Roboto face: model {got_en!r}, seen {SEEN_EN_13!r}")
    # The defect the scale-1.0 gate PASSED, and the axis catches.
    keeps_10 = STOP_WORD["ja"] in visible_at(PRE_JA, CJK, 1.0)
    keeps_13 = STOP_WORD["ja"] in visible_at(PRE_JA, CJK, 1.3)
    report(keeps_10 and not keeps_13,
           f"the previous ja body keeps 停止 at 1.0 ({keeps_10}) and loses it at "
           f"1.3 ({keeps_13}): the case a 1.0-only gate passed and a device showed cut")
    keeps_en_13 = STOP_WORD["en"] in visible_at(PRE_EN, LATIN, 1.3)
    report(not keeps_en_13,
           f"the previous en body loses Stop at 1.3 ({keeps_en_13} kept)")
    # The shipped body fixtures keep the word at every scale this gate checks.
    for lang, s, font in (("ja", NEW_JA, CJK), ("en", NEW_EN, LATIN)):
        lost = [sc for sc in SCALES if STOP_WORD[lang] not in visible_at(s, font, sc)]
        report(not lost,
               f"new {lang} body keeps {STOP_WORD[lang]!r} at every scale "
               f"{SCALES}: lost at {lost or 'none'}")
    print(f"SELF-TEST: {ok}/{total} PASS")
    sys.exit(0 if ok == total else 1)

src = open(L10N, encoding="utf-8").read()
failures = []
print(f"Ongoing-drive notification fit ({PX}px face, measured advance widths):")
tja, ten = read_pair(src, "driveNotificationTitle")
bja, ben = read_pair(src, "driveNotificationBody")
check("driveNotificationTitle", tja, ten, TITLE_BUDGET_PX, failures)
check("driveNotificationBody", bja, ben, BODY_BUDGET_PX, failures)

# --- the stop word must survive the cut, at every text scale -------------------
print("\nStop word survives a truncating row "
      f"({OBSERVED_CUT_PX:.0f}px prefix + {ELLIPSIS_PX:.0f}px ellipsis at 1.0, "
      "scaled):")
for lang, text, font in (("ja", bja, CJK), ("en", ben, LATIN)):
    word = STOP_WORD[lang]
    for sc in SCALES:
        shown = visible_at(text, font, sc)
        survives = word in shown
        cut = "" if shown == text else "…"
        basis = OBSERVED_SCALES.get(sc, "extrapolated")
        print(f"  {lang}  x{sc:<4} {'OK' if survives else 'CUT OFF':<8} "
              f"shows: {shown}{cut}   [{basis}]")
        if not survives:
            failures.append(
                f"driveNotificationBody [{lang}] loses {word!r} at text scale "
                f"{sc} ({basis}) — she would read {shown + cut!r}, which never "
                f"names the control that ends the drive")

# --- the title, reported per scale and NOT gated -------------------------------
# The title now carries "location in use". It is reported so a reader sees what
# survives, and it is not gated: no control lives in it. Its row model uses the
# title's own whole-row budget. At the top scales the Japanese title is cut
# inside 位置情報; that is a stated bound, not a pass.
print("\nTitle as a truncating row would show it (reported, not gated):")
for lang, text, font in (("ja", tja, CJK), ("en", ten, LATIN)):
    for sc in SCALES:
        shown = visible_at(text, font, sc, run_px=TITLE_BUDGET_PX - ELLIPSIS_PX)
        cut = "" if shown == text else "…"
        print(f"  {lang}  x{sc:<4} shows: {shown}{cut}")

if failures:
    print("\nFAIL: a notification string overflows the collapsed shade:", file=sys.stderr)
    for f in failures:
        print(f"  - {f}", file=sys.stderr)
    print("\n  The tail is what gets cut, and the tail is how she ends the drive.",
          file=sys.stderr)
    sys.exit(1)
print("\nPASS: every notification string fits by measurement, and the stop word "
      "survives at every checked text scale "
      "(NOT a device capture — see the header).")
PY
