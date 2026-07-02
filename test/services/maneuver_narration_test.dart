/// (e) The confidence gate — the HER differentiator — proven off-device.
///
/// These are PURE logic tests of `ManeuverNarrator.decide`, the seam adapter,
/// and the next-maneuver selector. They prove the safety contract that a turn
/// is spoken only when the honest position allows it:
///   gpsTrusted → SPEAK, gpsSuspect → HEDGE, deadReckoning/lost → SUPPRESS.
///
/// What they CANNOT prove (device-observable, DEFERRED per OPS-066): that HER
/// actually hears the line, and the real turn-trigger timing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;
import 'package:navigation_safety_core/navigation_safety_core.dart'
    show AlertSeverity, RoadSurfaceCondition;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:sngnav_app/services/maneuver_narration.dart';

RouteManeuver maneuver({
  int index = 1,
  String instruction = 'Right onto Main St',
  String type = 'right',
  double lengthKm = 0.4,
  double timeSeconds = 30,
  LatLng? position,
}) =>
    RouteManeuver(
      index: index,
      instruction: instruction,
      type: type,
      lengthKm: lengthKm,
      timeSeconds: timeSeconds,
      position: position ?? const LatLng(39.72, 140.10),
    );

void main() {
  const narrator = ManeuverNarrator();

  group('seam adapter RouteManeuver → NavigationManeuver', () {
    test('maps every field losslessly', () {
      final m = maneuver(
        index: 3,
        instruction: 'Sharp left onto 国道13号',
        type: 'sharp_left',
        lengthKm: 1.25,
        timeSeconds: 88,
        position: const LatLng(39.6, 140.1),
      );
      final n = toNavigationManeuver(m);
      expect(n.index, m.index);
      expect(n.instruction, m.instruction);
      expect(n.type, m.type);
      expect(n.lengthKm, m.lengthKm);
      expect(n.timeSeconds, m.timeSeconds);
      expect(n.position, m.position);
    });
  });

  group('the confidence gate (JA — HER)', () {
    test('gpsTrusted → SPEAK the JA turn plainly', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'right'),
        mode: LocalizationMode.gpsTrusted,
        icyTurn: false,
      );
      expect(d.confidence, NarrationConfidence.speak);
      expect(d.shouldAnnounce, isTrue);
      expect(d.text, contains('右折'));
      // NOT the raw English instruction (D4: no English maneuvers to HER).
      expect(d.text, isNot(contains('Main St')));
      expect(d.severity, AlertSeverity.warning);
      expect(d.icyCoupled, isFalse);
    });

    test('gpsSuspect → HEDGE: names the turn but softens + asks to confirm', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'right'),
        mode: LocalizationMode.gpsSuspect,
        icyTurn: false,
      );
      expect(d.confidence, NarrationConfidence.hedge);
      expect(d.shouldAnnounce, isTrue);
      expect(d.text, contains('右折')); // still names the maneuver
      expect(d.text, contains('不確か')); // but flags the position as uncertain
      expect(d.text, contains('ご確認')); // and asks HER to confirm
      expect(d.severity, AlertSeverity.warning);
    });

    test('deadReckoning → SUPPRESS: no announce, no turn, empty text', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'right'),
        mode: LocalizationMode.deadReckoning,
        icyTurn: false,
      );
      expect(d.confidence, NarrationConfidence.suppressed);
      expect(d.shouldAnnounce, isFalse);
      expect(d.text, isEmpty);
      // The confidently-wrong hazard this gate exists to prevent: NO turn word.
      expect(d.text, isNot(contains('右折')));
      // Even the severity is below the announcer's speak gate.
      expect(d.severity, AlertSeverity.info);
    });

    test('lost → SUPPRESS: no announce, no turn, empty text', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'left'),
        mode: LocalizationMode.lost,
        icyTurn: false,
      );
      expect(d.confidence, NarrationConfidence.suppressed);
      expect(d.shouldAnnounce, isFalse);
      expect(d.text, isEmpty);
      expect(d.text, isNot(contains('左折')));
      expect(d.severity, AlertSeverity.info);
    });

    test('SUPPRESS ignores icyTurn — a lost dot stays fully silent', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'right'),
        mode: LocalizationMode.lost,
        icyTurn: true, // hazard present, but position is lost
      );
      expect(d.shouldAnnounce, isFalse);
      expect(d.text, isEmpty);
      expect(d.icyCoupled, isFalse); // no coupling built on the suppress path
    });
  });

  group('icy-turn coupling', () {
    test('SPEAK + icy → couples the icy advisory + escalates to critical', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'right'),
        mode: LocalizationMode.gpsTrusted,
        icyTurn: true,
      );
      expect(d.shouldAnnounce, isTrue);
      expect(d.icyCoupled, isTrue);
      expect(d.text, contains('右折'));
      expect(d.text, contains('凍結')); // "the turn may be icy"
      expect(d.severity, AlertSeverity.critical);
    });

    test('HEDGE + icy → hedged AND icy-coupled AND critical', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'right'),
        mode: LocalizationMode.gpsSuspect,
        icyTurn: true,
      );
      expect(d.confidence, NarrationConfidence.hedge);
      expect(d.icyCoupled, isTrue);
      expect(d.text, contains('不確か'));
      expect(d.text, contains('凍結'));
      expect(d.severity, AlertSeverity.critical);
    });
  });

  group('English locale', () {
    test('gpsTrusted en → English turn, no Japanese', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'left'),
        mode: LocalizationMode.gpsTrusted,
        icyTurn: false,
        localeTag: 'en',
      );
      expect(d.text, contains('a left turn'));
      expect(d.text, isNot(contains('左折')));
    });

    test('en + icy → couples the "The turn may be icy." clause', () {
      final d = narrator.decide(
        maneuver: maneuver(type: 'left'),
        mode: LocalizationMode.gpsTrusted,
        icyTurn: true,
        localeTag: 'en',
      );
      expect(d.text, contains('The turn may be icy'));
    });
  });

  group('nextActionableManeuver', () {
    test('skips the depart bookend, returns the first real turn', () {
      final list = [
        maneuver(index: 0, type: 'depart', instruction: 'Depart'),
        maneuver(index: 1, type: 'right'),
        maneuver(index: 2, type: 'left'),
      ];
      expect(nextActionableManeuver(list)?.type, 'right');
    });

    test('empty list → null', () {
      expect(nextActionableManeuver(const []), isNull);
    });

    test('only a depart → returns it (nothing else to surface)', () {
      final list = [maneuver(index: 0, type: 'depart')];
      expect(nextActionableManeuver(list)?.type, 'depart');
    });

    test('an arrive counts as actionable', () {
      final list = [
        maneuver(index: 0, type: 'depart'),
        maneuver(index: 1, type: 'arrive'),
      ];
      expect(nextActionableManeuver(list)?.type, 'arrive');
    });
  });

  group('isSlipperySurface — icy-coupling fires ONLY on genuine ice (MUST)', () {
    test('genuinely slippery surfaces couple the icy advisory', () {
      expect(isSlipperySurface(RoadSurfaceCondition.ice), isTrue);
      expect(isSlipperySurface(RoadSurfaceCondition.wetIce), isTrue);
      expect(isSlipperySurface(RoadSurfaceCondition.snow), isTrue);
      expect(isSlipperySurface(RoadSurfaceCondition.slush), isTrue);
    });
    test('a dry / merely-wet / unknown road NEVER raises a false icy warning',
        () {
      // The regression this pins: a dry road under a suspect GPS fix must not
      // couple a CRITICAL "the turn may be icy" (the old heightened-caution
      // predicate did exactly that).
      expect(isSlipperySurface(RoadSurfaceCondition.dry), isFalse);
      expect(isSlipperySurface(RoadSurfaceCondition.wet), isFalse);
      expect(isSlipperySurface(RoadSurfaceCondition.unknown), isFalse);
    });
  });
}
