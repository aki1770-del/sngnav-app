/// W0 DETECTION-SURVIVAL LAYER — feed-loss survival WIRING tests (design §7).
///
/// Max honest in-env verification (same bound as fake_alert_actuators.dart):
/// proves the app RETAINS the last-good observation across a feed loss and
/// makes the correct stale-vs-absence-vs-silent decision from an INJECTED clock
/// — the honest time-stamped black-ice line survives the network dying, and a
/// stale reading is NEVER spoken as live. It does NOT prove HER HEARS anything
/// (on-device HEAR is DEFERRED — OPS-066): audibility, TTS pronunciation of the
/// hour+頃, and real feed-loss timing are the device hour's job.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart'
    show HapticCuePattern;
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/invisible_ice_watch.dart';

import '../support/fake_alert_actuators.dart';

// The retained observation is always stamped 06:30 JST; the injected clock is
// what moves it across the 60-min bound. spokenHourJst FLOORs, so 06:30 → 6 →
// the spoken stamp is 「6時頃」 (floor never sounds newer than the observation).
const String _key0630 = '20260115063000';

// HER phone wall-clock expressed as a TRUE instant anchored to the 06:30 JST
// observation, so the retain/expire bound compare (now.toUtc() - observedInstant)
// is HOST-TIMEZONE-INDEPENDENT — the test passes on a JST or a UTC CI host alike.
// (The old naive-local clock only matched the bound on a JST host.)
DateTime _clockAt(Duration age) => DateTime.utc(2026, 1, 15, 6, 30, 0)
    .subtract(const Duration(hours: 9))
    .add(age);

JmaObservation _obs({
  required double? temp,
  required int? humidity,
  required double? precip10m,
  double? wind,
  String observedAtJstKey = _key0630,
}) {
  return JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: temp,
    humidityPercent: humidity,
    windMetersPerSecond: wind,
    snowDepthCm: null,
    precipitation10mMm: precip10m,
    visibilityMeters: null,
    observedAtJstKey: observedAtJstKey,
    fetchedAt: DateTime(2026, 1, 15, 6, 30),
  );
}

// The founding radiative-frost window (invisible_ice_watch_test): +2°C / 70% /
// measured no precip → InvisibleIceWatchResult.watch.
JmaObservation _iceObs({String key = _key0630}) =>
    _obs(temp: 2.0, humidity: 70, precip10m: 0.0, observedAtJstKey: key);

// Warm dry-air morning → ice CLEAR, no turmoil → nothing announced live.
JmaObservation _clearObs() =>
    _obs(temp: 8.0, humidity: 70, precip10m: 0.0, wind: 2.0);

// Rain-turmoil (24 mm/h equiv) → turmoil rain CAUTION; precip>0 → ice CLEAR.
JmaObservation _rainTurmoilObs() =>
    _obs(temp: 2.0, humidity: 70, precip10m: 4.0, wind: 2.0);

// Sustained-wind-only caution: mean wind >= kWindCautionMeanMs (10 m/s) → a
// live wind CAUTION; warm + dry + no precip → ice CLEAR, no rain turmoil. Used
// to pin the KNOWN dropped-gale limitation on feed loss.
JmaObservation _windObs() =>
    _obs(temp: 8.0, humidity: 70, precip10m: 0.0, wind: 12.0);

const _iceStaleStamp = '時頃の観測では';
const _notLiveClause = '最新の情報は取得できていません';
const _absenceLine = '路面状況を取得できていません';
const _liveLooksWet = '路面は濡れて見えても';

// The JMA panel's refresh button is labelled 'Re-fetch' in the success state and
// 'Retry' in the failure state, and it sits far down the scroll (off-screen at
// pump). ensureVisible + the state-correct label is required — a bare
// find.text('Re-fetch').tap silently MISSES off-screen.
Future<void> _refetch(WidgetTester tester, {required bool fromSuccess}) async {
  final finder = find.text(fromSuccess ? 'Re-fetch' : 'Retry');
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

void main() {
  // ---- builder unit assertions (design §4 load-bearing clauses) ----
  group('staleInvisibleBlackIceSpokenText', () {
    test('ja carries the past-frame stamp AND the not-live clause', () {
      final s = staleInvisibleBlackIceSpokenText(hourJst: 7, ja: true);
      expect(s, contains('7時頃の観測では'));
      expect(s, contains(_notLiveClause));
      // NEVER reads as the live catalog line.
      expect(s, isNot(contains('注意。')));
    });
    test('en carries the explicit "not a live reading" disclaimer', () {
      final s = staleInvisibleBlackIceSpokenText(hourJst: 7, ja: false);
      expect(s, contains('around 7'));
      expect(s, contains('not a live reading'));
    });
  });

  // ---- sub-zero frozen-surface WARNING: the live announce path (Chair
  // calibration 2026-07-23). These pump SngnavApp end-to-end and inspect the
  // fake actuator, so the bool→enum latch refactor and the iceRose fold cannot
  // be silently re-muted with the suite still green (impl-review 2026-07-23).
  group('sub-zero frozen-surface live announce', () {
    // -3 °C / no precip → subZeroFrozen; and, crucially, watch NEVER fires here
    // (that needs temp > 0), so this pins that the sub-zero verdict folds into
    // iceRose and is not dropped by the `if (!iceRose && !turmoilRose) return;`
    // guard on a calm sub-zero morning (critic Finding 1).
    JmaObservation subZeroObs() =>
        _obs(temp: -3.0, humidity: 70, precip10m: 0.0);

    testWidgets('calm sub-zero morning speaks the distinct line exactly once',
        (tester) async {
      final fake = FakeAlertActuators();
      await tester.pumpWidget(SngnavApp(
        actuators: fake,
        locale: const Locale('ja'),
        clock: () => _clockAt(const Duration(minutes: 5)),
        jmaFetch: () async => JmaSuccess(subZeroObs()),
      ));
      await tester.pump();
      await tester.pump();

      expect(fake.spoken.where((s) => s.text == kSubZeroFrozenSpokenJa),
          hasLength(1),
          reason: 'a live sub-zero fetch speaks the frozen-surface line — the '
              'fold into iceRose must pass the announce guard even though '
              'watch never fires below zero');
      // It reaches the deaf/HoH driver on the haptic channel too, warning-tier.
      expect(fake.haptics, contains(HapticCuePattern.warning));
      // It is NOT the black-ice surprise line.
      expect(fake.spoken.where((s) => s.text.contains('ブラックアイスバーン')),
          isEmpty);
    });

    testWidgets('a passing snow band (outOfScope) does NOT re-nag on return '
        'to sub-zero', (tester) async {
      final fake = FakeAlertActuators();
      JmaResult next = JmaSuccess(subZeroObs());
      await tester.pumpWidget(SngnavApp(
        actuators: fake,
        locale: const Locale('ja'),
        clock: () => _clockAt(const Duration(minutes: 5)),
        jmaFetch: () async => next,
      ));
      await tester.pump();
      await tester.pump();
      final afterFirst =
          fake.spoken.where((s) => s.text == kSubZeroFrozenSpokenJa).length;
      expect(afterFirst, 1);

      // Snow band passes over: precip>0 at -3 °C → outOfScope. Then it clears:
      // precip 0 → subZeroFrozen again. The latch must stay sticky across the
      // outOfScope blip so the 14 s line is not re-spoken.
      next = JmaSuccess(_obs(temp: -3.0, humidity: 70, precip10m: 4.0));
      await _refetch(tester, fromSuccess: true);
      next = JmaSuccess(subZeroObs());
      await _refetch(tester, fromSuccess: true);

      expect(fake.spoken.where((s) => s.text == kSubZeroFrozenSpokenJa),
          hasLength(1),
          reason: 'sub-zero is once-per-entry; a snow-band scope-exit is not '
              'an all-clear and must not re-arm the warning');
    });

    testWidgets('a genuine warm-up to CLEAR then re-freeze DOES re-warn',
        (tester) async {
      final fake = FakeAlertActuators();
      JmaResult next = JmaSuccess(subZeroObs());
      await tester.pumpWidget(SngnavApp(
        actuators: fake,
        locale: const Locale('ja'),
        clock: () => _clockAt(const Duration(minutes: 5)),
        jmaFetch: () async => next,
      ));
      await tester.pump();
      await tester.pump();

      // Warms to a measured dry-air clear (+8 °C), then re-freezes.
      next = JmaSuccess(_clearObs());
      await _refetch(tester, fromSuccess: true);
      next = JmaSuccess(subZeroObs());
      await _refetch(tester, fromSuccess: true);

      expect(fake.spoken.where((s) => s.text == kSubZeroFrozenSpokenJa),
          hasLength(2),
          reason: 'a MEASURED all-clear is a genuine exit; re-freezing after '
              'it is a new entry and re-warns');
    });

    testWidgets('crossing 0 °C (watch <-> sub-zero) re-speaks the CORRECT '
        'distinct line', (tester) async {
      final fake = FakeAlertActuators();
      JmaResult next = JmaSuccess(_iceObs()); // +2 °C → watch (surprise line)
      await tester.pumpWidget(SngnavApp(
        actuators: fake,
        locale: const Locale('ja'),
        clock: () => _clockAt(const Duration(minutes: 5)),
        jmaFetch: () async => next,
      ));
      await tester.pump();
      await tester.pump();
      expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)),
          hasLength(1));
      expect(fake.spoken.where((s) => s.text == kSubZeroFrozenSpokenJa),
          isEmpty);

      // Temperature drops through 0 °C → subZeroFrozen. A different verdict, so
      // it re-announces — with the sub-zero line, not the surprise line.
      next = JmaSuccess(subZeroObs());
      await _refetch(tester, fromSuccess: true);
      expect(fake.spoken.where((s) => s.text == kSubZeroFrozenSpokenJa),
          hasLength(1),
          reason: 'a real 0 °C crossing is a tier change and re-speaks');
      // The surprise line was not repeated on the crossing.
      expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)),
          hasLength(1));
    });
  });

  // ---- feed-loss decision table (injected clock) ----

  testWidgets('fresh-live: JmaSuccess + ice=watch → the LIVE line (not stale)',
      (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 5)),
      jmaFetch: () async => JmaSuccess(_iceObs()),
    ));
    await tester.pump();
    await tester.pump();

    expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)), hasLength(1),
        reason: 'a live successful fetch speaks the live looks-wet line');
    expect(fake.spoken.where((s) => s.text.contains(_iceStaleStamp)), isEmpty,
        reason: 'a live fetch never speaks the stale-stamped variant');
    expect(fake.spoken.where((s) => s.text.contains(_absenceLine)), isEmpty);
  });

  testWidgets(
      'feed loss, cache ≤60 min + ice=watch → STALE-STAMPED (both ja clauses), '
      'warning severity', (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 30)), // 30 ≤ 60
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length;

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, hasLength(1),
        reason: 'feed loss fires the stale line exactly once on entry');
    final stale = newLines.single;
    expect(stale.text, contains('6時頃の観測では')); // spokenHourJst FLOORs 06:30→6
    expect(stale.text, contains(_notLiveClause),
        reason: 'the only spoken guarantee HER is not hearing a live reading');
    expect(stale.localeTag, 'ja-JP');
    // Severity is warning on BOTH new announces (clears the audibility floor,
    // never cries critical): every haptic fired is the warning cue.
    expect(fake.haptics, isNotEmpty);
    expect(fake.haptics.every((h) => h == HapticCuePattern.warning), isTrue,
        reason: 'stale + live ice announces are warning-tier, not critical');
  });

  testWidgets('feed loss, cache >60 min → the honest ABSENCE-LINE',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_clearObs()); // clear → no live announce
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 61)), // 61 > 60
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length;

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, hasLength(1));
    expect(newLines.single.text, contains(_absenceLine));
    expect(newLines.single.localeTag, 'ja-JP');
    expect(newLines.where((s) => s.text.contains(_iceStaleStamp)), isEmpty,
        reason: 'past the retain bound → never a stale announce');
  });

  testWidgets(
      'feed loss at EXACTLY 60 min + ice=watch → still RETAINED (> semantics)',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 60)), // exactly 60
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length;

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, hasLength(1),
        reason: 'exactly 60 min is NOT > 60 → retained, stale announce fires');
    expect(newLines.single.text, contains(_iceStaleStamp));
    expect(newLines.single.text, contains(_notLiveClause));
    expect(newLines.where((s) => s.text.contains(_absenceLine)), isEmpty,
        reason: 'not expired → the absence-line must NOT fire at the boundary');
  });

  testWidgets('feed loss, cache ≤60 min + turmoil-only (ice clear) → SILENT',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_rainTurmoilObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 30)),
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length;

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, isEmpty,
        reason: 'FAST hazard is silent when stale (cry-wolf); a ≤60 non-ice '
            'reading is honest silence, never a false absence-line');
  });

  testWidgets('feed loss, NO cache (first fetch fails) → ABSENCE-LINE',
      (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(Duration.zero),
      jmaFetch: () async => const JmaFailure('offline from boot'),
    ));
    await tester.pump();
    await tester.pump();

    // On the one night the network is dead from the start, HER still hears the
    // honest absence-line — never silence-as-all-clear.
    expect(fake.spoken.where((s) => s.text.contains(_absenceLine)), hasLength(1));
    final absence =
        fake.spoken.singleWhere((s) => s.text.contains(_absenceLine));
    expect(absence.localeTag, 'ja-JP');
    // Severity warning: spoken at all (>= warning) AND the haptic is warning.
    expect(fake.haptics, [HapticCuePattern.warning]);
  });

  testWidgets(
      'malformed observedAt on the cache → ABSENCE-LINE (parse-null path)',
      (tester) async {
    final fake = FakeAlertActuators();
    // Prime an ice=watch success but with an UNPARSEABLE observedAt key.
    JmaResult next = JmaSuccess(_iceObs(key: 'BADKEYBADKEY!!'));
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 5)),
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length;

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, hasLength(1));
    expect(newLines.single.text, contains(_absenceLine),
        reason: 'an unparseable stamp is treated as no-reading → absence, '
            'never a stale announce with a fabricated hour');
    expect(newLines.where((s) => s.text.contains(_iceStaleStamp)), isEmpty);
  });

  testWidgets(
      'two consecutive losses ≤60 + ice: stale KEEPS announcing (Chair) AND '
      'absence NEVER fires (cache never cleared on failure)', (tester) async {
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

    // First loss → stale fires (cache present).
    next = const JmaFailure('offline #1');
    await _refetch(tester, fromSuccess: true);
    expect(
        fake.spoken.where((s) => s.text.contains(_iceStaleStamp)), hasLength(1));

    // Second loss → the SLOW hazard KEEPS announcing (Chair: retain + keep
    // announcing), honestly re-stamped each feed-loss cycle (unlike the
    // once-per-entry absence line). And if the cache had been WIPED on the first
    // failure this would fire the ABSENCE-line (no cache) — it must NOT.
    await _refetch(tester, fromSuccess: false); // still in failure state → Retry
    expect(fake.spoken.where((s) => s.text.contains(_absenceLine)), isEmpty,
        reason: 'the last-good observation is NEVER cleared on a feed loss');
    expect(
        fake.spoken.where((s) => s.text.contains(_iceStaleStamp)), hasLength(2),
        reason: 'the stale black-ice line re-warns each feed-loss cycle');
  });

  testWidgets(
      'no-cache: the absence-line is gated once per entry (two losses → one)',
      (tester) async {
    final fake = FakeAlertActuators();
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(Duration.zero),
      jmaFetch: () async => const JmaFailure('offline from boot'),
    ));
    await tester.pump();
    await tester.pump();
    // Boot loss (no cache) fired the absence-line once.
    expect(
        fake.spoken.where((s) => s.text.contains(_absenceLine)), hasLength(1));

    // A SECOND no-cache loss must NOT re-spam the absence-line (gated per
    // entry; unlike a persistent HAZARD, an absence does not re-warn every
    // cycle). Button is 'Retry' in the failure state.
    await _refetch(tester, fromSuccess: false);
    expect(
        fake.spoken.where((s) => s.text.contains(_absenceLine)), hasLength(1),
        reason: 'absence fires once per dead-zone entry, then is gated');
  });

  // ---- MUST regression (review finding #1): loss → RESTORE re-arm ----

  testWidgets(
      'live-ice → (>60 dead-zone → ABSENCE) → restore still-watch: the LIVE '
      'line RE-ANNOUNCES (dead-zone reset re-armed the rise gate)',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 61)), // >60 → loss=absence
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    // (1) Fresh success, ice=watch → the LIVE black-ice line fires once.
    expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)), hasLength(1),
        reason: 'the live hazard was announced on the fresh fetch');

    // (2) Network dies for >60 min in the pass → the honest ABSENCE-LINE.
    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);
    expect(fake.spoken.where((s) => s.text.contains(_absenceLine)), hasLength(1),
        reason: 'HER hears "conditions unavailable" in the true dead-zone');

    // (3) Network returns; ice STILL watch → the LIVE line MUST fire AGAIN.
    // Without the finding #1 reset, iceRose = fired && !alreadyAnnounced would
    // stay false and the confirming live warning would be silently swallowed —
    // HER's last spoken word about the road would remain "unavailable".
    next = JmaSuccess(_iceObs());
    await _refetch(tester, fromSuccess: false); // was in failure state → Retry
    expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)), hasLength(2),
        reason: 'after a dead-zone absence, a returning live hazard re-announces');
  });

  testWidgets(
      'live-ice → within-60 blip (STALE re-warns) → restore still-watch: the '
      'live line does NOT re-announce (stale branch keeps the gate — no cry-wolf)',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 30)), // ≤60 → loss=stale
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)), hasLength(1));

    // Short blip ≤60 → the STALE-STAMPED line re-warns (HER stays warned).
    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);
    expect(fake.spoken.where((s) => s.text.contains(_iceStaleStamp)), hasLength(1),
        reason: 'a within-bound feed loss keeps warning via the stamped line');

    // Restore, still watch: the stale branch deliberately did NOT reset the gate
    // (HER was warned throughout the blip), so the live line does NOT re-fire —
    // the reset is scoped to a TRUE dead-zone only, not every feed-loss cycle.
    next = JmaSuccess(_iceObs());
    await _refetch(tester, fromSuccess: false);
    expect(fake.spoken.where((s) => s.text.contains(_liveLooksWet)), hasLength(1),
        reason: 'no per-blip re-announce cry-wolf; stale line already covered it');
  });

  // ---- SHOULD (test-quality): an ICE cache PAST the bound expires to absence --

  testWidgets(
      'feed loss, ICE cache PAST 60 min → ABSENCE-LINE (expired ice is never '
      'stale-announced — closes the cry-wolf-past-window row)', (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 61)), // ice cache, but >60
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length; // the live line already fired here

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, hasLength(1));
    expect(newLines.single.text, contains(_absenceLine),
        reason: 'an ice window past the 60-min bound expires to the absence-line');
    expect(newLines.where((s) => s.text.contains(_iceStaleStamp)), isEmpty,
        reason: 'never a stale black-ice announce about ice that may already be gone');
  });

  // ---- NICE: the en-locale stale path end-to-end (not just the builder) ----

  testWidgets(
      'feed loss, cache ≤60 + ice=watch, EN locale → stale line carries the '
      '"not a live reading" disclaimer end-to-end', (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_iceObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('en'),
      clock: () => _clockAt(const Duration(minutes: 30)),
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    final before = fake.spoken.length;

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    final newLines = fake.spoken.sublist(before);
    expect(newLines, hasLength(1));
    expect(newLines.single.text, contains('not a live reading'),
        reason: 'the en survival line keeps the explicit not-live disclaimer');
    expect(newLines.single.text, contains('black ice'));
    expect(newLines.single.localeTag, 'en-US');
  });

  // ---- KNOWN LIMITATION pin (review finding #2, design §3/§8 #2) ----

  testWidgets(
      'KNOWN LIMITATION: a live SUSTAINED-WIND caution is DROPPED (silent) on '
      'feed loss — recorded, deliberately-deferred (OPS-068 fail-toward-keeping)',
      (tester) async {
    final fake = FakeAlertActuators();
    JmaResult next = JmaSuccess(_windObs());
    await tester.pumpWidget(SngnavApp(
      actuators: fake,
      locale: const Locale('ja'),
      clock: () => _clockAt(const Duration(minutes: 5)), // fresh, ≤60
      jmaFetch: () async => next,
    ));
    await tester.pump();
    await tester.pump();
    // A LIVE wind caution was announced on the fresh success — a real hazard
    // that then gets dropped (this is what makes the drop meaningful, not moot).
    final before = fake.spoken.length;
    expect(before, greaterThan(0),
        reason: 'a live sustained-wind caution was announced before the feed died');

    next = const JmaFailure('offline');
    await _refetch(tester, fromSuccess: true);

    // DOCUMENTED intentional silence: wind is in the FAST lane and is NOT
    // retained on feed loss, so a still-valid gale is dropped. This pins the
    // dropped-gale gap as a RECORDED decision. If wind later gets its own retain
    // window + stale-stamped line (the fail-toward-keeping fix), this flips
    // deliberately. See the KNOWN LIMITATION comment in main.dart's feed-loss
    // branch + unresolved_safety_items.
    final newLines = fake.spoken.sublist(before);
    expect(newLines, isEmpty,
        reason: 'KNOWN LIMITATION: a still-valid sustained gale is dropped on '
            'feed loss; a ≤60 non-ice reading is honest silence, not a false '
            'absence-line (the absence-line fires only on true no-reading)');
  });
}
