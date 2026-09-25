/// Every bundled clip finishes well inside the play cap (2026-09-25).
///
/// WHY. [BundledAudioEngine] caps the platform await at `playTimeout`, 25 s
/// by default: a phrase still playing then is treated as a wedged channel and
/// goes to the TTS fallback, which with no network is a mouth that says
/// nothing. The comment beside the cap said the longest clip was 13.5 s.
/// Measured this day, the longest is 18.220 s (alert_ice_ageing_rural.wav),
/// and nothing compared the two: a clip re-rendered past the cap would be cut
/// into a false fallback on every play, with every test green.
///
/// WHAT IT CHECKS. Each clip's duration, read from its own WAV header and
/// data size, plus [_startMargin] for the player to start, fits under the cap
/// the engine uses by default. It does not listen to anything.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/voice/bundled_audio_engine.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

class _NoTts implements TtsEngine {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> setLanguage(String languageTag) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// Time for the player to start before the first sample sounds.
const _startMargin = Duration(seconds: 2);

/// The length of a PCM WAV, from its `fmt ` and `data` chunks.
Duration _wavDuration(Uint8List b) {
  final d = ByteData.sublistView(b);
  if (String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(b.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  int? rate, channels, bits, dataBytes;
  var off = 12;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final len = d.getUint32(off + 4, Endian.little);
    if (id == 'fmt ') {
      channels = d.getUint16(off + 10, Endian.little);
      rate = d.getUint32(off + 12, Endian.little);
      bits = d.getUint16(off + 22, Endian.little);
    } else if (id == 'data') {
      dataBytes = len;
    }
    off += 8 + len + (len.isOdd ? 1 : 0);
  }
  if (rate == null || channels == null || bits == null || dataBytes == null) {
    throw const FormatException('no fmt or data chunk');
  }
  final bytesPerSecond = rate * channels * (bits ~/ 8);
  return Duration(
      microseconds: (dataBytes * 1000000 / bytesPerSecond).round());
}

Uint8List _syntheticWav({required int rate, required int frames}) {
  final data = frames * 2; // mono, 16-bit
  final b = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, data, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  test('the reader measures a clip of known length exactly', () {
    expect(_wavDuration(_syntheticWav(rate: 16000, frames: 16000 * 3)),
        const Duration(seconds: 3));
  });

  test('every bundled clip, plus time to start, fits under the play cap', () {
    final cap = BundledAudioEngine(fallback: _NoTts()).playTimeout;
    final clips = Directory('assets/audio/ja')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wav'))
        .toList();
    expect(clips, isNotEmpty, reason: 'no clips found: nothing was measured');
    final lengths = {
      for (final f in clips)
        f.uri.pathSegments.last: _wavDuration(f.readAsBytesSync()),
    };
    final longest =
        lengths.entries.reduce((a, b) => a.value >= b.value ? a : b);
    for (final e in lengths.entries) {
      expect(e.value + _startMargin <= cap, isTrue,
          reason: '${e.key} is ${e.value.inMilliseconds} ms; with '
              '${_startMargin.inSeconds} s to start it would be cut at the '
              '${cap.inSeconds} s cap and fall through to a voice that needs '
              'the network');
    }
    // Recorded so the margin can be read off the run.
    // ignore: avoid_print
    print('longest clip: ${longest.key} ${longest.value.inMilliseconds} ms; '
        'cap ${cap.inMilliseconds} ms');
  });
}
