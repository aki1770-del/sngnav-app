/// N15 — every feed-loss SPOKEN line has a VISIBLE counterpart, and the panel
/// never contradicts the speaker.
///
/// Founding defect: during feed loss the JMA panel said 'Cached data is NOT
/// shown — staleness must be visible' while the voice was WARNING FROM that
/// cache (the stale black-ice re-warn) and, in the dead zone, speaking the
/// plan-time forecast memory. A deaf/HoH or muted-media driver got the
/// contradiction and none of the content.
///
/// These tests pin BOTH halves of the fix:
///   (a) the shared [feedLossVerdict] decision table (the voice path and the
///       panel compute from the SAME function, so they cannot drift), and
///   (b) counterpart IDENTITY — the visible card text is compared to the
///       actually-spoken text captured by the fake actuators, not to a copy
///       of the expected string (a test that re-types the string would go
///       green if both channels drifted together; comparing across the two
///       real channels cannot).
///
/// Honest bound (OPS-066): widget-level code verification only — on-device
/// rendering, real feed-loss timing, and audibility are DEFERRED to the next
/// APK pass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/forecast_validity.dart';
import 'package:sngnav_app/services/jma_forecast_fetch.dart';
import 'package:sngnav_app/services/trip_hazard_memory.dart';

import '../support/fake_alert_actuators.dart';

// Same anchors as feed_loss_survival_test.dart: the retained observation is
// stamped 06:30 JST; the injected clock moves it across the 60-min bound.
const String _key0630 = '20260115063000';

DateTime _clockAt(Duration age) => DateTime.utc(2026, 1, 15, 6, 30, 0)
    .subtract(const Duration(hours: 9))
    .add(age);

JmaObservation _obs({
  required double? temp,
  required int? humidity,
  required double? precip10m,
  String observedAtJstKey = _key0630,
}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: temp,
    humidityPercent: humidity,
    windMetersPerSecond: null,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: observedAtJstKey,
    fetchedAt: DateTime(2026, 1, 15, 6, 30),
  );
}

// The founding radiative-frost window: +2°C / 70% / measured no precip → watch.
JmaObservation _iceObs({String key = _key0630}) =>
    _obs(temp: 2.0, humidity: 70, precip10m: 0.0, observedAtJstKey: key);

// Warm dry-air morning → ice CLEAR → within-bound feed loss is honest silence.
JmaObservation _clearObs() => _obs(temp: 8.0, humidity: 70, precip10m: 0.0);

/// A snow hazard on JMA's OWN 6-hourly boundaries (06:00 JST → 12:00 JST),
/// publisher-declared — the memory she captures at plan time.
ForecastHazard _snowHazard() => ForecastHazard(
      kind: ForecastHazardKind.snow,
      window: ValidityWindow(
        start: DateTime.utc(2026, 1, 14, 21, 0), // 06:00 JST
        end: DateTime.utc(2026, 1, 15, 3, 0), // 12:00 JST
        provenance: ValidityProvenance.publisherDeclared,
      ),
      publisherText: '雪　所により　ふぶく',
      source: 'JMA 秋田地方気象台',
      issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
      areaName: '沿岸',
    );

TripHazardMemory _memoryAt(DateTime capturedAt) =>
    TripHazardMemory(hazards: [_snowHazard()], capturedAt: capturedAt);

// The panel's refresh button label depends on state and sits down the scroll;
// a bare tap silently MISSES off-screen (feed_loss_survival_test discipline).
Future<void> _refetch(WidgetTester tester, {required bool fromSuccess}) async {
  final finder = find.text(fromSuccess ? 'Re-fetch' : 'Retry');
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

String? _singleTextUnder(WidgetTester tester, Key key) {
  final texts = find.descendant(
    of: find.byKey(key),
    matching: find.byType(Text),
  );
  return tester.widget<Text>(texts.first).data;
}

void main() {
  // ---- (a) the shared decision table (pure) ----
  group('feedLossVerdict', () {
    test('no cache → absence', () {
      final v = feedLossVerdict(
        cached: null,
        memory: null,
        now: _clockAt(Duration.zero),
        spokenJa: true,
      );
      expect(v, isA<FeedLossAbsence>());
    });

    test('unparseable observedAt stamp → absence (never a fabricated hour)',
        () {
      final v = feedLossVerdict(
        cached: _iceObs(key: 'BADKEYBADKEY!!'),
        memory: null,
        now: _clockAt(const Duration(minutes: 5)),
        spokenJa: true,
      );
      expect(v, isA<FeedLossAbsence>());
    });

    test('cache past 60 min, no memory → absence', () {
      final v = feedLossVerdict(
        cached: _iceObs(),
        memory: null,
        now: _clockAt(const Duration(minutes: 61)),
        spokenJa: true,
      );
      expect(v, isA<FeedLossAbsence>());
    });

    test('cache ≤60 min + ice window → stale ice with FLOORED hour + age', () {
      final v = feedLossVerdict(
        cached: _iceObs(),
        memory: null,
        now: _clockAt(const Duration(minutes: 30)),
        spokenJa: true,
      );
      expect(v, isA<FeedLossStaleIce>());
      final s = v as FeedLossStaleIce;
      expect(s.hourJst, 6, reason: '06:30 floors to 6 — never sounds fresher');
      expect(s.ageMinutes, 30);
    });

    test('exactly 60 min + ice → still RETAINED (> semantics, not >=)', () {
      final v = feedLossVerdict(
        cached: _iceObs(),
        memory: null,
        now: _clockAt(const Duration(minutes: 60)),
        spokenJa: true,
      );
      expect(v, isA<FeedLossStaleIce>());
      expect((v as FeedLossStaleIce).ageMinutes, 60);
    });

    test('cache ≤60 min, no slow hazard → retained-quiet (honest silence, '
        'fields shown stale — never the absence line)', () {
      final v = feedLossVerdict(
        cached: _clearObs(),
        memory: null,
        now: _clockAt(const Duration(minutes: 30)),
        spokenJa: true,
      );
      expect(v, isA<FeedLossRetainedQuiet>());
      expect((v as FeedLossRetainedQuiet).ageMinutes, 30);
    });

    test('expired cache + memory VALID NOW (ja) → forecast memory, carrying '
        'the exact spoken line + capture time', () {
      final captured = _clockAt(Duration.zero);
      final v = feedLossVerdict(
        cached: _iceObs(),
        memory: _memoryAt(captured),
        now: _clockAt(const Duration(minutes: 90)), // 08:00 JST, in-window
        spokenJa: true,
      );
      expect(v, isA<FeedLossForecastMemory>());
      final f = v as FeedLossForecastMemory;
      expect(f.line, kForecastSnowValidJa);
      expect(f.capturedAt, captured);
      expect(f.spokenAloud, isTrue,
          reason: 'ja surface + bundled mouth covers the line → spoken');
    });

    test('expired cache + memory valid now, EN spoken → forecast memory on '
        'the VISIBLE channel (en counterpart line), NOT spoken aloud (the en '
        'forecast voice stays a recorded bound, not a claim — locale must '
        'not delete a held hazard from the screen)', () {
      final captured = _clockAt(Duration.zero);
      final v = feedLossVerdict(
        cached: _iceObs(),
        memory: _memoryAt(captured),
        now: _clockAt(const Duration(minutes: 90)),
        spokenJa: false,
      );
      expect(v, isA<FeedLossForecastMemory>());
      final f = v as FeedLossForecastMemory;
      expect(f.line, kForecastSnowValidEn);
      expect(f.capturedAt, captured);
      expect(f.spokenAloud, isFalse,
          reason: 'screen-only: the voice keeps the honest absence line');
    });

    test('memory whose publisher window does NOT cover now → absence '
        '(a forecast outside its declared window is never shown or spoken)',
        () {
      final v = feedLossVerdict(
        cached: null,
        memory: _memoryAt(_clockAt(Duration.zero)),
        // 13:00 JST — past the 12:00 JST window end.
        now: _clockAt(const Duration(hours: 6, minutes: 30)),
        spokenJa: true,
      );
      expect(v, isA<FeedLossAbsence>());
    });
  });

  // ---- (b) the visible counterparts, compared to the ACTUAL spoken text ----

  testWidgets(
      'feed loss ≤60 + ice: the panel shows the STALE banner + the retained '
      'fields + a visible card IDENTICAL to the spoken stale line — never '
      '"Cached data is NOT shown"', (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 30)),
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    // The voice re-warned with the stamped line…
    final spokenStale = fake.spoken
        .lastWhere((s) => s.text.contains('時頃の観測では'))
        .text;
    // …and the SCREEN shows the IDENTICAL text (counterpart identity across
    // the two real channels, not against a re-typed constant).
    expect(find.byKey(const Key('stale-ice-visible')), findsOneWidget);
    expect(_singleTextUnder(tester, const Key('stale-ice-visible')),
        spokenStale);

    // Prominent staleness label, with the real age.
    expect(find.byKey(const Key('jma-stale-banner')), findsOneWidget);
    final banner = _singleTextUnder(tester, const Key('jma-stale-banner'))!;
    expect(banner, contains('未更新'));
    expect(banner, contains('30分'));

    // The retained fields ARE shown (the reading the voice warns from).
    expect(find.text('秋田 (32402)'), findsOneWidget);
    expect(find.text('2026-01-15 06:30 JST'), findsOneWidget);

    // The contradiction is gone.
    expect(find.textContaining('Cached data is NOT shown'), findsNothing);
    // And no absence card — we hold a valid retained reading.
    expect(find.byKey(const Key('conditions-unknown-visible')), findsNothing);
  });

  testWidgets(
      'feed loss ≤60, no slow hazard: retained fields + banner, and NO stale '
      'watch verdict re-rendered (a stale 該当なし would read as current calm)',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_clearObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 30)),
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    expect(find.byKey(const Key('jma-stale-banner')), findsOneWidget);
    expect(find.text('秋田 (32402)'), findsOneWidget);
    // No hazard card (the voice was silent), no absence card (a reading is
    // held), and CRUCIALLY no watch-verdict row recomputed from stale data.
    expect(find.byKey(const Key('stale-ice-visible')), findsNothing);
    expect(find.byKey(const Key('conditions-unknown-visible')), findsNothing);
    expect(find.textContaining('該当なし'), findsNothing);
    expect(find.textContaining('Cached data is NOT shown'), findsNothing);
  });

  testWidgets(
      'feed loss with NO cache: the visible card is IDENTICAL to the spoken '
      'absence line', (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(Duration.zero),
      jmaFetch: () async => const JmaFailure('offline from boot'),
    ));
    await tester.pump();
    await tester.pump();

    final spokenAbsence = fake.spoken
        .lastWhere((s) => s.text.contains('路面状況を取得できていません'))
        .text;
    expect(find.byKey(const Key('conditions-unknown-visible')), findsOneWidget);
    expect(
      _singleTextUnder(tester, const Key('conditions-unknown-visible')),
      spokenAbsence,
    );
    // No retained display and no stale banner — there is nothing retained.
    expect(find.byKey(const Key('jma-stale-banner')), findsNothing);
    expect(find.byKey(const Key('stale-ice-visible')), findsNothing);
    expect(find.textContaining('Cached data is NOT shown'), findsNothing);
  });

  testWidgets(
      'dead zone at T+90 with a plan-time memory: the forecast card shows the '
      'IDENTICAL text the voice speaks, the capture caption, and the honest '
      'empty-observation note', (tester) async {
    final fake = FakeAlertActuators();
    // Mutable clock: plan time first (06:35 JST), then the dead zone (08:00).
    var now = _clockAt(const Duration(minutes: 5));
    JmaResult next = JmaSuccess(_clearObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => now,
      jmaFetch: () async => next,
      // PLAN TIME: the forward forecast the memory is captured from — JMA's
      // own 6-hourly window covering her whole morning.
      jmaForecastFetch: () async => JmaForecastSuccess(
        hazards: [_snowHazard()],
        issuedAt: DateTime.utc(2026, 1, 14, 20, 0),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // T+90: the observation is EXPIRED (90 > 60) but the publisher's declared
    // window (06:00–12:00 JST) still covers the clock.
    now = _clockAt(const Duration(minutes: 90));
    next = const JmaFailure('the centre is gone');
    await _refetch(tester, fromSuccess: true);

    // The voice spoke the forecast-memory line (once, gated)…
    final spokenForecast = fake.spoken
        .where((s) => s.text.contains('これは観測ではなく予報です'))
        .toList();
    expect(spokenForecast, hasLength(1),
        reason: 'the forecast memory is spoken once per dead-zone entry');
    // …and never the absence line (we KNOW something true).
    expect(
        fake.spoken.where((s) => s.text.contains('路面状況を取得できていません')),
        isEmpty);

    // The SCREEN shows the identical line.
    expect(find.byKey(const Key('forecast-memory-visible')), findsOneWidget);
    expect(
      _singleTextUnder(tester, const Key('forecast-memory-visible')),
      spokenForecast.single.text,
    );
    // With the plan-time caption (exact clock text is host-timezone-dependent;
    // the load-bearing clauses are 出発前 + 観測ではありません).
    expect(find.textContaining('出発前'), findsWidgets);
    expect(find.textContaining('観測ではありません'), findsOneWidget);
    // And the observation lane is honestly empty — the card is never dressed
    // as an observation.
    expect(find.byKey(const Key('jma-no-valid-observation')), findsOneWidget);
    expect(find.byKey(const Key('conditions-unknown-visible')), findsNothing);
    expect(find.byKey(const Key('jma-stale-banner')), findsNothing);
    expect(find.textContaining('Cached data is NOT shown'), findsNothing);
  });
}
