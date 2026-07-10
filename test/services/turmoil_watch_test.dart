import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/services/turmoil_watch.dart';

JmaObservation _obs({
  double? precip10m,
  double? wind,
}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: 22.0,
    humidityPercent: 80,
    windMetersPerSecond: wind,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: '20260710143000',
    fetchedAt: DateTime(2026, 7, 10, 14, 30),
  );
}

void main() {
  group('evaluateTurmoilWatch — rain channel (JMA 強い雨 bound, 20 mm/h)', () {
    test('3.5 mm/10min (21 mm/h equivalent) → caution', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 3.5, wind: 2.0));
      expect(s.rain, TurmoilChannel.caution);
      expect(s.anyCaution, isTrue);
    });

    test('exactly at the bound (20/6 mm per 10 min) → caution (>=)', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 20.0 / 6.0, wind: 2.0));
      expect(s.rain, TurmoilChannel.caution);
    });

    test('3.0 mm/10min (18 mm/h equivalent, やや強い雨 band) → clear — '
        'the caution deliberately does NOT fire below 強い雨 (cry-wolf)', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 3.0, wind: 2.0));
      expect(s.rain, TurmoilChannel.clear);
      expect(s.anyCaution, isFalse);
    });

    test('measured 0.0 is a MEASURED dry → clear, not unknown', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 0.0, wind: 2.0));
      expect(s.rain, TurmoilChannel.clear);
    });

    test('missing precipitation → rain channel unknown, never clear', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: null, wind: 2.0));
      expect(s.rain, TurmoilChannel.unknown);
    });
  });

  group('evaluateTurmoilWatch — wind channel (JMA やや強い風 bound, 10 m/s)', () {
    test('12.0 m/s mean → caution', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 0.0, wind: 12.0));
      expect(s.wind, TurmoilChannel.caution);
      expect(s.anyCaution, isTrue);
    });

    test('exactly 10.0 m/s → caution (>= — the band lower bound)', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 0.0, wind: 10.0));
      expect(s.wind, TurmoilChannel.caution);
    });

    test('9.9 m/s → clear', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 0.0, wind: 9.9));
      expect(s.wind, TurmoilChannel.clear);
    });

    test('missing wind → wind channel unknown, never clear', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: 0.0, wind: null));
      expect(s.wind, TurmoilChannel.unknown);
    });
  });

  group('per-channel independence (honest partial abstain)', () {
    test('wind caution + rain unknown → still anyCaution', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: null, wind: 15.0));
      expect(s.wind, TurmoilChannel.caution);
      expect(s.rain, TurmoilChannel.unknown);
      expect(s.anyCaution, isTrue);
      expect(s.allUnknown, isFalse);
    });

    test('both missing → allUnknown', () {
      final s = evaluateTurmoilWatch(_obs(precip10m: null, wind: null));
      expect(s.allUnknown, isTrue);
      expect(s.anyCaution, isFalse);
    });
  });

  group('turmoilRowText — verdict + honest per-channel bounds', () {
    TurmoilWatchState eval({double? p, double? w}) =>
        evaluateTurmoilWatch(_obs(precip10m: p, wind: w));

    test('both cautions', () {
      expect(turmoilRowText(eval(p: 4.0, w: 12.0)), '⚠ 強い雨・強めの風を観測中');
    });

    test('rain only', () {
      expect(turmoilRowText(eval(p: 4.0, w: 3.0)), '⚠ 強い雨を観測中');
    });

    test('rain caution with wind unreported names the gap', () {
      expect(
        turmoilRowText(eval(p: 4.0, w: null)),
        '⚠ 強い雨を観測中（風は判定不能）',
      );
    });

    test('wind caution with rain unreported names the gap', () {
      expect(
        turmoilRowText(eval(p: null, w: 11.0)),
        '⚠ 強めの風を観測中（降水は判定不能）',
      );
    });

    test('clear both', () {
      expect(turmoilRowText(eval(p: 0.0, w: 2.0)), '該当なし');
    });

    test('clear with one channel unreported is NOT a clean 該当なし', () {
      expect(turmoilRowText(eval(p: 0.0, w: null)), '該当なし（風は判定不能）');
      expect(turmoilRowText(eval(p: null, w: 2.0)), '該当なし（降水は判定不能）');
    });

    test('all unknown → 判定不能', () {
      expect(
        turmoilRowText(eval(p: null, w: null)),
        '判定不能（降水・風の観測値が不足）',
      );
    });
  });

  group('turmoilSpokenText — possibility-graded, action-coupled, ja/en', () {
    TurmoilWatchState eval({double? p, double? w}) =>
        evaluateTurmoilWatch(_obs(precip10m: p, wind: w));

    test('nothing in caution → null (nothing to announce)', () {
      expect(turmoilSpokenText(eval(p: 0.0, w: 2.0), ja: true), isNull);
      expect(turmoilSpokenText(eval(p: null, w: null), ja: true), isNull);
    });

    test('rain line is possibility-graded (おそれ) and action-coupled', () {
      final line = turmoilSpokenText(eval(p: 4.0, w: 2.0), ja: true)!;
      expect(line, contains('強い雨'));
      expect(line, contains('おそれ'));
      expect(line, contains('速度を落とし'));
    });

    test('wind line does NOT overstate the JMA band (強めの風, not 強い風)',
        () {
      final line = turmoilSpokenText(eval(p: 0.0, w: 11.0), ja: true)!;
      expect(line, contains('強めの風'));
      expect(line, isNot(contains('強い風を')));
      expect(line, contains('ハンドル'));
    });

    test('combined line covers both hazards', () {
      final line = turmoilSpokenText(eval(p: 4.0, w: 11.0), ja: true)!;
      expect(line, contains('強い雨'));
      expect(line, contains('風'));
      expect(line, contains('慎重に'));
    });

    test('en parity exists for every caution shape', () {
      expect(turmoilSpokenText(eval(p: 4.0, w: 2.0), ja: false),
          contains('Heavy rain'));
      expect(turmoilSpokenText(eval(p: 0.0, w: 11.0), ja: false),
          contains('wind'));
      expect(turmoilSpokenText(eval(p: 4.0, w: 11.0), ja: false),
          contains('Heavy rain and strong wind'));
    });
  });
}
