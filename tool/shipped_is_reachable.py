#!/usr/bin/env python3
"""Nothing may be SHIPPED that code cannot REACH.

WHY (OPS-070(B), before the act). Root cause, taken from AGL's ondemandnavi and
verified against our own tree the same day:

  Its recipe installs `openjtalk`, its voice model and its dictionary; it ships
  `package/jtalk`; and `guidance_module.h:24` hardcodes `flite`. Six links
  resolve. The seventh -- the selection -- was never written, so a complete
  Japanese TTS stack rides every image and never speaks.

The cause is NOT that someone forgot (V18 forbids stopping at a person). It is
that a capability can be ADDED TO THE SHIPPED ARTIFACT WITHOUT ANYTHING
REQUIRING IT TO BE REACHABLE FROM CODE. Packaging and calling are separate
layers with no link between them.

The symptom-level countermeasure -- "a human listens at RC time" -- is V15's
WORST tier, *found downstream*. This is the *detected instantly* tier: it fails
the build the moment an unreachable artifact is declared.

Yokoten: run against ourselves it found `assets/tiles/gunma_offline.mbtiles`
committed 2026-08-30, 11 MB, absent from pubspec assets and unreferenced in
lib/ -- our own jtalk, one hour old.

Exit 0 = every declared asset is reachable · 1 = an unreachable asset ·
2 = UNMEASURED (could not read the inputs -- never treated as a pass).
"""
import os, re, subprocess, sys

# Legal files ship unread BY DESIGN -- a licence is an obligation to the reader,
# not a resource the code loads. Matched on the BASENAME PREFIX: measured
# 2026-08-30, a suffix test missed `LICENSE-SnGNavSymbols.txt` and produced a
# false positive on the second run of this very check.
def _is_legal(path: str) -> bool:
    b = os.path.basename(path).upper()
    return b.startswith(('LICENSE', 'LICENCE', 'NOTICE', 'COPYING'))

def main() -> int:
    if not os.path.isfile('pubspec.yaml'):
        print('UNMEASURED: no pubspec.yaml here'); return 2
    y = open('pubspec.yaml', encoding='utf-8').read()
    m = re.search(r'^\s*assets:\s*$(.*?)(?=^\s{0,4}\w[\w-]*:|\Z)', y, re.M | re.S)
    if not m:
        print('UNMEASURED: no assets: block found'); return 2
    declared = re.findall(r'^\s*-\s*(\S+)', m.group(1), re.M)
    if not declared:
        print('UNMEASURED: assets: block parsed empty'); return 2

    # Fonts are declared in their OWN pubspec section and are reached by NAME
    # through the theme, never by asset path. Measured 2026-08-30: the first
    # build of this check flagged SnGNavSymbols.ttf and its LICENSE as
    # unreachable. Both were false positives -- the font is declared at
    # `fonts:` and the licence ships unread by legal obligation. A gate that
    # cries wolf gets routed around (V20), so font assets are collected here
    # and excluded from both halves rather than left to misfire.
    font_assets = set(re.findall(r'^\s*-\s*asset:\s*(\S+)', y, re.M))

    src = subprocess.run(['grep', '-rh', '--include=*.dart', '', 'lib/'],
                         capture_output=True, text=True).stdout
    if not src.strip():
        print('UNMEASURED: read no Dart source under lib/'); return 2

    bad, checked = [], 0
    for a in declared:
        if _is_legal(a) or a in font_assets:
            continue
        checked += 1
        if a.endswith('/'):
            files = sorted(os.listdir(a)) if os.path.isdir(a) else []
            # a directory asset is reachable if the DIRECTORY or any member is named
            if a.rstrip('/') in src or any(f in src for f in files):
                continue
            bad.append((a, f'directory, {len(files)} files, neither path nor any member named in lib/'))
        else:
            if a in src or os.path.basename(a) in src:
                continue
            bad.append((a, 'neither full path nor basename appears in lib/'))

    # The other half: an artifact sitting in assets/ that is not declared at all.
    orphan = []
    for root, _dirs, files in os.walk('assets'):
        for f in files:
            p = os.path.join(root, f)
            if _is_legal(f) or p in font_assets:
                continue
            if any(p == d or (d.endswith('/') and p.startswith(d)) for d in declared):
                continue
            orphan.append(p)

    print(f'declared assets checked: {checked}   unreachable: {len(bad)}   '
          f'undeclared files under assets/: {len(orphan)}')
    for a, why in bad:
        print(f'  UNREACHABLE  {a}\n               {why}')
    for p in orphan:
        sz = os.path.getsize(p)
        print(f'  UNDECLARED   {p}  ({sz/1048576:.1f} MB) — in the tree, not in the bundle')
    if bad or orphan:
        print('\nNothing may be shipped that code cannot reach. Declare it and wire it,'
              '\nor remove it. An artifact with no path is weight, not a capability.')
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
