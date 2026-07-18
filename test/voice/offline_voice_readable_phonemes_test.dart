/// The mouth must actually SPEAK the hazard — an open_jtalk empty-reading oracle.
///
/// assessment #9's gap: the byte-size check (offline_safety_voice_test.dart,
/// ">8000 bytes") passed the SILENT phrase `'濡路、注意'` (43 724 bytes) — because
/// 注意 rendered ~1.4 s of audio while 濡路 (not an open_jtalk dictionary word)
/// produced ZERO phonemes. A professional-profile driver on a wet Akita road
/// heard only 「チューイ」 with no hazard named. Bytes alone cannot see that: a
/// phrase can be half-voiced and still weigh a healthy KB.
///
/// This oracle goes to the phonemes. For every safety phrase, each punctuation-
/// delimited clause that carries kana/kanji content MUST produce at least as
/// many non-silence phonemes as it has content characters (measured floor across
/// the whole catalog is ratio 1.33; a readable clause never falls below 1.0, an
/// unreadable 記号-only clause like 濡路 falls to 0). A clause that renders to
/// silence — a hazard word open_jtalk cannot read — fails CI here, before it is
/// ever bundled into a WAV that "looks fine" at 40 KB.
///
/// ENV-HONEST (mirrors render_see_env): open_jtalk + its dictionary + an HTS
/// voice are needed to trace phonemes. Where they are absent the test SKIPS with
/// a named note (the render pipeline is not exercised, the claim is withdrawn) —
/// it never passes vacuously by pretending it verified. On a host with the
/// engine (open_jtalk lives at /usr/bin/open_jtalk here) the assertion is hard.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';

/// kana (hira/kata) + CJK ideographs + prolonged-sound mark — the characters
/// that must carry a spoken reading. Punctuation (、。) and ASCII are excluded.
final RegExp _content =
    RegExp(r'[぀-ゟ゠-ヿ一-鿿ー]');

String? _findOpenJtalk() {
  for (final p in const ['/usr/bin/open_jtalk', '/usr/local/bin/open_jtalk']) {
    if (File(p).existsSync()) return p;
  }
  final which = Process.runSync('bash', ['-lc', 'command -v open_jtalk || true']);
  final out = (which.stdout as String).trim();
  return out.isEmpty ? null : out;
}

String? _findDict() {
  const root = '/var/lib/mecab/dic/open-jtalk';
  if (!Directory(root).existsSync()) return null;
  final dirs = Directory(root)
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path)
      .toList()
    ..sort();
  return dirs.isEmpty ? null : dirs.last;
}

String? _findVoice() {
  const root = '/usr/share/hts-voice';
  if (!Directory(root).existsSync()) return null;
  final hits = Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.htsvoice'))
      .map((f) => f.path)
      .toList()
    ..sort();
  return hits.isEmpty ? null : hits.first;
}

/// Non-silence phonemes open_jtalk assigns to [text], parsed from the FIRST
/// `[Output label]` full-context block (later blocks repeat the same labels).
List<String> _nonSilencePhonemes(String bin, String dict, String voice,
    String text) {
  final tmp = Directory.systemTemp.createTempSync('jtalk_oracle');
  try {
    final trace = '${tmp.path}/trace.txt';
    final wav = '${tmp.path}/out.wav';
    // open_jtalk reads its text from stdin — feed it via a temp file + shell
    // redirect (Process.runSync exposes no stdin), and capture the phoneme
    // trace it writes to -ot.
    final inFile = File('${tmp.path}/in.txt')..writeAsStringSync(text);
    final r = Process.runSync('bash', [
      '-lc',
      '${_sq(bin)} -x ${_sq(dict)} -m ${_sq(voice)} -r 0.9 '
          '-ot ${_sq(trace)} -ow ${_sq(wav)} < ${_sq(inFile.path)}'
    ]);
    if (r.exitCode != 0 && !File(trace).existsSync()) {
      throw StateError('open_jtalk failed: ${r.stderr}');
    }
    final labs = File(trace).readAsStringSync();
    final blockMatch =
        RegExp(r'\[Output label\](.*?)(?:\n\[|\Z)', dotAll: true)
            .firstMatch(labs);
    final block = blockMatch?.group(1) ?? labs;
    final phonemes = RegExp(r'-([a-zA-Z]+)\+')
        .allMatches(block)
        .map((m) => m.group(1)!)
        .where((p) => p != 'sil' && p != 'pau')
        .toList();
    return phonemes;
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

String _sq(String s) => "'${s.replaceAll("'", r"'\''")}'";

void main() {
  test(
      'every content clause of every safety phrase renders real phonemes '
      '(no silent hazard word — open_jtalk empty-reading oracle)', () {
    final bin = _findOpenJtalk();
    final dict = _findDict();
    final voice = _findVoice();
    if (bin == null || dict == null || voice == null) {
      markTestSkipped('open_jtalk engine not present on this host '
          '(bin=$bin dict=$dict voice=$voice) — phoneme readability NOT '
          'verified in this environment. Re-run where open_jtalk is installed.');
      return;
    }

    final failures = <String>[];
    for (final id in kOfflineSafetyVoiceJa.keys) {
      // Verify the text the WAV is actually rendered FROM (the render override
      // when present, else the catalog value) — that is what HER hears. The
      // catalog value can be a terse emitter string open_jtalk cannot read
      // (e.g. 濡路); the override is the readable phrase the mouth speaks.
      final spoken = offlineSafetyRenderTextFor(id);
      for (final clause in spoken.split(RegExp(r'[、。]'))) {
        final contentLen = _content.allMatches(clause).length;
        if (contentLen == 0) continue; // punctuation / ASCII-only segment
        final phonemes = _nonSilencePhonemes(bin, dict, voice, clause);
        if (phonemes.length < contentLen) {
          failures.add('  "$id" clause 「$clause」 '
              '→ ${phonemes.length} non-silence phonemes for $contentLen '
              'content chars '
              '(${phonemes.isEmpty ? "SILENT — open_jtalk has no reading" : phonemes.join(" ")})');
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'These safety-phrase clauses render to silence or near-silence — '
          'the hazard word would not be spoken. Use a form open_jtalk can '
          'read (e.g. 濡れた路面, not 濡路) and re-render '
          '(bash tool/render_offline_voice.sh):\n${failures.join("\n")}',
    );
  });
}
