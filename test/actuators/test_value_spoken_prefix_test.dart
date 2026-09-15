/// AAA R52 AQ4: a line a test value raised is spoken with テスト値です。 /
/// "Test value." before it, as its OWN utterance, so the offline audio still
/// finds the line by its exact string, and the prefix itself is bundled.
///
/// Bound: recording actuators and an injected play seam. Nothing heard.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/actuators/alert_actuators.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/actuators/alert_announcer.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/voice/bundled_audio_engine.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

import '../support/fake_alert_actuators.dart';

class _PrefixThrows implements AlertActuators {
  final spoken = <String>[];
  final haptics = <HapticCuePattern>[];
  @override
  Future<void> speak(String text, {required String localeTag}) async {
    if (text == 'テスト値です。') throw StateError('prefix fault');
    spoken.add(text);
  }

  @override
  Future<void> haptic(HapticCuePattern pattern) async => haptics.add(pattern);
  @override
  Future<void> keepAwake(bool enabled) async {}
}

class _RecordingTts implements TtsEngine {
  final spoken = <String>[];
  @override
  Future<bool> isAvailable() async => true;
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
  const hud = DriveHudLocalizer();
  final stopJa = hud.spokenGuidance(DriveAction.considerStopping, 'ja');
  final cautionJa = hud.spokenGuidance(DriveAction.heightenedCaution, 'ja');

  test('the words, ja and en', () {
    expect(hud.testValueSpokenPrefix('ja'), 'テスト値です。');
    expect(hud.testValueSpokenPrefix('en'), 'Test value.');
  });

  test('prefix, then the line verbatim, one haptic', () async {
    final a = FakeAlertActuators();
    await AlertAnnouncer(actuators: a).announce(
      severity: AlertSeverity.critical,
      text: stopJa,
      localeTag: 'ja',
      spokenPrefix: 'テスト値です。',
    );
    expect(a.spoken.map((l) => l.text), ['テスト値です。', stopJa]);
    expect(a.haptics, hasLength(1));
  });

  test('no prefix: the line alone, as before', () async {
    final a = FakeAlertActuators();
    await AlertAnnouncer(actuators: a).announce(
      severity: AlertSeverity.critical,
      text: stopJa,
      localeTag: 'ja',
    );
    expect(a.spoken.map((l) => l.text), [stopJa]);
  });

  test('a fault speaking the prefix never silences the line', () async {
    final a = _PrefixThrows();
    await AlertAnnouncer(actuators: a).announce(
      severity: AlertSeverity.warning,
      text: cautionJa,
      localeTag: 'ja',
      spokenPrefix: 'テスト値です。',
    );
    expect(a.spoken, [cautionJa]);
    expect(a.haptics, hasLength(1));
  });

  test('offline: the prefix and each rung line are bundled audio, none '
      'goes to the TTS', () async {
    for (final s in ['テスト値です。', stopJa, cautionJa]) {
      expect(OfflineSafetyVoice.covers(s), isTrue, reason: s);
    }
    // The joined string is NOT in the mouth: that is why the prefix is its own
    // utterance. Were it joined, the line would go to a TTS that is silent
    // offline.
    expect(OfflineSafetyVoice.covers('テスト値です。$stopJa'), isFalse);
    final tts = _RecordingTts();
    final played = <String>[];
    final engine = BundledAudioEngine(
      fallback: tts,
      playAsset: (path, _) async {
        played.add(path);
        return true;
      },
    );
    await engine.speak('テスト値です。');
    await engine.speak(stopJa);
    expect(played, [
      'audio/ja/test_value_prefix.wav',
      'audio/ja/guidance_consider_stopping.wav',
    ]);
    expect(tts.spoken, isEmpty);
  });


  for (final fromTest in [false, true]) {
    test('an icy turn, icyTurnFromTestValue $fromTest: '
        '${fromTest ? 'prefix, then the turn' : 'the turn alone'}', () async {
      final a = FakeAlertActuators();
      final c = DriveHudController(actuators: a, localeTag: 'ja');
      c.updateEnvironment(
        visibilityMeters: 10000,
        visibilityAgeSeconds: 0,
        advisorySeverity: null,
        speedMetersPerSecond: null,
      );
      final t0 = DateTime.utc(2026, 1, 1, 8);
      c.onPositionFix(
        PositionAvailable(
          latitude: 39.72,
          longitude: 140.10,
          accuracyMeters: 20,
          timestamp: t0,
        ),
        now: t0,
      );
      await Future<void>.delayed(Duration.zero);
      final before = a.spoken.length;
      final d = c.narrateNextManeuver(
        const RouteManeuver(
          index: 1,
          instruction: 'Right onto Main St',
          type: 'right',
          lengthKm: 0.4,
          timeSeconds: 30,
          position: LatLng(39.72, 140.10),
        ),
        icyTurn: true,
        icyTurnFromTestValue: fromTest,
      );
      await Future<void>.delayed(Duration.zero);
      expect(d.icyCoupled, isTrue, reason: 'control');
      final told = a.spoken.sublist(before).map((l) => l.text).toList();
      expect(told, fromTest ? ['テスト値です。', d.text] : [d.text]);
    });
  }
}
