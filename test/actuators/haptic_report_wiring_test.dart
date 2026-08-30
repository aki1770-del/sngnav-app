// The one link `flutter_test` cannot exercise, asserted mechanically.
//
// `defaultAlertActuators()` returns a NoOp under the test binding (proven in
// alert_actuators_test.dart), and `MobileAlertActuators` hands its reporting
// callbacks to the channel it BUILDS — so no runtime test in this suite can
// observe whether the production app actually connects
// HardenedHapticChannel -> HER screen. That link was missing on 2026-08-21
// and nothing failed: the channel was unit-tested, the chip was widget-tested
// with an injected flag, and between them sat an unwired factory parameter.
//
// A source assertion is not elegant. It is, however, the only instrument in
// this suite that could have surfaced THAT counter-example, and an instrument
// that could not surface the counter-example has measured nothing.
//
// Deliberately asserts the SPEECH wiring too: the defect was an ASYMMETRY, so
// the test that guards it must fail if either half is cut.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The source span of `name(` ... matching `)`, or null if absent.
String? _callSpan(String source, String name) {
  final start = source.indexOf('$name(');
  if (start < 0) return null;
  var depth = 0;
  for (var i = start + name.length; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return null;
}

void main() {
  final actuators =
      File('lib/actuators/mobile_alert_actuators.dart').readAsStringSync();
  final main_ = File('lib/main.dart').readAsStringSync();

  group('the tactile report reaches HER screen in the PRODUCTION build', () {
    test('defaultAlertActuators accepts both haptic reporting callbacks', () {
      final decl = _callSpan(actuators, 'AlertActuators defaultAlertActuators');
      expect(decl, isNotNull,
          reason: 'the production actuator factory was renamed or removed');
      expect(decl, contains('onHapticUnverified'));
      expect(decl, contains('onHapticVerified'));
      // The asymmetry guard: audio must still be there too.
      expect(decl, contains('onSpeechUnverified'));
      expect(decl, contains('onSpeechVerified'));
    });

    test('...and FORWARDS them to MobileAlertActuators', () {
      final body = actuators.substring(
          actuators.indexOf('AlertActuators defaultAlertActuators'));
      final ctor = _callSpan(body, 'MobileAlertActuators');
      expect(ctor, isNotNull,
          reason: 'the factory no longer constructs MobileAlertActuators');
      expect(ctor, contains('onHapticUnverified:'),
          reason: 'accepted and dropped is the same silence as never accepted');
      expect(ctor, contains('onHapticVerified:'));
      expect(ctor, contains('onSpeechUnverified:'));
    });

    test('main.dart wires both callbacks at the production call site', () {
      final call = _callSpan(main_, 'defaultAlertActuators');
      expect(call, isNotNull,
          reason: 'the app no longer builds its actuators through the factory');
      expect(call, contains('onHapticUnverified:'),
          reason: 'a report nothing listens to reaches no pixel — the exact '
              'state measured on device 2026-08-21');
      expect(call, contains('onHapticVerified:'),
          reason: 'without the clear path a transient fault pins the chip for '
              'the rest of HER drive');
      expect(call, contains('onSpeechUnverified:'));
      expect(call, contains('onSpeechVerified:'));
    });

    test('the flag the callbacks drive is the one the chip reads', () {
      // Boolean form deliberately: `expect(wholeFile, contains(...))` prints
      // 4000 lines of main.dart on failure, and an instrument whose output
      // cannot be read is barely an instrument.
      void has(String needle, String why) =>
          expect(main_.contains(needle), isTrue, reason: '$needle missing: $why');

      has('_hapticUnverified', 'the page owns no tactile flag');
      has("Key('haptic-unverified-chip')", 'the flag reaches no pixel');
      // Listener attached AND removed: a leaked listener on a page-owned
      // notifier is a defect the speech twin already guards against.
      has('_hapticUnverified.addListener', 'the chip never rebuilds');
      has('_hapticUnverified.removeListener', 'listener leaked past dispose');
      has("Key('haptic-unverified-note')",
          'the haptics-only promise in the media-muted row is never withdrawn');
    });
  });

  // ⚑ ANTI-DRIFT, per AAA's 2026-08-22 verdict §2.1.
  //
  // The defect AAA found was not a missing feature — it was two channels on
  // two different cadences. Audio was re-probed at FOUR triggers (app open, a
  // 45 s ticker, real drive start, mock drive start); the tactile channel was
  // probed only when a warning was already owed. Adding a haptic probe at
  // four call sites of its own would recreate the same defect the first time
  // someone adds a fifth audio trigger and forgets the tactile one.
  //
  // So the two probes share ONE method, and this test is what keeps them
  // sharing it. It fails if either is lifted out.
  group('the two eyes-off channels are probed on ONE cadence', () {
    test('one method drives both probes', () {
      final body = _callSpan(main_, 'void _probeAlertChannelReadiness');
      expect(body, isNotNull,
          reason: 'the shared probe method was renamed or removed');
      final start = main_.indexOf('void _probeAlertChannelReadiness');
      // The method body: from its signature to the next top-level `\n  }`.
      final end = main_.indexOf('\n  }', start);
      expect(end, greaterThan(start));
      final method = main_.substring(start, end);
      expect(method.contains('audioReadinessProbe'), isTrue,
          reason: 'the audio probe left the shared cadence');
      expect(method.contains('hapticReadinessProbe'), isTrue,
          reason: 'the tactile probe left the shared cadence — this is the '
              'exact asymmetry AAA ruled PUSHBACK load-bearing');
    });

    test('every trigger calls the shared method, and there are still four',
        () {
      final calls = '_probeAlertChannelReadiness()'.allMatches(main_).length;
      // 1 declaration-adjacent call site count: initState, the ticker, real
      // drive start, mock drive start. The declaration itself is not a call.
      expect(calls, 5,
          reason: 'four call sites plus the declaration itself. Audio had four '
              'triggers when AAA measured it; if a fifth is added, change this '
              'number deliberately — do not let the tactile channel silently '
              'keep four');
    });

    test('the caution the probe raises reaches HER pre-drive surface', () {
      void has(String needle, String why) =>
          expect(main_.contains(needle), isTrue, reason: '$needle missing: $why');
      has('_hapticAvailable', 'the page holds no tactile readiness state');
      has("Key('haptic-unavailable-caution')", 'the probe reaches no pixel');
    });
  });
}
