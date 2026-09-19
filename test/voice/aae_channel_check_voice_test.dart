/// The warning-channel check's Japanese line, played by the same mouth as her
/// real warnings.
///
/// WHY (2026-09-19). Every Japanese safety line plays from a bundled clip,
/// because on the night the network dies the phone's own voice can be silent
/// and then hang. The check's line, 「これはテストです。警報の音と振動を確認して
/// います。」, had no clip, so the bundled engine handed it to the phone's voice.
/// On a phone with no working Japanese system voice the check was therefore
/// silent while every real warning would play: she would answer いいえ, and the
/// diary would record a failure that is not in her warnings. A system voice
/// that never reports completion is also waited out by the engine's timeout,
/// which holds the one announcement queue for that long, and then raises the
/// unverified chip on her in-drive card.
///
/// These tests use the app's own words (AppL10n, ja) and the engine composition
/// the phone runs (buildMobileTtsEngine: a BundledAudioEngine over a
/// HardenedTtsEngine at its DEFAULT timings); only the platform is replaced.
/// Each prints what it measured, so a failing run says how long the hold was.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity;
import 'package:sngnav_app/actuators/alert_announcer.dart';
import 'package:sngnav_app/actuators/hardened_tts_engine.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/drive_diary.dart';
import 'package:sngnav_app/services/staleness_policy.dart'
    show kConditionsUnknownJaSpokenText;
import 'package:sngnav_app/voice/bundled_audio_engine.dart';
import 'package:sngnav_app/voice/offline_safety_voice.dart';
import 'package:voice_guidance/voice_guidance.dart' show TtsEngine;

import '../support/fake_alert_actuators.dart';

final String _line = const AppL10n(Locale('ja')).channelCheckSpokenLine;

/// A system voice that is simply not there: anything routed to it is recorded
/// so a test can show it was not used.
class _DeadTts implements TtsEngine {
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

/// A platform voice that accepts an utterance and never reports that it
/// finished: the plugin state the hardened engine's timeout exists for.
class _HangingAdapter implements TtsAdapter {
  final List<String> spoken = <String>[];

  @override
  Future<dynamic> speak(String text, {required bool focus}) {
    spoken.add(text);
    return Completer<dynamic>().future;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;
  @override
  Future<dynamic> setAudioAttributesForNavigation() async => 1;
  @override
  Future<dynamic> setLanguage(String languageTag) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> stop() async => 1;
  @override
  Future<dynamic> getLanguages() async => <String>['ja-JP'];
}

/// The actuators the app is given, with speech going through [engine] after
/// being recorded, the way the phone's actuators speak through theirs.
class _EngineBackedActuators extends FakeAlertActuators {
  _EngineBackedActuators(this.engine);

  final TtsEngine engine;

  @override
  Future<void> speak(String text, {required String localeTag}) async {
    await super.speak(text, localeTag: localeTag);
    await engine.speak(text);
  }
}

/// The phone's engine composition with a hanging platform voice.
BundledAudioEngine _phoneEngineWithHangingVoice({
  required _HangingAdapter adapter,
  required void Function() onUnverified,
  required void Function() onVerified,
  List<String>? played,
}) =>
    BundledAudioEngine(
      fallback: HardenedTtsEngine(
        adapter: adapter,
        onSpeechUnverified: onUnverified,
        onSpeechVerified: onVerified,
      ),
      playAsset: (path, volume) async {
        played?.add(path);
        return true;
      },
      onBundledSpoken: (_) => onVerified(),
    );

void main() {
  test('the check line is in the bundled catalog under the words the app says',
      () {
    expect(
      OfflineSafetyVoice.assetFor(_line),
      isNotNull,
      reason: 'the check speaks 「$_line」 and the bundled mouth has no clip '
          'for it, so it goes to the phone\'s own voice',
    );
  });

  test('the check line plays from bundled audio and never reaches the phone\'s '
      'voice', () async {
    final tts = _DeadTts();
    final played = <String>[];
    final delegated = <String>[];
    final engine = BundledAudioEngine(
      fallback: tts,
      playAsset: (path, volume) async {
        played.add(path);
        return true;
      },
      onDelegatedToTts: delegated.add,
    );

    await engine.speak(_line);

    // ignore: avoid_print
    print('AAE_VOICE[route] played=$played delegated=${delegated.length}');
    expect(delegated, isEmpty,
        reason: 'the check line was handed to the phone\'s voice');
    expect(tts.spoken, isEmpty);
    expect(played, hasLength(1));
    expect(played.single, OfflineSafetyVoice.assetFor(_line));
  });

  testWidgets('with a phone voice that hangs, a real warning announced just '
      'after the check reaches her at once', (tester) async {
    final adapter = _HangingAdapter();
    final played = <String>[];
    var elapsedMs = 0;
    int? realWarningAtMs;
    final realWarning = OfflineSafetyVoice.assetFor(
      kConditionsUnknownJaSpokenText,
    )!;
    final engine = _phoneEngineWithHangingVoice(
      adapter: adapter,
      onUnverified: () {},
      onVerified: () {},
      played: played,
    );
    final announcer = AlertAnnouncer(
      actuators: _EngineBackedActuators(engine),
    );

    unawaited(announcer.announce(
      severity: AlertSeverity.warning,
      text: _line,
      localeTag: 'ja',
    ));
    unawaited(announcer.announce(
      severity: AlertSeverity.warning,
      text: kConditionsUnknownJaSpokenText,
      localeTag: 'ja',
    ));
    await tester.pump();
    while (elapsedMs <= 30000) {
      if (played.contains(realWarning)) {
        realWarningAtMs = elapsedMs;
        break;
      }
      await tester.pump(const Duration(milliseconds: 250));
      elapsedMs += 250;
    }

    // ignore: avoid_print
    print('AAE_VOICE[queue] real warning played at ${realWarningAtMs ?? '>30000'} '
        'ms; the check line reached the phone voice ${adapter.spoken.length} '
        'time(s)');
    expect(realWarningAtMs, isNotNull,
        reason: 'the real warning never played within 30 s');
    expect(realWarningAtMs, 0,
        reason: 'the real warning waited ${realWarningAtMs}ms behind the '
            'check line');
    expect(adapter.spoken, isEmpty);
  });

  testWidgets('with a phone voice that hangs, firing the check in the app '
      'finishes at once and raises no unverified chip on her page',
      (tester) async {
    final adapter = _HangingAdapter();
    final speechUnverified = ValueNotifier<bool>(false);
    final tmp = Directory.systemTemp.createTempSync('aae-cc-voice-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // Wired as main.dart wires the phone's engine: unverified raises the chip,
    // verified clears it.
    final engine = _phoneEngineWithHangingVoice(
      adapter: adapter,
      onUnverified: () => speechUnverified.value = true,
      onVerified: () => speechUnverified.value = false,
    );
    final acts = _EngineBackedActuators(engine);

    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      actuators: acts,
      diary: DriveDiary(file: File('${tmp.path}/diary.txt')),
      speechUnverified: speechUnverified,
    ));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('channel-check-fire')),
      300,
    );
    await tester.tap(find.byKey(const Key('channel-check-fire')));
    await tester.pump();

    // The check is finished when its questions appear.
    final question = find.byKey(const Key('channel-check-heard-yes'));
    var elapsedMs = 0;
    while (question.evaluate().isEmpty && elapsedMs < 30000) {
      await tester.pump(const Duration(milliseconds: 250));
      elapsedMs += 250;
    }
    final chipRaised = speechUnverified.value;
    await tester.pump();

    // ignore: avoid_print
    print('AAE_VOICE[app] questions after ${question.evaluate().isEmpty ? '>30000' : elapsedMs} '
        'ms; chip raised=$chipRaised; chip on screen='
        '${find.byKey(const Key('speech-unverified-chip')).evaluate().length}; '
        'the check line reached the phone voice ${adapter.spoken.length} time(s)');
    expect(acts.spoken.last.text, _line,
        reason: 'precondition: the check spoke its own line');
    expect(question, findsOneWidget,
        reason: 'the check never finished within 30 s');
    expect(elapsedMs, 0,
        reason: 'the check held for ${elapsedMs}ms before she could answer');
    expect(chipRaised, isFalse,
        reason: 'the check raised 「音声警告を確認できませんでした」 on her page');
    expect(find.byKey(const Key('speech-unverified-chip')), findsNothing);
    expect(adapter.spoken, isEmpty);
  });
}
