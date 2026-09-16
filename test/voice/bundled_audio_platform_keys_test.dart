/// The keys the offline voice sends to Android, taken from the real channel call.
///
/// Every other test of the bundled voice injects `playAsset`, so the key never
/// reaches the platform in any of them. That is how a key naming a path the APK
/// does not hold stayed green from 2026-07-12 to 2026-09-16. This test runs the
/// engine's own channel call for every phrase in the bundled vocabulary, with
/// Android replaced by a handler that records the `asset` argument, and then
/// loads each recorded key from the asset bundle the Flutter tool built from
/// pubspec.yaml.
///
/// A Dart test cannot see an APK. When SNGNAV_BUNDLED_AUDIO_KEYS_OUT names a
/// file, the recorded keys are written there, and
/// tool/check_bundled_audio_in_apk.py checks them against a built APK using the
/// key rule MainActivity.kt applies.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/voice/bundled_audio_engine.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

class _RecordingTts implements TtsEngine {
  final List<String> spoken = <String>[];

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
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled phrase reaches the platform with a key the asset bundle '
      'holds', () async {
    final keys = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(kBundledAudioChannel, (call) async {
      if (call.method == 'play') {
        final args = call.arguments as Map<Object?, Object?>;
        keys.add(args['asset']! as String);
      }
      return true; // report the clip as played to the end
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(kBundledAudioChannel, null),
    );

    final tts = _RecordingTts();
    final engine = BundledAudioEngine(fallback: tts);
    for (final text in kOfflineSafetyVoiceJa.values) {
      await engine.speak(text);
    }

    expect(
      keys,
      hasLength(kOfflineSafetyVoiceJa.length),
      reason: 'Every phrase in the bundled vocabulary must reach the platform.',
    );
    expect(tts.spoken, isEmpty);

    // Written before the bundle check, so a red run still hands the APK check
    // the keys it has to judge.
    final out = Platform.environment['SNGNAV_BUNDLED_AUDIO_KEYS_OUT'];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsStringSync('${keys.join('\n')}\n');
    }

    final missing = <String>[];
    for (final key in keys) {
      try {
        await rootBundle.load(key);
      } on Object {
        missing.add(key);
      }
    }
    expect(
      missing,
      isEmpty,
      reason: '${missing.length} of ${keys.length} keys sent to the platform '
          'are not in the asset bundle built from pubspec.yaml, so Android '
          'cannot open them either. First: '
          '${missing.isEmpty ? '-' : missing.first}',
    );
  });
}
