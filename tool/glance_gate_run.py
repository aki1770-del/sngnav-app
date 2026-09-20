#!/usr/bin/env python3
"""Runs HIE's glance gate over THIS app's declared state surfaces.

WHY THIS DRIVER EXISTS, and it is not a preference.
hie_glance_gate.py:74 is `SDK_COLORS = "/home/komada/flutter/packages/flutter/
lib/src/material/colors.dart"` -- a HARDCODED ABSOLUTE PATH to one laptop's
Flutter SDK, used to resolve `Colors.blueGrey.shade700` and friends into hex.
No CI runner has that path. Measured 2026-09-20 with the constant pointed at a
nonexistent file: the gate says `C3 FAIL: Flutter SDK colours.dart unreadable ->
cannot resolve shade names. UNMEASURED, not absence.` and exits 1. That is the
RIGHT behaviour and it is also why the gate, invoked as a subprocess, is RED on
every runner for a reason that has nothing to do with legibility.

Found by tool/selftest-hermeticity-guard.sh, which classified this app's own
wrapper OUTSIDE-REPO on exactly that read. It was not found by the author.

So the gate is IMPORTED, not forked. tool/hie_glance_gate.py stays byte-identical
to HIE's copy (md5 in tool/hie_glance_gate.SOURCE); this driver binds the one
environment-dependent constant from OUTSIDE and calls the gate's own check().
Every rule -- C1, C2, C3, C3b -- is HIE's code, unmodified. AAE does not edit
HIE's file, and a caller supplying a machine path is not an edit.

⛑ TOLD TO THE OWNER, not just worked around: while that constant is hardcoded,
this gate is unarmable by ANY caller that does not do what this file does. The
fix belongs in HIE's copy (read FLUTTER_ROOT / an argument / the env), and until
it lands, every future arming re-implements this. Named on the record.
"""
import os
import shutil
import sys
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get('GLANCE_GATE_ROOT') or os.path.dirname(HERE)

# file, class, rendered-pixel guard discharging C3b, why it is a state surface
DECLARATIONS = [
    ("lib/akita_map.dart", "_HerDot",
     "test/render_see/her_dot_glance_capture_test.dart",
     "her position: real fix vs mock vs degraded -- the states she must tell apart at a glance"),
]
if os.environ.get('GLANCE_GATE_EMPTY'):
    DECLARATIONS = []


def die(msg):
    print(f"GLANCE GATE: {msg}", file=sys.stderr)
    sys.exit(1)


def resolve_sdk_colors():
    """Find the SDK's material/colors.dart on THIS machine. Fail closed."""
    rel = os.path.join('packages', 'flutter', 'lib', 'src', 'material', 'colors.dart')
    explicit = os.environ.get('GLANCE_SDK_COLORS')
    if explicit:
        return explicit, 'GLANCE_SDK_COLORS'
    froot = os.environ.get('FLUTTER_ROOT')
    if froot and os.path.exists(os.path.join(froot, rel)):
        return os.path.join(froot, rel), 'FLUTTER_ROOT'
    exe = shutil.which('flutter')
    if exe:
        # <sdk>/bin/flutter -> <sdk>
        sdk = os.path.dirname(os.path.dirname(os.path.realpath(exe)))
        cand = os.path.join(sdk, rel)
        if os.path.exists(cand):
            return cand, f'which flutter -> {sdk}'
        # The layout above is <sdk>/bin/flutter. A runner may place the CLI
        # somewhere else entirely, and this seat cannot test a GitHub runner's
        # layout from here. So ASK FLUTTER where its root is rather than assume
        # a shape -- an assumption about someone else's machine is how the
        # hardcoded path in the gate happened in the first place.
        try:
            import json
            import subprocess
            out = subprocess.run([exe, '--version', '--machine'],
                                 capture_output=True, text=True, timeout=180)
            root = json.loads(out.stdout).get('flutterRoot')
            if root and os.path.exists(os.path.join(root, rel)):
                return os.path.join(root, rel), 'flutter --version --machine'
        except Exception as e:
            print(f"GLANCE GATE: asked `flutter --version --machine` and could not "
                  f"use the answer ({e.__class__.__name__}).", file=sys.stderr)
    return None, 'not found'


def load_gate(sdk_colors):
    path = os.environ.get('GLANCE_GATE_PY') or os.path.join(HERE, 'hie_glance_gate.py')
    if not os.path.exists(path):
        die(f"the gate is not at {path}. A guard that is not there guards nothing. "
            f"UNMEASURED, never cleared.")
    spec = importlib.util.spec_from_file_location('hie_glance_gate', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if not hasattr(mod, 'check') or not hasattr(mod, 'NA'):
        die(f"{path} does not expose check()/NA. This is not the gate this driver was written for.")

    # Bind the ONE environment-dependent constant from outside.
    #
    # ⛑ AND THE OBVIOUS WAY TO DO THIS DOES NOT WORK. `mod.SDK_COLORS = x`
    # alone changes NOTHING: the gate calls `load_material_palette()` with no
    # argument (hie_glance_gate.py:306 and :380) and that function's signature is
    # `def load_material_palette(path=SDK_COLORS)`, whose default was bound when
    # the module was DEFINED. Measured, not reasoned: with a fixture palette in
    # which blue.shade600 is #00FF00, the driver printed `palette from <fixture>`
    # and the gate still reported #1E88E5 from the hardcoded SDK path. The
    # provenance line was TRUE-LOOKING AND FALSE -- a success-shaped value, on a
    # runner it would have named a path it never read. Caught by testing the
    # binding instead of trusting it; author's own defect, recorded rather than
    # quietly repaired.
    mod.SDK_COLORS = sdk_colors
    mod.load_material_palette.__defaults__ = (sdk_colors,)

    # Now PROVE the binding took, rather than assume it. A palette that resolves
    # nothing is UNMEASURED, and must never reach a verdict.
    pal = mod.load_material_palette()
    if not pal:
        die(f"the palette at {sdk_colors} resolved no swatches. UNMEASURED, not absence.")
    if mod.load_material_palette.__defaults__[0] != sdk_colors:
        die("the gate's palette path could not be bound from outside. Refusing to "
            "report a verdict the gate did not actually compute from this palette.")
    return mod, pal


def main():
    sdk, how = resolve_sdk_colors()
    if not sdk or not os.path.exists(sdk):
        die("could not find the Flutter SDK's material/colors.dart, so shade names "
            "cannot be resolved. UNMEASURED, not absence. Set GLANCE_SDK_COLORS or "
            "FLUTTER_ROOT, or put `flutter` on PATH. Refusing to report a verdict.")
    print(f"GLANCE GATE: palette from {sdk}  (via {how})")

    gate, pal = load_gate(sdk)
    print(f"GLANCE GATE: {len(pal)} swatch shade(s) resolved from it.")
    if not DECLARATIONS:
        die("the declaration list is EMPTY. Zero checks is UNMEASURED, never a clean run.")

    rc = 0
    for f, cls, guard, why in DECLARATIONS:
        fp = os.path.join(ROOT, f)
        if not os.path.exists(fp):
            die(f"declaration names {f}, which does not exist. A stale declaration is a "
                f"success-shaped value.")
        src = open(fp, encoding='utf-8').read()
        if f"class {cls} " not in src and f"class {cls}<" not in src:
            die(f"declaration names class {cls} in {f}, which does not declare it. "
                f"A declaration that names nothing FAILS.")
        gp = os.path.join(ROOT, guard)
        print(f"--- {cls}  ({f})  -- {why}")
        ok, lines = gate.check(fp, cls, guard=gp)
        for l in lines:
            print(l)
        verdict = ("PASS" if ok is True
                   else "N/A -> FAIL (named, unmeasurable)" if ok is gate.NA else "FAIL")
        print("VERDICT:", verdict)
        if ok is not True:
            rc = 1
    print(f"GLANCE GATE: {len(DECLARATIONS)} declared state surface(s) checked.")
    return rc


if __name__ == '__main__':
    sys.exit(main())
