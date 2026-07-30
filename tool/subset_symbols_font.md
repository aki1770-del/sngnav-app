# Re-cutting `assets/fonts/SnGNavSymbols.ttf`

The bundled symbols subset backstops the symbol-class glyphs (⚠ ❄ ※ → ° …)
in HER-facing strings — glyphs the ja system font stack does not guarantee
(measured 2026-07-30: Noto Sans CJK JP lacks U+2744 ❄; the render-see
harness fonts lack U+26A0 ⚠). It is wired app-wide via
`ThemeData.fontFamilyFallback` in `lib/main.dart`.

`test/fonts/symbol_font_coverage_test.dart` re-derives the symbol inventory
from `lib/**` string literals on every run and fails when a new symbol is
not in the shipped font. When it fails, re-cut:

```bash
# 1. fontTools in a venv (any recent version)
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools

# 2. Subset DejaVu Sans to the inventory the failing test prints
#    (KEEP the existing 14 and ADD the new codepoints):
/tmp/fontenv/bin/pyftsubset /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
  --unicodes=U+00A9,U+00B0,U+00B1,U+00B5,U+00B7,U+00D7,U+03B2,U+2013,U+2014,U+2026,U+203B,U+2192,U+26A0,U+2744 \
  --output-file=assets/fonts/SnGNavSymbols.ttf \
  --layout-features='' --name-IDs='*'

# 3. RENAME the family (license requirement — the Bitstream Vera license
#    voids itself on modified fonts that keep the name; and Flutter must
#    resolve the family the theme names):
/tmp/fontenv/bin/python - <<'EOF'
from fontTools.ttLib import TTFont
f = TTFont('assets/fonts/SnGNavSymbols.ttf')
name = f['name']
for nid, val in [(1,'SnGNavSymbols'),(3,'SnGNavSymbols subset of DejaVu Sans'),
                 (4,'SnGNavSymbols'),(6,'SnGNavSymbols')]:
    name.setName(val, nid, 3, 1, 0x409)
name.names = [r for r in name.names
              if not (r.nameID in (1,3,4,6)
                      and not (r.platformID==3 and r.platEncID==1 and r.langID==0x409))]
f.save('assets/fonts/SnGNavSymbols.ttf')
EOF

# 4. Prove it: the drift test must go green, and the capture must be LOOKED at
flutter test test/fonts/symbol_font_coverage_test.dart
flutter test test/render_see/symbol_glyphs_capture_test.dart
```

If a needed glyph is ever missing from DejaVu Sans, pick another
freely-licensed source that has it, subset from there, and keep BOTH license
notices in `assets/fonts/`. Never widen a glyph's source silently.

License: `assets/fonts/LICENSE-SnGNavSymbols.txt` (Bitstream Vera terms;
subset renamed as required; the notice ships in the APK as an asset).
