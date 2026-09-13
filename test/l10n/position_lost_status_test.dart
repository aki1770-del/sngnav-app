/// The status line under the map when HER position is lost says how old the
/// last trusted position is, never a radius, and never 「±Infinitym」.
///
/// Until 2026-09-13 the line was built as
/// `'${modeLabel} · 最後の位置 ±${radius.toStringAsFixed(0)}m'`. In lost with no
/// trusted fix ever, the controller's radius is `double.infinity`, and Dart
/// prints it as `Infinity`: she read 「現在地 不明 · 最後の位置 ±Infinitym」
/// (derived by HIE, `bd6ebc4_every_mode/MANIFEST.txt`, scenario 09).
///
/// The ages below come from the real position controller, driven the way the
/// app drives it, not from chosen numbers.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization_fallback/localization_fallback.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/drive_hud_controller.dart';
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

const _ja = AppL10n(Locale('ja'));
const _en = AppL10n(Locale('en'));

final _t0 = DateTime.utc(2026, 1, 14, 21, 0);

PositionFix _fix(double acc) => fixFromSample(
      latitude: 39.7195,
      longitude: 140.1180,
      accuracyMeters: acc,
      timestamp: _t0,
    );

/// A controller that took one trusted fix and then heard nothing for [d].
LocalizationEstimate _drought(Duration d) {
  final hud =
      DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
  hud.onPositionFix(_fix(15), now: _t0);
  hud.poll(now: _t0.add(d));
  return hud.estimate!;
}

void main() {
  group('from the real controller', () {
    test('lost 180 s after the last trusted fix', () {
      final e = _drought(const Duration(seconds: 180));
      expect(e.mode, LocalizationMode.lost, reason: 'control');
      expect(_ja.positionLostStatus(e.secondsSinceTrustedFix),
          '現在地 不明 · 最後の位置 3分前');
      expect(_en.positionLostStatus(e.secondsSinceTrustedFix),
          'Position unknown · last position 3 min ago');
    });

    test('lost 90 min after the last trusted fix', () {
      final e = _drought(const Duration(minutes: 90));
      expect(e.mode, LocalizationMode.lost, reason: 'control');
      expect(_ja.positionLostStatus(e.secondsSinceTrustedFix),
          '現在地 不明 · 最後の位置 1時間30分前');
      expect(_en.positionLostStatus(e.secondsSinceTrustedFix),
          'Position unknown · last position 1h 30m ago');
    });

    test('lost with no trusted fix ever: no age is claimed, and no Infinity',
        () {
      final hud =
          DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
      hud.onPositionFix(_fix(-1), now: _t0);
      final e = hud.estimate!;
      expect(e.mode, LocalizationMode.lost, reason: 'control');
      expect(e.secondsSinceTrustedFix, double.infinity, reason: 'control');
      expect(e.confidenceRadiusMeters, double.infinity, reason: 'control');
      expect(_ja.positionLostStatus(e.secondsSinceTrustedFix),
          '現在地 不明 · 最後の位置 なし');
      expect(_en.positionLostStatus(e.secondsSinceTrustedFix),
          'Position unknown · no last position');
    });

    test('lost the instant a trusted fix is too imprecise (800 m): under a '
        'minute', () {
      final hud =
          DriveHudController(actuators: FakeAlertActuators(), localeTag: 'ja');
      hud.onPositionFix(_fix(800), now: _t0);
      final e = hud.estimate!;
      expect(e.mode, LocalizationMode.lost, reason: 'control');
      expect(_ja.positionLostStatus(e.secondsSinceTrustedFix),
          '現在地 不明 · 最後の位置 1分以内');
      expect(_en.positionLostStatus(e.secondsSinceTrustedFix),
          'Position unknown · last position within 1 min');
    });
  });

  group('boundaries', () {
    test('whole minutes, rounded down: the age is a lower bound', () {
      expect(_ja.positionLostStatus(59.999), '現在地 不明 · 最後の位置 1分以内');
      expect(_ja.positionLostStatus(60), '現在地 不明 · 最後の位置 1分前');
      expect(_ja.positionLostStatus(179.9), '現在地 不明 · 最後の位置 2分前');
      expect(_ja.positionLostStatus(25 * 3600), '現在地 不明 · 最後の位置 25時間0分前');
    });

    test('NaN, infinity and negative claim no age', () {
      for (final s in [double.nan, double.infinity, -1.0]) {
        expect(_ja.positionLostStatus(s), '現在地 不明 · 最後の位置 なし',
            reason: '$s');
        expect(_en.positionLostStatus(s), 'Position unknown · no last position',
            reason: '$s');
      }
    });

    test('never a radius, never Infinity or NaN, in either language', () {
      for (final l in [_ja, _en]) {
        for (final s in [0.0, 30.0, 180.0, 5400.0, 1e300, double.infinity,
            double.nan, -5.0]) {
          final line = l.positionLostStatus(s);
          expect(line, isNot(contains('±')), reason: line);
          expect(line, isNot(contains('Infinity')), reason: line);
          expect(line, isNot(contains('NaN')), reason: line);
        }
      }
    });
  });

  test('the prefix is the drive HUD\'s own name for lost — one vocabulary', () {
    const hud = DriveHudLocalizer();
    expect(_ja.positionLostStatus(180),
        startsWith('${hud.modeLabel(LocalizationMode.lost, 'ja')} · '));
    expect(_en.positionLostStatus(180),
        startsWith('${hud.modeLabel(LocalizationMode.lost, 'en')} · '));
  });
}
