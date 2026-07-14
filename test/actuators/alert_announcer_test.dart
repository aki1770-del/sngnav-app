/// WS5 — [AlertAnnouncer] tests. The heart of the accessibility floor:
/// a whiteout-class hazard must reach the driver on BOTH channels (audio +
/// haptic), off the same severity gate, with the correct JA text + locale.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/actuators/alert_actuators.dart';
import 'package:sngnav_app/actuators/alert_announcer.dart';
import 'package:sngnav_app/main.dart' show severityForCondition;

import '../support/fake_alert_actuators.dart';

/// An actuator whose [speak] ALWAYS throws (a TTS fault), but whose [haptic]
/// still records. Proves the OPS-059 parity guarantee: a broken audio channel
/// must NOT suppress the tactile cue the deaf / HoH driver depends on.
/// An actuator whose [speak] is manually completed by the test — lets the
/// serialization tests hold one utterance "in the air" and prove a second
/// announce WAITS instead of speaking over it.
class _HoldingActuators implements AlertActuators {
  final List<String> speakStarts = <String>[];
  final List<String> speakEnds = <String>[];
  final List<Completer<void>> _completers = <Completer<void>>[];

  /// Completes the [i]th in-flight speak.
  void release(int i) => _completers[i].complete();

  @override
  Future<void> speak(String text, {required String localeTag}) async {
    speakStarts.add(text);
    final c = Completer<void>();
    _completers.add(c);
    await c.future;
    speakEnds.add(text);
  }

  @override
  Future<void> haptic(HapticCuePattern pattern) async {}

  @override
  Future<void> keepAwake(bool enabled) async {}
}

class _SpeakThrowsActuators implements AlertActuators {
  final List<HapticCuePattern> haptics = <HapticCuePattern>[];
  bool speakAttempted = false;

  @override
  Future<void> speak(String text, {required String localeTag}) async {
    speakAttempted = true;
    throw StateError('TTS engine fault (simulated)');
  }

  @override
  Future<void> haptic(HapticCuePattern pattern) async {
    haptics.add(pattern);
  }

  @override
  Future<void> keepAwake(bool enabled) async {}
}

void main() {
  group('AlertAnnouncer — whiteout reaches HER on audio AND haptic', () {
    test(
      'critical whiteout (ageingRural + ice) => speak(JA text, ja-JP) + '
      'critical haptic',
      () async {
        final fake = FakeAlertActuators();
        final announcer = AlertAnnouncer(actuators: fake);

        // The real catalog guidance HER's mother would receive: the ice
        // action string for the ageingRural profile. Sourced from the
        // package, not hardcoded, so the test tracks the publisher's wording.
        final explainer = AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.ice,
          DriverProfile.ageingRural,
        );
        final severity = severityForCondition(RoadSurfaceCondition.ice);
        expect(severity, AlertSeverity.critical);
        // Guard against silent-drift: the guidance is really Japanese.
        expect(explainer.localeTag, 'ja');
        expect(explainer.action, contains('凍結'));

        await announcer.announce(
          severity: severity,
          text: explainer.action,
          localeTag: explainer.localeTag,
        );

        // AUDIO channel fired with the correct JA text at the ja-JP voice tag.
        expect(fake.spoken, hasLength(1));
        expect(fake.spoken.single.text, explainer.action);
        expect(fake.spoken.single.localeTag, 'ja-JP');

        // HAPTIC channel fired the critical (3-pulse) cue — the deaf / HoH /
        // can't-hear-over-the-wind driver gets the SAME warning.
        expect(fake.haptics, [HapticCuePattern.critical]);
      },
    );

    test('warning (snow) => speak + warning haptic', () async {
      final fake = FakeAlertActuators();
      final announcer = AlertAnnouncer(actuators: fake);
      final explainer = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.snow,
        DriverProfile.ageingRural,
      );

      await announcer.announce(
        severity: severityForCondition(RoadSurfaceCondition.snow),
        text: explainer.action,
        localeTag: explainer.localeTag,
      );

      expect(fake.spoken, hasLength(1));
      expect(fake.haptics, [HapticCuePattern.warning]);
    });

    test(
      'foreign-tourist ice => EN text at en-US (locale fallback)',
      () async {
        final fake = FakeAlertActuators();
        final announcer = AlertAnnouncer(actuators: fake);
        final explainer = AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.ice,
          DriverProfile.foreignTouristSnowZone,
        );
        expect(explainer.localeTag, 'en');

        await announcer.announce(
          severity: AlertSeverity.critical,
          text: explainer.action,
          localeTag: explainer.localeTag,
        );

        expect(fake.spoken.single.localeTag, 'en-US');
        expect(fake.haptics, [HapticCuePattern.critical]);
      },
    );

    test(
      'info (dry) => announced on NEITHER channel (parity with voice gate)',
      () async {
        final fake = FakeAlertActuators();
        final announcer = AlertAnnouncer(actuators: fake);

        expect(severityForCondition(RoadSurfaceCondition.dry), AlertSeverity.info);

        await announcer.announce(
          severity: AlertSeverity.info,
          text: 'road is dry',
          localeTag: 'ja',
        );

        expect(fake.spoken, isEmpty);
        expect(fake.haptics, isEmpty);
      },
    );

    test(
      'OPS-059 independence: a TTS fault (speak throws) does NOT suppress the '
      'haptic — the deaf / HoH driver still gets the critical cue',
      () async {
        final throwing = _SpeakThrowsActuators();
        final announcer = AlertAnnouncer(actuators: throwing);

        // announce() must NOT propagate the speak() throw...
        await expectLater(
          announcer.announce(
            severity: AlertSeverity.critical,
            text: 'whiteout — critical',
            localeTag: 'ja',
          ),
          completes,
        );

        // ...the audio channel was attempted (and faulted)...
        expect(throwing.speakAttempted, isTrue);
        // ...and the haptic channel STILL fired the critical cue (parity held).
        expect(throwing.haptics, [HapticCuePattern.critical]);
      },
    );
  });

  group('AlertAnnouncer — cross-call serialization (no overlapping speech)',
      () {
    test(
      'two unawaited announces from independent timers never speak on top '
      'of each other: the second starts only after the first completes',
      () async {
        final holding = _HoldingActuators();
        final announcer = AlertAnnouncer(actuators: holding);

        // Both fired unawaited (the real call sites' shape: feed-loss re-warn
        // ticker vs rung-rise from a watchdog poll).
        final first = announcer.announce(
          severity: AlertSeverity.warning,
          text: 'first warning',
          localeTag: 'ja',
        );
        final second = announcer.announce(
          severity: AlertSeverity.warning,
          text: 'second warning',
          localeTag: 'ja',
        );
        await Future<void>.delayed(Duration.zero);

        // Only the FIRST utterance is in the air.
        expect(holding.speakStarts, ['first warning']);

        holding.release(0);
        await first;
        await Future<void>.delayed(Duration.zero);

        // The second starts only now — after the first finished.
        expect(holding.speakStarts, ['first warning', 'second warning']);
        holding.release(1);
        await second;
        expect(holding.speakEnds, ['first warning', 'second warning']);
      },
    );

    test('an info-class no-op does not occupy a queue slot', () async {
      final holding = _HoldingActuators();
      final announcer = AlertAnnouncer(actuators: holding);

      final real = announcer.announce(
        severity: AlertSeverity.warning,
        text: 'real warning',
        localeTag: 'ja',
      );
      // Fired while the real one is in the air; must return without queueing.
      await announcer.announce(
        severity: AlertSeverity.info,
        text: 'info — never announced',
        localeTag: 'ja',
      );
      await Future<void>.delayed(Duration.zero);
      expect(holding.speakStarts, ['real warning']);
      holding.release(0);
      await real;
      expect(holding.speakEnds, ['real warning']);
    });

    test(
      'a faulting utterance does not wedge the queue: the next announce '
      'still delivers',
      () async {
        final throwing = _SpeakThrowsActuators();
        final announcer = AlertAnnouncer(actuators: throwing);

        await announcer.announce(
          severity: AlertSeverity.critical,
          text: 'faults',
          localeTag: 'ja',
        );
        await announcer.announce(
          severity: AlertSeverity.warning,
          text: 'still delivers',
          localeTag: 'ja',
        );
        // Both haptics fired — the chain survived the first fault.
        expect(throwing.haptics,
            [HapticCuePattern.critical, HapticCuePattern.warning]);
      },
    );
  });
}
