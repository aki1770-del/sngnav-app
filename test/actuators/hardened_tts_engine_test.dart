// Tier-1 voice-lane hardening — HardenedTtsEngine behavior contract.
//
// The fake TtsAdapter scripts the platform's verified result semantics
// (flutter_tts 4.2.5 Android FlutterTtsPlugin.kt: 1 = utterance completed
// under awaitSpeakCompletion, kt:120-121/201-207; 0 = discarded-busy or
// stopped, kt:304-309/379-382; onError HANGS the Future, kt:168-198 — hence
// the timeout scenario is a real, reachable plugin state, not paranoia).
//
// HONESTY (OPS-066 / AAE env-bound): these tests pin the DART-side contract
// (config-once, focus:true, retry, timeout, log, callbacks, never-throw).
// Real engine rebind timing / audio-focus ducking / audibility are on-device
// facts — DEFERRED, no Android device in this env.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/actuators/hardened_tts_engine.dart';
import 'package:sngnav_app/services/error_log.dart';

/// Scripted adapter: each speak() consumes the next scripted behavior.
class FakeTtsAdapter implements TtsAdapter {
  FakeTtsAdapter(this.speakScript);

  /// One entry per expected speak() call:
  /// an int (the platform result), the string 'hang' (never completes),
  /// or an Exception object (thrown).
  final List<Object> speakScript;

  final List<String> spokenTexts = [];
  final List<bool> spokenFocus = [];
  int awaitSpeakCompletionCalls = 0;
  bool? lastAwaitSpeakCompletionValue;
  int setAudioAttributesCalls = 0;
  int stopCalls = 0;
  final List<String> languages = [];
  final List<double> volumes = [];
  final List<double> rates = [];

  @override
  Future<dynamic> speak(String text, {required bool focus}) {
    spokenTexts.add(text);
    spokenFocus.add(focus);
    final step = speakScript.isEmpty ? 1 : speakScript.removeAt(0);
    if (step == 'hang') return Completer<dynamic>().future; // never resolves
    if (step is Exception) return Future<dynamic>.error(step);
    return Future<dynamic>.value(step);
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    awaitSpeakCompletionCalls++;
    lastAwaitSpeakCompletionValue = awaitCompletion;
    return 1;
  }

  @override
  Future<dynamic> setAudioAttributesForNavigation() async {
    setAudioAttributesCalls++;
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String languageTag) async {
    languages.add(languageTag);
    return 1;
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    volumes.add(volume);
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    rates.add(rate);
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stopCalls++;
    return 1;
  }

  @override
  Future<dynamic> getLanguages() async => ['ja-JP', 'en-US'];
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_hardened_tts');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  LocalErrorLog makeLog() =>
      LocalErrorLog(file: File('${tmp.path}/error_log.txt'));

  HardenedTtsEngine makeEngine(
    FakeTtsAdapter adapter, {
    LocalErrorLog? log,
    void Function()? onUnverified,
    void Function()? onVerified,
  }) =>
      HardenedTtsEngine(
        adapter: adapter,
        errorLog: log,
        onSpeechUnverified: onUnverified,
        onSpeechVerified: onVerified,
        // Small timings so the timeout/retry paths run in test time.
        retryDelay: const Duration(milliseconds: 1),
        speakTimeoutFloor: const Duration(milliseconds: 50),
        speakTimeoutPerChar: Duration.zero,
        speakTimeoutCeiling: const Duration(milliseconds: 100),
      );

  test('success path: one speak, focus:true, no retry, no log, '
      'verified callback fires', () async {
    final adapter = FakeTtsAdapter([1]);
    final log = makeLog();
    var unverified = 0;
    var verified = 0;
    final engine = makeEngine(adapter,
        log: log,
        onUnverified: () => unverified++,
        onVerified: () => verified++);

    await engine.speak('ブラックアイスバーンのおそれ');

    expect(adapter.spokenTexts, hasLength(1), reason: 'no retry on success');
    expect(adapter.spokenFocus, [true],
        reason: 'audio-focus duck (focus:true) on every utterance');
    expect(verified, 1);
    expect(unverified, 0);
    expect(log.readAll(), isEmpty, reason: 'no log line on success');
  });

  test('one-time lazy config: awaitSpeakCompletion(true) + nav audio '
      'attributes exactly once across speaks', () async {
    final adapter = FakeTtsAdapter([1, 1, 1]);
    final engine = makeEngine(adapter);

    await engine.speak('一');
    await engine.speak('二');
    await engine.speak('三');

    expect(adapter.awaitSpeakCompletionCalls, 1);
    expect(adapter.lastAwaitSpeakCompletionValue, isTrue);
    expect(adapter.setAudioAttributesCalls, 1);
  });

  test('failure-then-retry-success: platform 0 then 1 -> verified, '
      'no log, no unverified callback', () async {
    final adapter = FakeTtsAdapter([0, 1]);
    final log = makeLog();
    var unverified = 0;
    var verified = 0;
    final engine = makeEngine(adapter,
        log: log,
        onUnverified: () => unverified++,
        onVerified: () => verified++);

    await engine.speak('凍結注意');

    expect(adapter.spokenTexts, hasLength(2), reason: 'exactly one retry');
    expect(verified, 1);
    expect(unverified, 0);
    expect(log.readAll(), isEmpty);
  });

  test('double failure: 0 then 0 -> one LocalErrorLog line + '
      'onSpeechUnverified, never throws', () async {
    final adapter = FakeTtsAdapter([0, 0]);
    final log = makeLog();
    var unverified = 0;
    var verified = 0;
    final engine = makeEngine(adapter,
        log: log,
        onUnverified: () => unverified++,
        onVerified: () => verified++);

    await engine.speak('視界不良');

    expect(adapter.spokenTexts, hasLength(2),
        reason: 'retry ONCE, never a loop');
    expect(unverified, 1);
    expect(verified, 0);
    final logged = log.readAll();
    expect(logged, contains('HardenedTtsEngine'));
    expect(logged, contains('speech unverified'));
    expect(logged, isNot(contains('視界不良')),
        reason: 'the spoken text must NOT be logged (length only — the log '
            'must stay free of anything position-like)');
  });

  test('timeout (the plugin onError-hang state): callback + log, '
      'stop() fired to clear the held platform result, no retry', () async {
    final adapter = FakeTtsAdapter(['hang']);
    final log = makeLog();
    var unverified = 0;
    final engine = makeEngine(adapter, log: log,
        onUnverified: () => unverified++);

    await engine.speak('ホワイトアウト');

    expect(adapter.spokenTexts, hasLength(1),
        reason: 'no second full timeout window after a timeout');
    expect(unverified, 1);
    expect(log.readAll(), contains('timeout'));
    expect(adapter.stopCalls, greaterThanOrEqualTo(1),
        reason: 'stop() clears the plugin\'s held speakResult '
            '(FlutterTtsPlugin.kt:373-383)');
  });

  test('adapter throwing never escapes the announcer (never-throw '
      'contract) and reports unverified', () async {
    final adapter =
        FakeTtsAdapter([Exception('channel fault'), Exception('again')]);
    final log = makeLog();
    var unverified = 0;
    final engine = makeEngine(adapter, log: log,
        onUnverified: () => unverified++);

    // Must complete normally — no throw.
    await engine.speak('注意');

    expect(unverified, 1);
    expect(log.readAll(), contains('speech unverified'));
  });

  test('empty / disposed guards: no adapter calls, no callbacks', () async {
    final adapter = FakeTtsAdapter([1]);
    var unverified = 0;
    final engine = makeEngine(adapter, onUnverified: () => unverified++);

    await engine.speak('   ');
    expect(adapter.spokenTexts, isEmpty);

    await engine.dispose();
    await engine.speak('after dispose');
    expect(adapter.spokenTexts, isEmpty);
    expect(unverified, 0);
  });

  test('delegation parity with FlutterTtsEngine: rate mapping halves into '
      '0.0..1.0 and volume clamps', () async {
    final adapter = FakeTtsAdapter([]);
    final engine = makeEngine(adapter);

    await engine.setSpeechRate(1.0); // our base -> flutter_tts 0.5
    await engine.setSpeechRate(3.0); // clamped to 2.0 -> 1.0
    await engine.setSpeechRate(0.1); // clamped to 0.25 -> 0.125
    expect(adapter.rates, [0.5, 1.0, 0.125]);

    await engine.setVolume(1.7);
    expect(adapter.volumes, [1.0]);

    await engine.setLanguage('ja-JP');
    expect(adapter.languages, ['ja-JP']);

    expect(await engine.isAvailable(), isTrue);
  });
}
