/// W0 DETECTION-SURVIVAL — unit tests for the staleness policy helpers
/// (design §7 host-verifiable set: observedAtJstAsLocal parse/malformed;
/// observedAtJstInstant tz-correct bound; spokenHourJst FLOOR / no roll-forward).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/staleness_policy.dart';

void main() {
  group('observedAtJstAsLocal', () {
    test('parses a valid 14-digit yyyymmddHHMMSS key into a LOCAL DateTime', () {
      final dt = observedAtJstAsLocal('20260115063000');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 1);
      expect(dt.day, 15);
      expect(dt.hour, 6);
      expect(dt.minute, 30);
      expect(dt.second, 0);
      // Parsed as LOCAL (not UTC) — the comparison-against-now contract.
      expect(dt.isUtc, isFalse);
    });

    test('wrong length → null (caller treats as no-reading → absence-line)', () {
      expect(observedAtJstAsLocal(''), isNull);
      expect(observedAtJstAsLocal('2026011506300'), isNull); // 13 digits
      expect(observedAtJstAsLocal('202601150630000'), isNull); // 15 digits
    });

    test('non-digit content at 14 chars → null (malformed → absence path)', () {
      expect(observedAtJstAsLocal('BADKEYBADKEY!!'), isNull);
      expect(observedAtJstAsLocal('2026011506xx00'), isNull);
    });
  });

  group('spokenHourJst (FLOOR — never sounds newer than the observation)', () {
    test('truncates to the observation own hour, any minute', () {
      expect(spokenHourJst(DateTime(2026, 1, 15, 6, 0)), 6);
      expect(spokenHourJst(DateTime(2026, 1, 15, 6, 29)), 6);
      // The safety-critical cases: :30 and :50 must FLOOR to 6, never round up
      // to 7 (a stale reading must never be stamped an hour that sounds fresher).
      expect(spokenHourJst(DateTime(2026, 1, 15, 6, 30)), 6);
      expect(spokenHourJst(DateTime(2026, 1, 15, 6, 31)), 6);
      expect(spokenHourJst(DateTime(2026, 1, 15, 6, 50)), 6);
    });

    test('spoken hour is <= the true observation hour (never fresher)', () {
      for (final minute in [0, 15, 29, 30, 31, 45, 59]) {
        final obs = DateTime(2026, 1, 15, 6, minute);
        expect(spokenHourJst(obs), lessThanOrEqualTo(obs.hour));
      }
    });

    test('23:xx stays 23 (never rolls forward to 0 / the next day)', () {
      expect(spokenHourJst(DateTime(2026, 1, 15, 23, 0)), 23);
      expect(spokenHourJst(DateTime(2026, 1, 15, 23, 30)), 23);
      expect(spokenHourJst(DateTime(2026, 1, 15, 23, 59)), 23);
    });
  });

  group('observedAtJstInstant (tz-correct absolute instant for the bound)', () {
    test('interprets the digits as JST (UTC+9) → correct UTC instant', () {
      final utc = observedAtJstInstant('20260115063000');
      expect(utc, isNotNull);
      expect(utc!.isUtc, isTrue);
      // 06:30 JST == 21:30 UTC the previous day.
      expect(utc, DateTime.utc(2026, 1, 14, 21, 30, 0));
    });

    test('malformed key → null (caller treats as no-reading → absence)', () {
      expect(observedAtJstInstant('BADKEYBADKEY!!'), isNull);
      expect(observedAtJstInstant('2026011506300'), isNull); // 13 digits
    });

    test('bound is host-timezone-independent: age = now.toUtc() - instant', () {
      final instant = observedAtJstInstant('20260115063000')!;
      // A device wall-clock 30 min after the observation, on ANY timezone.
      final now = instant.add(const Duration(minutes: 30));
      expect(now.toUtc().difference(instant), const Duration(minutes: 30));
      expect(now.toUtc().difference(instant) > kSlowHazardRetainWindow, isFalse);
      // 61 min → past the 60-min bound.
      final now61 = instant.add(const Duration(minutes: 61));
      expect(now61.toUtc().difference(instant) > kSlowHazardRetainWindow, isTrue);
    });
  });

  group('staleness bound constants', () {
    test('slow-hazard retain window is 60 min; fast-hazard fresh is 20 min', () {
      expect(kSlowHazardRetainWindow, const Duration(minutes: 60));
      expect(kFastHazardFreshWindow, const Duration(minutes: 20));
    });
  });
}
