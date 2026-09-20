#!/usr/bin/env python3
"""HIE glance gate - a surface that distinguishes SAFETY STATES must distinguish
them on a channel that survives the loss of colour.

WHY, written before the act (OPS-070(B)). Measured 2026-09-12 on
SNGNav example/lib/main.dart `_WeatherMarker`: the tri-state hazard model is
CORRECT in logic and BI-STATE in appearance. The three states render as three
circles of the same size whose fills sit at WCAG contrast 1.08-1.17:1 against
one another - a 3.0:1 floor. Rendered and SEEN this turn: with colour removed,
`hazardous`, `unknown` and `notHazardous` are one identical grey disc. Colour is
the first channel lost to glare, to peripheral vision, to a sun-washed panel and
to colour-vision deficiency, and it was the ONLY channel carrying the difference
between "there is ice" and "the road is fine".

THE RULE
  C1  A state surface must differ on at least one NON-COLOUR channel
      (shape, size, or border). Colour contrast alone is insufficient,
      because colour is the channel that dies first.
  C2  The ABSENCE state (unknown / unmeasured) must not be luminance-
      confusable with the CLEAR state. CLAUDE.md D3/D4: the surface resolves
      toward "she is told the road was not measured", never toward "looks clear".
  C3  If the gate cannot find the construct it checks, it FAILS.
      An empty match is UNMEASURED, never absence.
      (memory: gh-search-issues-false-negative-2026-08-19,
               gate-block-is-not-length-2026-09-04)

WHAT THIS GATE CANNOT SEE - the load-bearing half (HIE bylaws 2):
  - It reads SOURCE, not pixels. It cannot see a surface occluded at runtime,
    a theme override, an opacity animation, or a parent that tints its child.
  - It does not measure comprehension. Discriminable != understood. No human
    has looked at these markers under a timed glance; that study is owed.
  - It knows nothing of the panel: physical size, DPI, viewing distance,
    sunlight legibility and the IVI's own gamma are all outside it.
  - Luminance contrast is a proxy for peripheral discriminability, not a
    measurement of it.
  - It does not know WHICH colour encodes state. A widget with many colours and
    many sizes passes C1 trivially. This is a NECESSARY condition, not a
    sufficient one: it catches "colour is the only channel", not "the right
    thing is salient".
  - It reads only literal colours. A colour arriving from a theme, a variable
    or a named constant outside the class body is invisible to it, and colours
    with alpha < 0xF0 are skipped as non-fills.
  - It renders NO safety-standard verdict. ISO 26262 -> AAA, ISO 21448 -> FSE.
  - It does not judge whether a SIZE difference is large enough to see at a
    glance: 20 px against 22 px counts as a size channel. The eye judges that.

FIXED 2026-09-13 (board C-30) - two fail-open paths, measured by AAE, confirmed
in code by ORS, reproduced by HIE with minimal fixtures before the fix:
  - C2 turned a pair below the floor into a WARN, exit 0, whenever C1 passed.
    A warning that does not interrupt is not a halt (V8); a green build that
    hides a failure violates Jidoka (V87). A sub-floor pair now FAILS. Because
    this gate cannot tell a decorative colour from a state colour, it cannot
    show that the absence and clear states are apart, and ambiguity routes to
    FAIL (V16). A pair that carries no state may be declared with
    --accept-pair 'A/B=reason'; every acceptance prints in the verdict, a
    reason is required, and a declaration naming a pair the gate did not find
    FAILS (a stale acceptance is a success-shaped value, V14).
  - C1 read the width inside Border.all(...) / BorderSide(...) as a widget
    size, so two same-size circles differing only in border width passed.
    Widths inside border and radius calls are no longer extents.
  - Consequence, recorded against this seat's own work: SNGNav
    example/lib/main.dart _WeatherMarker (b14986e, HIE's own 2026-09-12 fix)
    passed only through the WARN path - hazard #B71C1C against clear #0D47A1
    at 1.314:1. It now FAILS until rendered, judged and either changed or
    declared with a reason.
  - A --sweep now FAILS a decorative multi-colour widget whose colours sit
    below the floor. That is the price of fail-closed, and why arming this gate
    needs a per-file declaration list rather than a bare sweep.

Owner: HIE (hmi-interface-engineer).
"""
import re, sys, os

SDK_COLORS = "/home/komada/flutter/packages/flutter/lib/src/material/colors.dart"
FLOOR = 3.0          # WCAG 2.1 non-text UI component contrast minimum
ABSENCE = ("unknown", "unmeasured", "unassessed", "stale", "absent")
CLEAR   = ("nothazardous", "clear", "ok", "safe", "normal", "good")

def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def luminance(hexs):
    h = hexs.lstrip('#')
    return (0.2126 * lin(int(h[0:2], 16)) + 0.7152 * lin(int(h[2:4], 16))
            + 0.0722 * lin(int(h[4:6], 16)))

def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def load_material_palette(path=SDK_COLORS):
    """Resolve Colors.<swatch>.shade<N> from the SDK ON DISK, never from memory."""
    if not os.path.exists(path):
        return None
    src = open(path, encoding='utf-8').read()
    # BLINDNESS FOUND AND FIXED 2026-09-20, AND IT HAD BEEN HERE SINCE THIS
    # GATE WAS BUILT ON 2026-09-12. Every Material swatch writes its 500 as
    # `500: Color(_<name>PrimaryValue)` -- a named constant, not a hex literal
    # -- so the pattern below resolved NOTHING for 19 swatches, and 500 is the
    # most-used shade in the SDK. The advisory card's attribution line is
    # `Colors.grey.shade500` at 2.424:1 on its surface, and this gate printed
    # its fill list without it and said nothing was missing. A palette that
    # resolves silently to nothing is the same class as an empty search read
    # as absence.
    prim = dict(re.findall(
        r'static const int _(\w+)PrimaryValue = 0x([0-9A-Fa-f]{8});', src))
    pal = {}
    for m in re.finditer(r'static const MaterialColor (\w+) = MaterialColor\(\s*\w+,\s*<int, Color>\{(.*?)\}\s*\);',
                         src, re.S):
        name, body = m.group(1), m.group(2)
        for s, v in re.findall(r'(\d+):\s*Color\(0x([0-9A-Fa-f]{8})\)', body):
            pal[f"{name}.shade{s}"] = '#' + v[2:]
        for s, ref in re.findall(r'(\d+):\s*Color\((_\w+)PrimaryValue\)', body):
            key = ref[1:]
            if key in prim:
                pal[f"{name}.shade{s}"] = '#' + prim[key][2:]
    return pal or None

def class_body(src, cls):
    m = re.search(r'class\s+' + re.escape(cls) + r'\b', src)
    if not m:
        return None
    i = src.find('{', m.end())
    if i < 0:
        return None
    d = 0
    for j in range(i, len(src)):
        if src[j] == '{': d += 1
        elif src[j] == '}':
            d -= 1
            if d == 0:
                return src[i:j + 1]
    return None

# Calls whose `width:` is a stroke or a radius, never a widget's extent.
NOT_EXTENT_CALLS = ('Border.all', 'BorderSide', 'Border', 'BorderRadius.circular',
                    'Radius.circular')


def strip_calls(src, names):
    """Remove every call to one of `names`, balanced parentheses included, so a
    width inside a border is not read as the size of the widget it decorates."""
    pat = re.compile(r'(?<![\w.])(?:' + '|'.join(re.escape(n) for n in names) + r')\(')
    out, i = [], 0
    while True:
        m = pat.search(src, i)
        if not m:
            out.append(src[i:])
            return ''.join(out)
        out.append(src[i:m.start()])
        depth, j = 0, m.end() - 1
        while j < len(src):
            if src[j] == '(':
                depth += 1
            elif src[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        i = j + 1


# A colour inside one of these is INK ON something, never a surface itself.
INK_CALLS = ('TextStyle', 'IconThemeData', 'DefaultTextStyle')


def colours_in(src, pal):
    out = []
    for sw, sh in re.findall(r'Colors\.(\w+)\.shade(\d+)', src):
        k = f"{sw}.shade{sh}"
        if k in pal: out.append((k, pal[k]))
    for v in re.findall(r'Color\(0x([0-9A-Fa-f]{8})\)', src):
        # Alpha matters: a transparent colour is not a fill, and counting one
        # produced a bogus contrast pair the first time this gate ran for real.
        if int(v[0:2], 16) < 0xF0:
            continue
        out.append(('0x' + v, '#' + v[2:]))
    return out


def calls_body(src, names):
    """The argument text of every call to one of `names`, parens balanced."""
    pat = re.compile(r'(?<![\w.])(?:' + '|'.join(re.escape(x) for x in names) + r')\(')
    out, i = [], 0
    while True:
        m = pat.search(src, i)
        if not m:
            return '\n'.join(out)
        depth, j = 0, m.end() - 1
        while j < len(src):
            if src[j] == '(':
                depth += 1
            elif src[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.append(src[m.end():j])
        i = j + 1


def analyse(body, pal):
    # INK IS SEPARATED FROM FILL SINCE 2026-09-20, AND THE REASON RUNS AGAINST
    # THIS GATE. On `AdvisoryCards` it reported a C2 pair #616161/#B71C1C at
    # 1.061:1 as a sub-floor FAIL. Both are TEXT colours --
    # `TextStyle(color: Colors.grey.shade700)` and
    # `TextStyle(color: Colors.red.shade900)` -- which never sit side by side
    # as two state surfaces, because neither IS a surface. A gate that cries
    # wolf is switched off, and a switched-off gate protects nothing (HIE-3).
    #
    # This makes C2 compare FEWER pairs, so where the check went is stated in
    # the output rather than left to be discovered: an ink's ground is a
    # RENDER fact a static reader cannot know, so inks are listed and marked
    # N/A HERE -- measured nothing, never a pass -- and the 4.5:1 text floor
    # on them is measured from sampled pixels by the rendered floor guard,
    # sngnav-app test/widgets/advisory_card_contrast_floor_test.dart.
    inks = colours_in(calls_body(body, INK_CALLS), pal)
    fills = colours_in(strip_calls(body, INK_CALLS), pal)
    # non-colour channels
    shapes = set(re.findall(r'BoxShape\.\w+', body)) | set(re.findall(r'shape:\s*(?:const\s+)?(\w+)\(', body))
    shapes |= set(re.findall(r'(\w+Border)\(\)', body))
    # Extents only: a border's width is a stroke, and counting it let two
    # same-size circles pass C1 on a 3 px vs 4 px border (C-30).
    sizes = set(re.findall(r'(?:width|height|size):\s*([0-9.]+)',
                           strip_calls(body, NOT_EXTENT_CALLS)))
    borders = set(re.findall(r'Border\.all\(', body))
    return fills, shapes, sizes, borders, inks

NA = 'N/A'   # measured nothing - never report this as a pass



# ---------------------------------------------------------------------------
# C3b - THE SCOPE ASSERTION. Added 2026-09-20 after an RCA the Chair ordered on
# D18, and it is an EXTENSION OF C3, not a second gate. The re-entrancy test was
# taken first (CLAUDE.md s11 test 3) and it came back positive: C3 already says
# "If the gate cannot find the construct it checks, it FAILS. An empty match is
# UNMEASURED, never absence." That principle was implemented at four sites - the
# SDK palette, the file, the class name, and a stale --accept-pair - and EVERY
# ONE of them is a FAILED LOOKUP: I searched for a named thing and it was not
# there. None of them is an ABSENT LOOKUP: there is paint here I never searched
# for. An absent lookup has no site at which to fail, so C3 could not reach it.
#
# WHAT IT COST HER, measured this turn and reproducible from the logs beside
# this file. On sngnav-app `lib/widgets/advisory_cards.dart` at d09afa7d the
# gate was pointed at `AdvisoryCards` (:84) and reported 5 fills, 2 distinct.
# The card her eyes actually read is painted by `_AdvisoryCard` (:430), and on
# that class this gate returns `fills found: 0 (0 distinct) []` - because every
# fill arrives through `_severityColor(...)` (:447, :476, :482), a TOP-LEVEL
# function at :653, outside every class body. Zero fills and one fill are the
# same state in this program (`len(uniq) < 2` -> N/A), and under --sweep an N/A
# class was `continue` - not printed, not counted, invisible. The only backstop,
# `checked == 0`, needs EVERY class in the file to be N/A. One measurable
# sibling masked the class that paints the card. Measured: with the one pair
# this gate could see unified, --sweep exits 0 and prints "1 state surface(s)
# checked, 0 failing" while `Opacity(opacity: 0.55)` (:542), `_severityColor`
# (:653) and `Colors.grey.shade500` (:536) are all still in the file. Five
# severity words at 1.843-2.393:1 and an English hazard card with every word
# between 1.567:1 and 3.767:1 sat under that green for eight days.
#
# AND THE BOUND WAS ALREADY WRITTEN DOWN. This module's own docstring names
# "an opacity animation, or a parent that tints its child" and "a colour
# arriving from a theme, a variable or a named constant outside the class body".
# Both defects are literally in that list. A docstring has no exit code, and it
# prints only on `usage` - so a caller who invokes the gate CORRECTLY never sees
# it. The disclosure was addressed to a reader; the verdict was addressed to a
# build. C3b moves the disclosure into the verdict.

PAINT_KEYS = ('color', 'backgroundColor', 'fillColor', 'fill', 'surfaceTintColor',
              'shadowColor', 'foregroundColor', 'barrierColor', 'cursorColor')
PAINT_POS = re.compile(r'(?<![\w])(?:' + '|'.join(PAINT_KEYS) + r')\s*:\s*([^,\n)]+)')
# Every one of these changes the PAINTED pixel without changing any colour
# literal, so a static reader of the source cannot derive what lands on glass.
COMPOSITING = ('Opacity(', '.withOpacity(', '.withValues(', '.withAlpha(',
               'ColorFiltered(', 'BackdropFilter(', 'Color.lerp(', 'FadeTransition(',
               'AnimatedOpacity(', 'ShaderMask(')
# A paint value starting with one of these IS a literal this gate can evaluate.
LITERAL_PAINT = re.compile(r'^\s*(?:const\s+)?(?:Colors\.|Color\(0x|k[A-Z])')


def top_level_names(src):
    """Identifiers declared at column 0 - functions, getters and constants that
    live OUTSIDE every class body and are therefore outside `class_body`."""
    out = set()
    out |= set(re.findall(r'^(?:Color|Colors)\s+(\w+)\s*\(', src, re.M))
    out |= set(re.findall(r'^(?:final|const)\s+(?:Color\s+)?(\w+)\s*=', src, re.M))
    out |= set(re.findall(r'^\w[\w<>, ?]*\s+(\w+)\s*\([^)]*\)\s*(?:=>|\{)', src, re.M))
    return out


def scope_report(src, cls, body):
    """C3b. What of this file's PAINT lies outside the region measured?

    Returns a list of (code, message). A non-empty list means this gate has
    rendered a verdict over a surface it does not reach, and that is a FAIL
    unless a rendered-pixel guard is registered for the file."""
    f = []

    # C3b-1 A swatch token the palette did not resolve. This is C3's own rule
    # ("an empty match is UNMEASURED, never absence") applied to the palette,
    # where it had never been applied. `Colors.grey.shade500` is written
    # `Color(_greyPrimaryValue)` in the SDK; before 861ba8ae this gate resolved
    # NOTHING for 19 swatches and printed its fill list without saying so.
    pal = load_material_palette() or {}
    unresolved = sorted({f"Colors.{a}.shade{b}" for a, b in
                         re.findall(r'Colors\.(\w+)\.shade(\d+)', src)
                         if f"{a}.shade{b}" not in pal})
    if unresolved:
        f.append(("C3b-1 UNRESOLVED SWATCH",
                  f"{len(unresolved)} swatch token(s) in this file resolved to NOTHING and were "
                  f"silently dropped from the fill list: {unresolved}. An empty match is "
                  f"UNMEASURED, never absence (C3)."))

    # C3b-2 A fill produced by a CALL the gate cannot evaluate. This is the one
    # that hid the whole card: `color: _severityColor(advisory.severity)`.
    tl = top_level_names(src)
    calls = {}
    for v in PAINT_POS.findall(body):
        v = v.strip()
        if LITERAL_PAINT.match(v):
            continue
        m = re.match(r'([A-Za-z_]\w*)\s*\(', v)
        if m:
            calls.setdefault(m.group(1), 0)
            calls[m.group(1)] += 1
    if calls:
        named = ', '.join(f"{k}() x{v}" + (" [DEFINED OUTSIDE EVERY CLASS BODY]" if k in tl else "")
                          for k, v in sorted(calls.items()))
        f.append(("C3b-2 PAINT FROM A CALL",
                  f"a paint position in `{cls}` takes its colour from a call this gate cannot "
                  f"evaluate: {named}. The fill is not a literal, so it is NOT in the fill list "
                  f"above, and `fills found: 0` reads exactly like `there is no paint here`."))

    # C3b-3 Compositing. The painted pixel is not the source colour.
    comp = sorted({t for t in COMPOSITING if t in body})
    if comp:
        f.append(("C3b-3 COMPOSITING IN THE PAINT PATH",
                  f"{comp} changes what lands on glass without changing any colour literal. "
                  f"Every contrast figure this gate prints is computed from the literal, so it "
                  f"is a figure about the RECIPE, not about the PAINT."))

    # C3b-4 A sibling class in the same file that paints, when only one was
    # measured. `AdvisoryCards` was measured; `_AdvisoryCard` paints the card.
    sibs = []
    for other in re.findall(r'^class\s+(\w+)', src, re.M):
        if other == cls:
            continue
        ob = class_body(src, other)
        if ob and PAINT_POS.search(ob):
            sibs.append(other)
    if sibs:
        f.append(("C3b-4 UNMEASURED SIBLING THAT PAINTS",
                  f"this file also declares {sibs}, which paint and were not measured by this "
                  f"check. A verdict on one class is not a verdict on the file."))
    return f


def rendered_guard_ok(path):
    """A registered rendered-pixel guard discharges C3b - but a declaration that
    names nothing is a success-shaped value (the --accept-pair discipline), so
    the file must exist AND must actually sample pixels."""
    if not os.path.exists(path):
        return False, f"--rendered-guard {path}: no such file. A guard that does not exist guards nothing."
    g = open(path, encoding='utf-8').read()
    if not re.search(r'toByteData|toImage|getPixel|readAsBytes|RawImage|rgba|byteData', g):
        return False, (f"--rendered-guard {path}: this file samples no pixels. It cannot discharge a "
                       f"bound about what lands on glass.")
    return True, f"--rendered-guard {path}: exists and samples pixels."


def check(path, cls, verbose=True, accept=None, guard=None):
    """returns (ok, lines); ok is True, False, or NA when the class is not a
    state surface. NA is not a pass: a sweep skips it, a named check fails it.
    `accept` maps frozenset({'#AAAAAA', '#BBBBBB'}) -> reason for a sub-floor
    pair the caller declares carries no state; each one prints in the output."""
    accept = accept or {}
    out = []
    pal = load_material_palette()
    if pal is None:
        return False, ["C3 FAIL: Flutter SDK colours.dart unreadable -> cannot resolve "
                       "shade names. UNMEASURED, not absence."]
    if not os.path.exists(path):
        return False, [f"C3 FAIL: source not found: {path}"]
    src = open(path, encoding='utf-8').read()
    body = class_body(src, cls)
    if body is None:
        return False, [f"C3 FAIL: class `{cls}` not found in {path}. "
                       "The gate could not measure what it exists to check."]
    # C3b RUNS BEFORE ANY VERDICT. The gate states what it does not reach
    # BEFORE it states what it found, because the eight days of D18 were spent
    # reading a confident fill list that was missing the class doing the paint.
    scope = scope_report(src, cls, body)
    discharged = False
    if guard is not None:
        gok, gmsg = rendered_guard_ok(guard)
        out.append(f"  C3b guard       : {gmsg}")
        if not gok:
            return False, out + ["C3b FAIL: the registered rendered-pixel guard does not hold."]
        discharged = True
    if scope:
        out.append(f"  C3b SCOPE       : {len(scope)} region(s) of this file's PAINT lie OUTSIDE "
                   f"what this check measured.")
        for code, msg in scope:
            out.append(f"      {code}: {msg}")
        if not discharged:
            return False, out + [
                "C3b FAIL: this gate reads SOURCE, not pixels, and the paint above is outside "
                "its reach. It will NOT render a contrast verdict over a region it cannot see. "
                "Discharge with --rendered-guard <test that samples the painted pixels>, or "
                "narrow the check to a class whose fills are all literals. "
                "UNMEASURED, never cleared."]
        out.append("      -> DISCHARGED by the rendered-pixel guard above, which measures the "
                   "PAINT. The figures below remain figures about the RECIPE.")
    fills, shapes, sizes, borders, inks = analyse(body, pal)
    uniq = sorted({h for _, h in fills})
    out.append(f"  fills found     : {len(fills)} ({len(uniq)} distinct) {uniq}")
    out.append(f"  shape tokens    : {sorted(shapes) or 'NONE'}")
    out.append(f"  size values     : {sorted(sizes) or 'NONE'}")
    uink = sorted({h for _, h in inks})
    if uink:
        out.append(f"  inks found      : {len(inks)} ({len(uink)} distinct) {uink}")
        out.append("      -> N/A HERE, NOT A PASS: an ink's ground is a render fact this "
                   "static gate cannot know. The 4.5:1 text floor on these is measured "
                   "from sampled pixels by the rendered floor guard.")
    else:
        out.append("  inks found      : NONE")
    if len(uniq) < 2:
        # `fills found: 0` and `this widget paints one colour` were the SAME
        # state until 2026-09-20, and under --sweep both were silent. A class
        # that PAINTS and yields no measurable fill is not "not a state
        # surface" - it is a state surface this gate cannot read.
        if PAINT_POS.search(body):
            msg = (f"`{cls}` occupies {len(re.findall(PAINT_POS, body))} paint position(s) "
                   f"and yields {len(uniq)} measurable fill(s). It PAINTS and this gate "
                   f"cannot read it.")
            if discharged:
                # The rendered guard measured the PAINT. This gate still
                # measured nothing, and N/A is never a pass (C3).
                return NA, out + [f"C3b N/A: {msg} The registered rendered-pixel guard carries "
                                  f"this surface. THIS gate has measured nothing here."]
            return False, out + [f"C3b FAIL: {msg} That is UNMEASURED, never "
                                 f"`not a state surface`."]
        return NA, out + [f"N/A: fewer than 2 distinct fills in `{cls}`; this is not a state "
                          "surface. NOT a pass - this gate has measured nothing here."]
    ok = True
    # C1 - non-colour channel
    nonclr = (len(shapes) > 1) or (len(sizes) > 1) or bool(borders and len(shapes) >= 1 and len(sizes) > 1)
    if nonclr:
        out.append("  C1 PASS: states differ on a non-colour channel (shape and/or size).")
    else:
        ok = False
        out.append("  C1 FAIL: every state uses the SAME shape and the SAME size. "
                   "COLOUR IS THE ONLY CHANNEL, and colour is the channel that dies "
                   "in glare, in peripheral vision and in colour-vision deficiency.")
    # C2 - luminance separation. FAIL-CLOSED since C-30: a sub-floor pair is a
    # FAIL whatever C1 found, unless the caller declared, with a reason, that
    # the pair carries no state.
    below, accepted, present = [], [], set()
    for i in range(len(uniq)):
        for j in range(i + 1, len(uniq)):
            r = contrast(uniq[i], uniq[j])
            key = frozenset((uniq[i], uniq[j]))
            present.add(key)
            reason = accept.get(key)
            if r >= FLOOR:
                tag = 'ok'
            elif reason:
                tag = f'BELOW {FLOOR} - ACCEPTED BY DECLARATION: {reason}'
                accepted.append((r, uniq[i], uniq[j], reason))
            else:
                tag = f'BELOW {FLOOR}'
                below.append((r, uniq[i], uniq[j]))
            out.append(f"  contrast {uniq[i]} vs {uniq[j]} = {r:.3f}:1 {tag}")
    stale = [k for k in accept if k not in present]
    for k in stale:
        ok = False
        out.append(f"  C3 FAIL: --accept-pair names {'/'.join(sorted(k))}, a pair this gate did not "
                   "find. A declaration about nothing is a success-shaped value; remove or correct it.")
    if below:
        ok = False
        w = min(below)
        channel = ("a non-colour channel exists, but this gate cannot tell a decorative colour from "
                   "a state colour, so it cannot show the absence and clear states are apart"
                   if nonclr else "and no non-colour channel: with colour gone these states are ONE OBJECT")
        out.append(f"  C2 FAIL: {len(below)} pair(s) below {FLOOR}:1, weakest {w[1]}/{w[2]} at "
                   f"{w[0]:.3f}:1; {channel}. Ambiguity routes to FAIL. Render it and look; declare a "
                   "pair that carries no state with --accept-pair 'A/B=reason'.")
    elif accepted:
        out.append(f"  C2 PASS WITH {len(accepted)} DECLARED ACCEPTANCE(S) - each is the caller's "
                   "claim, printed above, and refutable by a render.")
    return ok, out

def selftest():
    """Prove the gate FAILS on the real defect before anyone trusts a PASS."""
    import tempfile
    defect = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hazardous ? Colors.red.shade700
            : unknown ? Colors.blueGrey.shade600 : Colors.blue.shade700,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.ac_unit, color: Colors.white, size: 24),
    );
  }
}
'''
    fixed = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    switch (v) {
      case A: return SizedBox(width: 52, height: 52, child: DecoratedBox(
          decoration: ShapeDecoration(color: Color(0xFFB71C1C), shape: _TriBorder())));
      case B: return Container(width: 46, height: 46, decoration: BoxDecoration(
          color: Color(0xFFFFC107), shape: BoxShape.circle,
          border: Border.all(color: Color(0xFF212121), width: 4)));
      case C: return Container(width: 30, height: 30, decoration: BoxDecoration(
          color: Color(0xFF0D47A1), shape: BoxShape.circle));
    }
  }
}
'''
    # C-30 fail-open path 1: the only non-colour difference is a border width.
    border_only = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    if (degraded) {
      return Container(decoration: BoxDecoration(color: Colors.grey.shade900,
          shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade900, width: 4)));
    }
    return Container(decoration: BoxDecoration(color: Colors.blue.shade600,
        shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade900, width: 3)));
  }
}
'''
    # C-30 fail-open path 2: a shape difference excused a 1.390:1 pair.
    subfloor = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    if (unknown) {
      return Container(width: 22, height: 22, decoration: BoxDecoration(
          color: Colors.blue.shade400, shape: BoxShape.rectangle));
    }
    return Container(width: 22, height: 22, decoration: BoxDecoration(
        color: Colors.blue.shade600, shape: BoxShape.circle));
  }
}
'''
    # sngnav-app bd6ebc4 _HerDot, the surface this gate last cleared: every pair
    # it can see is above the floor, so it needs no declaration.
    her_dot = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    if (degraded) {
      return Container(width: 34, height: 34, decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade900, width: 4)));
    }
    if (isMock) {
      return Container(width: 20, height: 20, decoration: BoxDecoration(
          color: Colors.amber.shade50, shape: BoxShape.rectangle,
          border: Border.all(color: Colors.grey.shade900, width: 3)));
    }
    return Container(width: 22, height: 22, decoration: BoxDecoration(
        color: Colors.blue.shade600, shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3)));
  }
}
'''
    # A decorative outline shared by both states sits below the floor against
    # one fill; the state fills themselves are 5.295:1 apart.
    decorative = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    if (unknown) {
      return Container(width: 40, height: 40, decoration: BoxDecoration(
          color: Color(0xFFFFC107), shape: BoxShape.rectangle,
          border: Border.all(color: Color(0xFF212121), width: 2)));
    }
    return Container(width: 24, height: 24, decoration: BoxDecoration(
        color: Color(0xFF0D47A1), shape: BoxShape.circle,
        border: Border.all(color: Color(0xFF212121), width: 2)));
  }
}
'''
    # 2026-09-20 BLINDNESS 1: shade500 is a named constant in the SDK, so this
    # gate resolved NOTHING for it and saw ONE fill here -- N/A, "not a state
    # surface" -- while the two states are 1.362:1 apart.
    shade500 = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    if (unknown) {
      return Container(width: 30, height: 30, decoration: BoxDecoration(
          color: Colors.grey.shade500, shape: BoxShape.rectangle));
    }
    return Container(width: 44, height: 44, decoration: BoxDecoration(
        color: Colors.grey.shade400, shape: BoxShape.circle));
  }
}
'''
    # 2026-09-20 BLINDNESS 2: two TEXT colours counted as state fills produced
    # a sub-floor pair that does not exist on any surface. The real fills here
    # are 5.7:1 apart and the widget is sound.
    ink_not_fill = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    if (bad) {
      return Container(width: 30, height: 30, color: Color(0xFFFFEBEE),
          child: Text('x', style: TextStyle(color: Colors.red.shade900)));
    }
    return Container(width: 44, height: 44, decoration: BoxDecoration(
        color: Color(0xFF1B5E20), shape: BoxShape.circle),
        child: Text('y', style: TextStyle(color: Colors.grey.shade700)));
  }
}
'''
    # 2026-09-20 C3b, THE D18 SHAPE, REPRODUCED. This is `advisory_cards.dart`
    # at d09afa7d in miniature: the measured class occupies three paint
    # positions and every one of them is a CALL to a top-level function, so
    # `fills found: 0` - and an Opacity in the paint path, and a sibling class
    # that paints. Before C3b this was `N/A: not a state surface`, silent under
    # --sweep. The two severity fills it hides are 1.84:1 apart.
    d18_shape = '''
class _WeatherMarker extends StatelessWidget {
  Widget build(BuildContext context) {
    final card = Container(width: 30, height: 30, decoration: BoxDecoration(
        color: _severityColor(s), border: Border.all(color: _severityColor(s))));
    return Container(color: _severityColor(s).withValues(alpha: 0.15),
        child: deEmphasize ? Opacity(opacity: 0.55, child: card) : card);
  }
}

class _Sibling extends StatelessWidget {
  Widget build(BuildContext context) {
    return Container(color: Color(0xFFB0BEC5), width: 8, height: 8);
  }
}

Color _severityColor(x) {
  switch (x) {
    case Sev.moderate: return Colors.amber.shade400;
    case Sev.severe: return Colors.orange.shade600;
  }
}
'''

    outline = {frozenset(('#0D47A1', '#212121')): 'outline shared by both states, carries no state'}
    stale = {frozenset(('#000000', '#FFFFFF')): 'a pair that is not in the widget'}
    # A guard that samples pixels, and one that only claims to.
    real_guard = tempfile.NamedTemporaryFile('w', suffix='.dart', delete=False)
    real_guard.write("void main(){ final d = await image.toByteData(); expect(d,isNotNull); }")
    real_guard.close()
    fake_guard = tempfile.NamedTemporaryFile('w', suffix='.dart', delete=False)
    fake_guard.write("void main(){ expect(widget.color, Colors.amber.shade400); }")
    fake_guard.close()
    cases = (
        ("REAL DEFECT 2026-09-12 (must FAIL)", defect, None, False),
        ("HIE'S OWN 2026-09-12 FIX (must FAIL since C-30: hazard/clear 1.314:1)", fixed, None, False),
        ("C-30 BORDER WIDTH ONLY (must FAIL C1)", border_only, None, False),
        ("C-30 SUB-FLOOR PAIR BESIDE A SHAPE CHANGE (must FAIL C2)", subfloor, None, False),
        ("sngnav-app bd6ebc4 _HerDot (must PASS)", her_dot, None, True),
        ("DECORATIVE PAIR, DECLARED WITH A REASON (must PASS)", decorative, outline, True),
        ("DECORATIVE PAIR, NOT DECLARED (must FAIL)", decorative, None, False),
        ("STALE DECLARATION (must FAIL)", her_dot, stale, False),
        ("2026-09-20 shade500 BLINDNESS (must FAIL: 1.362:1 pair this gate "
         "could not resolve until today)", shade500, None, False),
        ("2026-09-20 INK COUNTED AS FILL (must PASS: the only sub-floor pair "
         "was two TEXT colours, which are not surfaces)", ink_not_fill, None, True),
        ("2026-09-20 C3b THE D18 SHAPE - fill from a top-level call, an Opacity "
         "in the paint path, a sibling that paints (must FAIL; was N/A and "
         "SILENT under --sweep for eight days)", d18_shape, None, False),
    )
    rc = 0
    for label, body, accept, expect in cases:
        fp = tempfile.NamedTemporaryFile('w', suffix='.dart', delete=False)
        fp.write(body); fp.close()
        ok, lines = check(fp.name, '_WeatherMarker', accept=accept)
        os.unlink(fp.name)
        good = (ok is expect)
        print(f"[selftest] {label}: gate said {'PASS' if ok is True else 'FAIL'} -> "
              f"{'correct' if good else 'WRONG'}")
        for l in lines: print("     " + l)
        if not good: rc = 1
    # --- C3b assertions, each one a thing that was TRUE of this gate until today ---
    fp = tempfile.NamedTemporaryFile('w', suffix='.dart', delete=False)
    fp.write(d18_shape); fp.close()

    # (i) The mutant that proves C3b can fail. With scope_report neutered, the
    # D18 shape goes back to N/A -- not a FAIL -- which is exactly the state
    # that let advisory_cards.dart sit green for eight days.
    import builtins
    # C3b lives at TWO sites -- scope_report, and the paint-position check that
    # stops a painting class being reported as `not a state surface`. Neutering
    # one proved nothing; the first run of this mutant still said FAIL and told
    # me so. Both are neutered here, and only then does the fixture fall back to
    # the pre-2026-09-20 verdict.
    real_scope = scope_report
    real_paint = PAINT_POS
    globals()['scope_report'] = lambda *a, **k: []
    globals()['PAINT_POS'] = re.compile(r'(?!x)x')
    mutant_ok, _ = check(fp.name, '_WeatherMarker')
    globals()['scope_report'] = real_scope
    globals()['PAINT_POS'] = real_paint
    good = (mutant_ok is NA)
    print(f"[selftest] C3b MUTANT (both C3b sites neutered; the D18 shape must fall back to N/A, "
          f"proving C3b is what catches it): gate said "
          f"{'PASS' if mutant_ok is True else ('N/A' if mutant_ok is NA else 'FAIL')} -> "
          f"{'correct' if good else 'WRONG - C3b is not load-bearing here'}")
    if not good: rc = 1

    # (ii) A rendered-pixel guard discharges it.
    dok, _ = check(fp.name, '_WeatherMarker', guard=real_guard.name)
    print(f"[selftest] C3b DISCHARGED BY A PIXEL-SAMPLING GUARD (must not FAIL on C3b): "
          f"{'correct' if dok is not False else 'WRONG'}")
    if dok is False: rc = 1

    # (iii) A guard that samples no pixels is a success-shaped value and is refused.
    fok, flines = check(fp.name, '_WeatherMarker', guard=fake_guard.name)
    good = (fok is False and any('samples no pixels' in l for l in flines))
    print(f"[selftest] C3b GUARD THAT SAMPLES NO PIXELS (must be refused): "
          f"{'correct' if good else 'WRONG'}")
    if not good: rc = 1

    # (iv) A guard that does not exist is refused.
    nok, nlines = check(fp.name, '_WeatherMarker', guard='/nonexistent/guard.dart')
    good = (nok is False and any('no such file' in l for l in nlines))
    print(f"[selftest] C3b GUARD THAT DOES NOT EXIST (must be refused): "
          f"{'correct' if good else 'WRONG'}")
    if not good: rc = 1

    # (v) C3b-1: a swatch the palette cannot resolve is named, not dropped.
    real_pal = load_material_palette
    globals()['load_material_palette'] = lambda *a, **k: {}
    f1 = real_scope(d18_shape, '_WeatherMarker', class_body(d18_shape, '_WeatherMarker'))
    globals()['load_material_palette'] = real_pal
    good = any(c.startswith('C3b-1') for c, _ in f1)
    print(f"[selftest] C3b-1 UNRESOLVED SWATCH IS NAMED, NOT SILENTLY DROPPED: "
          f"{'correct' if good else 'WRONG'}")
    if not good: rc = 1
    os.unlink(fp.name); os.unlink(real_guard.name); os.unlink(fake_guard.name)

    try:
        parse_accept(['#0D47A1/#212121='])
        print("[selftest] AN ACCEPTANCE WITHOUT A REASON (must be refused): accepted -> WRONG")
        rc = 1
    except ValueError as e:
        print(f"[selftest] AN ACCEPTANCE WITHOUT A REASON (must be refused): refused -> correct ({e})")
    print("[selftest] " + ("the gate fires on every measured defect, including both C-30 fail-open "
                           "paths, and clears only what it can show." if rc == 0 else "GATE IS BROKEN."))
    return rc


def parse_accept(values):
    """'#AAAAAA/#BBBBBB=reason' -> {frozenset: reason}. A reason is required."""
    out = {}
    for v in values:
        pair, sep, reason = v.partition('=')
        cols = [c.strip().upper() for c in pair.split('/')]
        if (len(cols) != 2 or not all(re.fullmatch(r'#[0-9A-F]{6}', c) for c in cols)):
            raise ValueError(f"--accept-pair {v!r}: expected '#RRGGBB/#RRGGBB=reason'")
        if not sep or not reason.strip():
            raise ValueError(f"--accept-pair {v!r}: an acceptance without a reason is not accepted")
        out[frozenset(cols)] = reason.strip()
    return out

def sweep(path):
    src = open(path, encoding='utf-8').read()
    names = re.findall(r'^class\s+(\w+)', src, re.M)
    bad = []
    checked = 0
    for c in names:
        ok, lines = check(path, c)
        if ok is NA:
            # PRINTED, not silent. Before 2026-09-20 this was a bare `continue`,
            # so on advisory_cards.dart the class that paints the card never
            # appeared in the sweep output at all.
            print(f"  {c:30s} N/A (no paint found; measured nothing)")
            continue
        checked += 1
        print(f"  {c:30s} {'PASS' if ok else 'FAIL'}")
        if not ok:
            bad.append((c, lines))
    if checked == 0:
        print(f"SWEEP FAIL: {len(names)} classes, none of them a state surface. "
              "The gate measured nothing; that is UNMEASURED, not clean.")
        return 1
    for c, lines in bad:
        print(f"\n--- {c} ---")
        for l in lines:
            print(l)
    print(f"\nSWEEP: {checked} state surface(s) checked, {len(bad)} failing.")
    return 1 if bad else 0


if __name__ == '__main__':
    if '--selftest' in sys.argv:
        sys.exit(selftest())
    if '--sweep' in sys.argv:
        a = [x for x in sys.argv[1:] if not x.startswith('--')]
        sys.exit(sweep(a[0]))
    positional, declared, guard, argv = [], [], None, sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == '--accept-pair' and i + 1 < len(argv):
            declared.append(argv[i + 1]); i += 2; continue
        if argv[i].startswith('--accept-pair='):
            declared.append(argv[i].split('=', 1)[1]); i += 1; continue
        if argv[i] == '--rendered-guard' and i + 1 < len(argv):
            guard = argv[i + 1]; i += 2; continue
        if argv[i].startswith('--rendered-guard='):
            guard = argv[i].split('=', 1)[1]; i += 1; continue
        positional.append(argv[i]); i += 1
    if len(positional) < 2:
        print(__doc__)
        print("usage: hie-glance-gate.py <file.dart> <ClassName> [--accept-pair '#RRGGBB/#RRGGBB=reason' ...]"
              " [--rendered-guard <test.dart>]"
              "\n       hie-glance-gate.py --selftest | --sweep <file.dart>")
        sys.exit(2)
    try:
        accept = parse_accept(declared)
    except ValueError as e:
        print(f"HIE glance gate: {e}")
        sys.exit(2)
    ok, lines = check(positional[0], positional[1], accept=accept, guard=guard)
    print(f"HIE glance gate: {positional[1]} in {positional[0]}")
    for l in lines: print(l)
    # A class named for checking that turns out not to be a state surface is a
    # FAIL, not a pass: the caller asked a question this gate could not answer.
    verdict = "PASS" if ok is True else ("N/A -> FAIL (named, unmeasurable)" if ok is NA else "FAIL")
    if ok is True and accept:
        verdict += f" (with {len(accept)} declared acceptance(s), printed above)"
    print("VERDICT:", verdict)
    sys.exit(0 if ok is True else 1)
