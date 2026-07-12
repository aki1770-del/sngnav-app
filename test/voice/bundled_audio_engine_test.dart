/// The offline mouth, exercised.
///
/// The one behaviour that matters, and that could not be verified before: a
/// safety phrase must reach the driver from BUNDLED BYTES, never through the
/// system TTS — because with no network that TTS is silent and then hangs.
///
/// The play seam is injected. If it were not, the real AudioPlayer would throw
/// off-device, every phrase would quietly take the TTS fallback path, and a
/// broken mouth would look perfectly healthy in CI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/staleness_policy.dart';
import 'package:sngnav_app/voice/bundled_audio_engine.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

/// A TTS that behaves like the real one with no network: NOT available, and
/// anything routed to it is recorded so a test can prove it was not used.
class _DeadTts implements TtsEngine {
  final List<String> spoken = <String>[];
  int stops = 0;

  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> setLanguage(String languageTag) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
}

void main() {
  group('BundledAudioEngine — the mouth that needs no network', () {
    late _DeadTts tts;
    late List<String> played;
    late List<String> delegated;
    late BundledAudioEngine engine;

    setUp(() {
      tts = _DeadTts();
      played = <String>[];
      delegated = <String>[];
      engine = BundledAudioEngine(
        fallback: tts,
        playAsset: (path, volume) async {
          played.add(path);
          return true; // the platform started playback
        },
        onDelegatedToTts: delegated.add,
      );
    });

    test('it is available even when the TTS beneath it is dead', () async {
      expect(await tts.isAvailable(), isFalse);
      expect(
        await engine.isAvailable(),
        isTrue,
        reason: 'The bundled core does not depend on anyone else\'s '
            'infrastructure. That is the entire point.',
      );
    });

    test('the absence line plays from bundled audio and NEVER reaches the TTS',
        () async {
      await engine.speak(kConditionsUnknownJaSpokenText);
      expect(played, <String>['audio/ja/conditions_unknown.wav']);
      expect(
        tts.spoken,
        isEmpty,
        reason: 'It reached the system TTS — silent, then hanging, with no '
            'network. This is the defect the engine exists to end.',
      );
      expect(delegated, isEmpty);
    });

    test('every phrase in the finite safety core bypasses the TTS', () async {
      for (final text in kOfflineSafetyVoiceJa.values) {
        await engine.speak(text);
      }
      expect(played.length, kOfflineSafetyVoiceJa.length);
      expect(tts.spoken, isEmpty);
    });

    test('slotted text still delegates to TTS — a recorded hole, not a hidden '
        'one', () async {
      const slotted = '7時頃の観測では、ブラックアイスバーンのおそれがあります。';
      await engine.speak(slotted);
      expect(played, isEmpty);
      expect(delegated, <String>[slotted]);
      expect(
        tts.spoken,
        <String>[slotted],
        reason: 'Slotted text cannot be pre-rendered and still routes to TTS. '
            'Where TTS is dead it is SILENT — a known limitation, written down.',
      );
    });

    test('if the bundled path itself faults, TTS is still better than silence',
        () async {
      final broken = BundledAudioEngine(
        fallback: tts,
        playAsset: (_, _) async => throw StateError('decoder blew up'),
        onDelegatedToTts: delegated.add,
      );
      await broken.speak(kConditionsUnknownJaSpokenText);
      expect(
        tts.spoken,
        <String>[kConditionsUnknownJaSpokenText],
        reason: 'Never leave the driver with nothing.',
      );
    });

    test('a platform that does NOT start playback is treated as NOT SPOKEN — '
        'never recorded as delivered', () async {
      final silent = BundledAudioEngine(
        fallback: tts,
        // The native player returned false: the phrase did not play.
        playAsset: (_, _) async => false,
        onDelegatedToTts: delegated.add,
      );
      await silent.speak(kConditionsUnknownJaSpokenText);
      expect(
        tts.spoken,
        <String>[kConditionsUnknownJaSpokenText],
        reason: 'A false from the platform means she heard NOTHING. It must '
            'fall back, never be counted as spoken.',
      );
    });

    test('stop() stops both mouths', () async {
      await engine.stop();
      expect(tts.stops, 1);
    });
  });
}
