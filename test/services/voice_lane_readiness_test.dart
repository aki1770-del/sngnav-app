// A1 pre-drive voice-lane readiness — verdicts from faked voice maps in the
// REAL flutter_tts 4.2.5 Android map shape (FlutterTtsPlugin.kt:618-626:
// name / locale as Locale.toLanguageTag / quality / latency /
// network_required "0"|"1" strings / features).

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/voice_lane_readiness.dart';

/// A voice map exactly in the Android plugin's shape.
Map<String, String> voice(String locale, {String? networkRequired}) => {
      'name': '$locale-x-test-voice',
      'locale': locale,
      'quality': 'high',
      'latency': 'normal',
      'network_required': ?networkRequired,
      'features': '',
    };

void main() {
  test('offline ja voice present -> offlineJaReady', () async {
    final verdict = await readVoiceLaneReadiness(voicesProvider: () async => [
          voice('en-US', networkRequired: '0'),
          voice('ja-JP', networkRequired: '1'),
          voice('ja-JP', networkRequired: '0'), // the one that matters
        ]);
    expect(verdict, VoiceLaneVerdict.offlineJaReady);
  });

  test('every ja voice network-bound -> jaNetworkOnly', () async {
    final verdict = await readVoiceLaneReadiness(voicesProvider: () async => [
          voice('ja-JP', networkRequired: '1'),
          voice('ja-JP', networkRequired: '1'),
          voice('en-US', networkRequired: '0'),
        ]);
    expect(verdict, VoiceLaneVerdict.jaNetworkOnly);
  });

  test('voices exist, none Japanese -> noJaVoice', () async {
    final verdict = await readVoiceLaneReadiness(voicesProvider: () async => [
          voice('en-US', networkRequired: '0'),
          voice('ko-KR', networkRequired: '0'),
        ]);
    expect(verdict, VoiceLaneVerdict.noJaVoice);
  });

  test('missing network_required (iOS map shape) counts as offline-capable '
      '-> never a false warning', () async {
    final verdict = await readVoiceLaneReadiness(voicesProvider: () async => [
          {'name': 'Kyoko', 'locale': 'ja-JP'}, // iOS: no network_required
        ]);
    expect(verdict, VoiceLaneVerdict.offlineJaReady);
  });

  test('underscore locale separators tolerated', () async {
    final verdict = await readVoiceLaneReadiness(voicesProvider: () async => [
          voice('ja_JP', networkRequired: '1'),
        ]);
    expect(verdict, VoiceLaneVerdict.jaNetworkOnly);
  });

  test('null (Android engine NPE reply, kt:553-566) -> unknown', () async {
    final verdict =
        await readVoiceLaneReadiness(voicesProvider: () async => null);
    expect(verdict, VoiceLaneVerdict.unknown);
  });

  test('empty list -> unknown (unreadable, not proven absence)', () async {
    final verdict =
        await readVoiceLaneReadiness(voicesProvider: () async => <Object>[]);
    expect(verdict, VoiceLaneVerdict.unknown);
  });

  test('provider throwing (MissingPluginException class of faults) '
      '-> unknown', () async {
    final verdict = await readVoiceLaneReadiness(
        voicesProvider: () async => throw Exception('no plugin'));
    expect(verdict, VoiceLaneVerdict.unknown);
  });

  test('provider hanging -> unknown after the timeout, never a hang',
      () async {
    final verdict = await readVoiceLaneReadiness(
      voicesProvider: () => Future.any([]), // never completes
      timeout: const Duration(milliseconds: 20),
    );
    expect(verdict, VoiceLaneVerdict.unknown);
  });

  test('no provider under the test binding -> unknown without touching '
      'the plugin (honest-null off-mobile posture)', () async {
    // The flutter_test harness sets FLUTTER_TEST, so the mobile-platform
    // guard is false and the real FlutterTts is never constructed.
    final verdict = await readVoiceLaneReadiness();
    expect(verdict, VoiceLaneVerdict.unknown);
  });

  test('malformed entries are skipped, not fatal', () async {
    final verdict = await readVoiceLaneReadiness(voicesProvider: () async => [
          'not-a-map',
          <String, String>{}, // no locale
          voice('ja-JP', networkRequired: '0'),
        ]);
    expect(verdict, VoiceLaneVerdict.offlineJaReady);
  });
}
