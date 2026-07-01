/// WS5 — [AlertAnnouncer] tests. The heart of the accessibility floor:
/// a whiteout-class hazard must reach the driver on BOTH channels (audio +
/// haptic), off the same severity gate, with the correct JA text + locale.
library;

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
}
