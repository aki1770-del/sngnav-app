#!/usr/bin/env bash
# Render the finite ja SAFETY vocabulary to bundled audio — the MOUTH.
#
# Source of truth: lib/voice/offline_safety_voice.dart (kOfflineSafetyVoiceJa).
# This script does NOT author phrases; it renders the ones already in the app.
#
# Engine: open_jtalk + the nitech-jp-atr503-m001 HTS voice (fully offline, on
# this workstation only — HER phone plays the resulting WAVs and needs no engine
# at all). Chair ruling 2026-07-12: synth now, human-record the safety core
# before winter. When the human recordings land they replace these files at the
# SAME ids and nothing else in the app changes.
#
# Output: assets/audio/ja/<id>.wav — 16 kHz mono 16-bit PCM.
#   16 kHz is deliberate: speech intelligibility for a warning is fully carried
#   below 8 kHz, and it holds the whole safety core to a few hundred KB in an
#   APK that must also carry a 16 MB offline basemap. Bigger is not safer here;
#   it is just bigger.
#
# Usage:  bash tool/render_offline_voice.sh          (renders all)
#         bash tool/render_offline_voice.sh --check  (verifies, renders nothing)
set -euo pipefail

cd "$(dirname "$0")/.."
CATALOG="lib/voice/offline_safety_voice.dart"
OUTDIR="assets/audio/ja"

command -v open_jtalk >/dev/null || {
  echo "FATAL: open_jtalk not installed. This renders the safety voice." >&2
  exit 1
}
DIC="$(find /var/lib/mecab/dic/open-jtalk -maxdepth 1 -type d | tail -1)"
VOICE="$(find /usr/share/hts-voice -name '*.htsvoice' | head -1)"
[ -d "$DIC" ] && [ -f "$VOICE" ] || { echo "FATAL: open_jtalk dict/voice missing" >&2; exit 1; }

# Parse id → text straight out of the Dart catalog. Deliberately dumb: if the
# catalog changes shape this breaks loudly rather than rendering a stale set.
mapfile -t ENTRIES < <(
  sed -n "/^const Map<String, String> kOfflineSafetyVoiceJa/,/^};/p" "$CATALOG" |
    grep -oE "^  '[a-z_]+':[[:space:]]*$" -A0 >/dev/null 2>&1 || true
  python3 - "$CATALOG" <<'PY'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
body = re.search(r'const Map<String, String> kOfflineSafetyVoiceJa\s*=\s*<String, String>\{(.*?)\n\};', src, re.S).group(1)
# id: 'text',   (text may sit on the next line)
for m in re.finditer(r"'([a-z_]+)':\s*\n?\s*'([^']+)'", body):
    print(f"{m.group(1)}\t{m.group(2)}")
PY
)

[ "${#ENTRIES[@]}" -gt 0 ] || { echo "FATAL: parsed 0 phrases from $CATALOG" >&2; exit 1; }

if [ "${1:-}" = "--check" ]; then
  missing=0
  for e in "${ENTRIES[@]}"; do
    id="${e%%$'\t'*}"
    [ -s "$OUTDIR/$id.wav" ] || { echo "MISSING: $OUTDIR/$id.wav"; missing=1; }
  done
  [ "$missing" -eq 0 ] && echo "OK: ${#ENTRIES[@]}/${#ENTRIES[@]} safety phrases rendered."
  exit "$missing"
fi

mkdir -p "$OUTDIR"
echo "Rendering ${#ENTRIES[@]} ja safety phrases → $OUTDIR"
for e in "${ENTRIES[@]}"; do
  id="${e%%$'\t'*}"
  text="${e#*$'\t'}"
  printf '%s' "$text" |
    open_jtalk -x "$DIC" -m "$VOICE" -r 0.9 -ow "/tmp/_oj_$id.wav"
  # 48k → 16k mono: speech-band only, small enough to ship beside the basemap.
  python3 - "/tmp/_oj_$id.wav" "$OUTDIR/$id.wav" <<'PY'
import audioop, sys, wave
src, dst = sys.argv[1], sys.argv[2]
with wave.open(src) as w:
    frames = w.readframes(w.getnframes())
    sw, ch, rate = w.getsampwidth(), w.getnchannels(), w.getframerate()
if ch == 2:
    frames = audioop.tomono(frames, sw, 0.5, 0.5)
frames, _ = audioop.ratecv(frames, sw, 1, rate, 16000, None)
with wave.open(dst, 'wb') as o:
    o.setnchannels(1); o.setsampwidth(sw); o.setframerate(16000)
    o.writeframes(frames)
PY
  rm -f "/tmp/_oj_$id.wav"
  printf '  %-24s %6s  %s\n' "$id" "$(du -h "$OUTDIR/$id.wav" | cut -f1)" "$text"
done
echo "Total: $(du -sh "$OUTDIR" | cut -f1)"
