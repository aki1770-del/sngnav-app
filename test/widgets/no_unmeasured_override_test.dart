/// Nothing that is not a measurement lowers, clears, ages out or hides a
/// caution her card shows from a measurement (ruled 2026-09-15; made an
/// invariant 2026-09-16).
///
/// Why, written before the act. On b0f74e7 the demo visibility band took
/// precedence over the station's reading (`_mockVisibilityMeters ??` the
/// measured value, with age 0). Under a measured 80 m one choice of クリア took
/// the top rung, its cause and its announce line off her card, and closed the
/// measured whiteout so it would be told again as new. Moving the control to
/// the development page removes the hand, not the precedence: a debug build,
/// a later control, or any code that writes the same state reaches it.
///
/// The invariant, for every input that is not a measurement (the demo band,
/// the Akita mock position, the simulated GPS blackout clock, the simulated
/// road condition, the driver type):
///  (a) under a measured condition, the rung on her card is never lower, and
///      the cause is never gone, after the input is set than before;
///  (b) it never closes a measured whiteout: a whiteout a measurement opened
///      is closed only by a measurement, so it is not told twice as new;
///  (c) with no fresh reading, the card's own floor (visibility not measured
///      is not clear) is not cleared by a demo value;
///  (d) it may ADD caution: a demo value lower than the reading raises the rung;
///  (e) while a value that is not a measurement is what her card shows, the
///      card says a test value is in force (a keyed line; its words are not
///      ruled here).
///
/// (e) narrowed 2026-09-18 (AAA R58 W1, produced by FSE at R106) for the mock
/// position ONLY, and only because the same ruling moved the statement to a
/// place that never goes quiet. The card-wide line claimed the CARD shows a
/// test value; under a measured visibility the rung came from the measurement,
/// so the claim was wrong about the rung. It is now drawn for the mock only
/// where the 理由 row carries `positionUncertain` — and, in the same ruling,
/// the mock's own trust and uncertainty rows say the position is a test.
/// Measured at R106 and the reason these are one change and not two: a trusted
/// mock can NEVER reach `positionUncertain` (taking the mock cancels the
/// position watchdog, so nothing polls the estimate down), so the narrowing
/// alone does not shrink the mock case — it empties it. The two halves are
/// complementary: where the trust row is GPS 良好/GPS 不確か the rows carry it,
/// and where the mode is GPS 途絶/現在地 不明 the 理由 row carries
/// `positionUncertain` and the line carries it. Neither half stands alone.
///
/// Cut to bite before and after the demo controls leave her page: each control
/// is found by its key on her page, and if it is not there, on the development
/// page (`SngnavApp(developerPageEntry: true)`), then her page is read again.
/// The rung is read from the banner's headline through the app's localizer;
/// the cause through the localizer's own reason words; tells from the
/// recording actuators. Bound: host widget tests; nothing heard or felt.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show CautionReason, DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart' as re;
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

const _hud = DriveHudLocalizer();
final _stopLine = _hud.spokenGuidance(DriveAction.considerStopping, 'ja');
String _reason(CautionReason r) => _hud.reasonLabel(r, 'ja');

/// The keyed lines invariant (e) asks for. Their words are not ruled here.
const _testValueOnCard = Key('drive-hud-test-value');
const _testRoadOnTurnCard = Key('maneuver-test-road-condition');

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;

// ------------------------------------------------------------- the weather ----

var _visibilities = <int?>[80];
var _failing = <bool>[false];
var _fetches = 0;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _jma() async {
  final i = _fetches++;
  if (i < _failing.length && _failing[i]) {
    return const JmaFailure('test: this refresh failed');
  }
  return JmaSuccess(
    JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: 5,
      humidityPercent: 50,
      windMetersPerSecond: 2,
      snowDepthCm: null,
      precipitation10mMm: 0,
      visibilityMeters:
          _visibilities[i < _visibilities.length
              ? i
              : _visibilities.length - 1],
      observedAtJstKey: _jstKey(_now),
      fetchedAt: _now,
    ),
  );
}

// --------------------------------------------------------------- the app ----

class _OneTurnEngine implements re.RoutingEngine {
  @override
  Future<re.RouteResult> calculateRoute(re.RouteRequest request) async =>
      re.RouteResult(
        shape: [request.origin, request.destination],
        maneuvers: const [
          re.RouteManeuver(
            index: 0,
            instruction: 'Depart',
            type: 'depart',
            lengthKm: 0.3,
            timeSeconds: 30,
            position: LatLng(39.70, 140.09),
          ),
          re.RouteManeuver(
            index: 1,
            instruction: 'Turn right',
            type: 'right',
            lengthKm: 1.2,
            timeSeconds: 90,
            position: LatLng(39.71, 140.10),
          ),
        ],
        totalDistanceKm: 1.5,
        totalTimeSeconds: 120,
        summary: 'fake',
        engineInfo: const re.EngineInfo(name: 'mock'),
      );
  @override
  Future<bool> isAvailable() async => true;
  @override
  re.EngineInfo get info => const re.EngineInfo(name: 'mock');
  @override
  Future<void> dispose() async {}
}

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  List<int?> visibilities = const [80],
  List<bool> failing = const [false],
  bool route = false,
  // AAA R58 W1 re-audit (FSE R114). Defaults to ja so every existing call site
  // is byte-unchanged; the en case exists because AppL10n.supportedLocales is
  // [ja, en] and the app follows the DEVICE, so an English-locale driver reads
  // these same rows. The ja default is this harness's, never the app's.
  Locale locale = const Locale('ja'),
}) async {
  final a = FakeAlertActuators();
  _now = _start;
  _visibilities = [...visibilities];
  _failing = [...failing];
  _fetches = 0;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    SngnavApp(
      key: UniqueKey(),
      actuators: a,
      locale: locale,
      clock: () => _now,
      jmaFetch: _jma,
      positionSource: source,
      developerPageEntry: true,
      routingEngineFactory: route ? () => _OneTurnEngine() : null,
    ),
  );
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _advance(
  WidgetTester tester,
  Duration d, {
  void Function()? each,
}) async {
  var left = d;
  while (left > Duration.zero) {
    final step = left > const Duration(seconds: 15)
        ? const Duration(seconds: 15)
        : left;
    _now = _now.add(step);
    each?.call();
    await tester.pump(step);
    left -= step;
  }
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Position _position(DateTime at) => Position(
  latitude: 39.7186,
  longitude: 140.1024,
  timestamp: at,
  accuracy: 10,
  hasAccuracy: true,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _Positioned {
  final platform = StreamController<Position>();
  Stream<PositionFix> source() => herPositionStream(
    isServiceEnabled: () async => true,
    checkPermission: () async => LocationPermission.whileInUse,
    positionStream: () => platform.stream,
  );
  void fix() => platform.add(_position(_now));
}

Stream<PositionFix> _failedStart() => herPositionStream(
  isServiceEnabled: () async => throw StateError('no location provider'),
);

Future<void> _tapShare(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  expect(
    find.byKey(const Key('share-location-button')),
    findsNothing,
    reason: 'control: sharing started',
  );
}

// ------------------------------------------ controls, wherever they are ----

bool _drawn(Finder f) => f.evaluate().isNotEmpty;

Future<void> _openDevPage(WidgetTester tester) async {
  final entry = find.byKey(const Key('developer-page-entry'));
  expect(entry, findsOneWidget, reason: 'control: the development page entry');
  await tester.tap(entry);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(
    find.byKey(const Key('developer-page')),
    findsOneWidget,
    reason: 'control: the development page opened',
  );
}

Future<void> _closeDevPage(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(
    find.byKey(const Key('developer-page')),
    findsNothing,
    reason: 'control: back on her page',
  );
}

/// Runs [act] where the control found by [finder] is: her page, else the
/// development page. Returns false when neither page draws it.
Future<bool> _whereItIs(
  WidgetTester tester,
  Finder finder,
  Future<void> Function() act,
) async {
  if (_drawn(finder)) {
    await act();
    return true;
  }
  await _openDevPage(tester);
  final there = _drawn(finder);
  if (there) await act();
  await _closeDevPage(tester);
  return there;
}

Future<void> _chooseItem(
  WidgetTester tester,
  Finder dropdown,
  bool Function(Object?) isValue,
) async {
  await tester.ensureVisible(dropdown);
  await tester.pump();
  await tester.tap(dropdown);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(
    find
        .byWidgetPredicate((w) => w is DropdownMenuItem && isValue(w.value))
        .last,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _chooseBand(WidgetTester tester, double? meters) async {
  final band = find.byKey(const Key('drive-hud-visibility'));
  final found = await _whereItIs(
    tester,
    band,
    () => _chooseItem(tester, band, (v) => v == meters),
  );
  expect(found, isTrue, reason: 'control: the demo band is drawn somewhere');
}

Future<void> _pressBlackout(WidgetTester tester) async {
  final b = find.byKey(const Key('drive-hud-blackout-button'));
  final found = await _whereItIs(tester, b, () async {
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await tester.pump();
    await tester.pump();
  });
  expect(found, isTrue, reason: 'control: the blackout simulator is drawn');
}

/// Taps the Akita mock position if it is drawn and enabled anywhere. Returns
/// whether it was tapped.
Future<bool> _tapMockIfOffered(WidgetTester tester) async {
  final m = find.byKey(const Key('use-mock-button'));
  var tapped = false;
  await _whereItIs(tester, m, () async {
    final w = tester.widget<ButtonStyleButton>(m);
    if (w.onPressed == null) return;
    await tester.ensureVisible(m);
    await tester.pump();
    await tester.tap(m);
    await tester.pump();
    await tester.pump();
    tapped = true;
  });
  return tapped;
}

Finder _dropdownOf(String enumName) => find.byWidgetPredicate(
  (w) => w is DropdownButton && '${w.value}'.startsWith('$enumName.'),
);

Future<void> _chooseEnum(
  WidgetTester tester,
  String enumName,
  String value,
) async {
  final d = _dropdownOf(enumName);
  final found = await _whereItIs(
    tester,
    d,
    () => _chooseItem(tester, d, (v) => '$v' == '$enumName.$value'),
  );
  expect(found, isTrue, reason: 'control: the $enumName selector is drawn');
}

// ------------------------------------------------------- what she is shown ----

typedef _Card = ({DriveAction? rung, bool cause, int stopTold});

bool _shown(String words) => find.textContaining(words).evaluate().isNotEmpty;

_Card _card(FakeAlertActuators a, CautionReason cause) => (
  rung: rungOnCard(),
  cause: _shown(_reason(cause)),
  stopTold: a.spoken.where((s) => s.text == _stopLine).length,
);

int _rank(DriveAction? r) => r == null ? -1 : r.index;

void _expectNotLower(_Card after, _Card before, String when) {
  expect(
    _rank(after.rung),
    greaterThanOrEqualTo(_rank(before.rung)),
    reason: '$when: the rung fell from ${before.rung} to ${after.rung}',
  );
  if (before.cause) {
    expect(after.cause, isTrue, reason: '$when: the cause left her card');
  }
}

const _lowVis = CautionReason.lowVisibility;

// ------------------------------------ AAA R52: words and the spoken prefix ----
// Literals, not the app's constants: a test that imported the words it checks
// would pass on any words.

const _cardWordsJa = 'テスト値を使った表示です（測定ではありません）';
const _iceWordsJa = '凍結の表示はテスト値です（路面は測定していません）';
const _prefixJa = 'テスト値です。';

// AAA R58 W1, the half that carries the honesty when the card-wide line is
// narrowed away: the mock's own position rows. Mock only — GPS 途絶 and
// 現在地 不明 are unchanged, because a card in those modes already carries the
// card-wide line (positionUncertain is in its 理由 row by construction).
const _mockTrustWordsJa = 'テスト位置（GPS ではありません）';
const _mockRadiusWordsJa = '誤差 約 35 m（テスト値）';

// The SAME two rows on an English device. AppL10n.supportedLocales is
// [ja, en] and the app follows the DEVICE, so these rows ship to an
// English-locale driver exactly as the ja pair ships to hers. Until FSE R114
// they were asserted in ja only: shipped and unasserted in en.
const _mockTrustWordsEn = 'Test position (not GPS)';
const _mockRadiusWordsEn = 'within ~35 m (test value)';

/// [line] was spoken with the test-value prefix as the utterance before it.
bool _toldAsTest(FakeAlertActuators a, String line) {
  for (var i = 1; i < a.spoken.length; i++) {
    if (a.spoken[i].text == line && a.spoken[i - 1].text == _prefixJa) {
      return true;
    }
  }
  return false;
}

/// [line] was spoken with no test-value prefix before it.
bool _toldBare(FakeAlertActuators a, String line) {
  for (var i = 0; i < a.spoken.length; i++) {
    if (a.spoken[i].text == line &&
        (i == 0 || a.spoken[i - 1].text != _prefixJa)) {
      return true;
    }
  }
  return false;
}

String _textOf(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data ?? '';

void main() {
  // ================================================== (O1) the demo band ====

  group('(a) the demo band under a fresh measured 80 m', () {
    for (final band in const [1500.0, 700.0, 300.0]) {
      testWidgets(
        'a positioned share: choosing ${band.toInt()} m leaves the top rung '
        'and its cause on her card',
        (tester) async {
          final p = _Positioned();
          final a = await _boot(tester, source: p.source);
          await _tapShare(tester);
          p.fix();
          await _advance(tester, const Duration(seconds: 1), each: p.fix);
          final before = _card(a, _lowVis);
          expect(
            before.rung,
            DriveAction.considerStopping,
            reason: 'control: a measured 80 m is the top rung',
          );
          expect(before.cause, isTrue, reason: 'control: the cause is shown');

          await _chooseBand(tester, band);
          await _advance(tester, const Duration(seconds: 15), each: p.fix);
          _expectNotLower(_card(a, _lowVis), before, 'band ${band.toInt()} m');
        },
      );
    }

    testWidgets(
      'no share: choosing 1500 m leaves the top rung and cause; clearing it '
      'does not tell the same whiteout again',
      (tester) async {
        final a = await _boot(tester);
        await _advance(tester, const Duration(seconds: 1));
        final before = _card(a, _lowVis);
        expect(
          before.rung,
          DriveAction.considerStopping,
          reason: 'control: the whiteout is on her card with no share',
        );
        expect(before.stopTold, 1, reason: 'control: told once when it opened');

        await _chooseBand(tester, 1500);
        await _advance(tester, const Duration(seconds: 15));
        _expectNotLower(_card(a, _lowVis), before, 'band 1500 m, no share');

        await _chooseBand(tester, null);
        await _advance(tester, const Duration(seconds: 15));
        expect(
          _card(a, _lowVis).stopTold,
          1,
          reason:
              'a measured whiteout closed by a demo value and opened again '
              'is told twice',
        );
      },
    );

    testWidgets(
      'a failed start after 1500 m was chosen: the top rung and the stop '
      'line, as for any failed start in a measured whiteout',
      (tester) async {
        final a = await _boot(tester, source: _failedStart);
        await _advance(tester, const Duration(seconds: 1));
        await _chooseBand(tester, 1500);
        final told = _card(a, _lowVis).stopTold;
        await _tapShare(tester);
        await _advance(tester, const Duration(seconds: 16));
        final after = _card(a, _lowVis);
        expect(
          after.rung,
          DriveAction.considerStopping,
          reason: 'the demo band hid the measured whiteout from a failed start',
        );
        expect(after.cause, isTrue, reason: 'the cause left her card');
        expect(
          after.stopTold,
          greaterThan(told),
          reason: 'the failed start in a measured whiteout was not told',
        );
      },
    );
  });

  group('(b) the demo band never closes a whiteout a measurement opened', () {
    for (final band in const [null, 300.0]) {
      testWidgets('no share: 80 m, the next refresh fails (stale), band '
          '${band?.toInt() ?? 'untouched'}, then a fresh 80 m: told once', (
        tester,
      ) async {
        final a = await _boot(
          tester,
          visibilities: const [80, 80, 80],
          failing: const [false, true],
        );
        await _advance(tester, const Duration(seconds: 1));
        expect(_card(a, _lowVis).stopTold, 1, reason: 'control: told once');
        await _advance(tester, const Duration(minutes: 10, seconds: 30));
        expect(_fetches, 2, reason: 'control: the failed refresh ran');
        if (band != null) {
          await _chooseBand(tester, band);
          await _advance(tester, const Duration(seconds: 15));
          await _chooseBand(tester, null);
        }
        await _advance(tester, const Duration(minutes: 10));
        expect(_fetches, 3, reason: 'control: the fresh refresh ran');
        expect(
          _card(a, _lowVis).stopTold,
          1,
          reason: 'the same measured whiteout was told again as new',
        );
      });
    }
  });

  group('(c) with no fresh reading, a demo value does not clear her', () {
    for (final (name, vis, fail, wait, reason) in [
      (
        'no visibility reading',
        <int?>[null],
        <bool>[false],
        const Duration(seconds: 1),
        CautionReason.unknownVisibility,
      ),
      (
        'a reading gone stale',
        <int?>[80],
        <bool>[false, true],
        const Duration(minutes: 10, seconds: 30),
        CautionReason.staleVisibility,
      ),
    ]) {
      testWidgets(
        '$name, a positioned share: 1500 m keeps the rung and says the '
        'reading is missing',
        (tester) async {
          final p = _Positioned();
          final a = await _boot(
            tester,
            source: p.source,
            visibilities: vis,
            failing: fail,
          );
          await _tapShare(tester);
          p.fix();
          await _advance(tester, wait, each: p.fix);
          final before = _card(a, reason);
          expect(
            before.rung,
            DriveAction.heightenedCaution,
            reason: 'control: a missing reading holds the middle rung',
          );
          expect(before.cause, isTrue, reason: 'control: $name is stated');
          await _chooseBand(tester, 1500);
          await _advance(tester, const Duration(seconds: 15), each: p.fix);
          _expectNotLower(_card(a, reason), before, '$name, band 1500 m');
        },
      );
    }
  });

  group('(d) a demo value may add caution', () {
    for (final (name, vis) in [
      ('a fresh measured 700 m', <int?>[700]),
      ('no visibility reading', <int?>[null]),
    ]) {
      testWidgets(
        '$name, a positioned share: 80 m raises her to the top rung',
        (tester) async {
          final p = _Positioned();
          final a = await _boot(tester, source: p.source, visibilities: vis);
          await _tapShare(tester);
          p.fix();
          await _advance(tester, const Duration(seconds: 1), each: p.fix);
          expect(
            _card(a, _lowVis).rung,
            DriveAction.heightenedCaution,
            reason: 'control: the middle rung',
          );
          await _chooseBand(tester, 80);
          await _advance(tester, const Duration(seconds: 15), each: p.fix);
          final after = _card(a, _lowVis);
          expect(
            after.rung,
            DriveAction.considerStopping,
            reason: 'a demo value lower than the reading must add caution',
          );
          expect(after.cause, isTrue);
        },
      );
    }
  });

  group('(e) her card says when a test value is what it shows', () {
    testWidgets(
      'a fresh measured 700 m, a positioned share: no line before; with 80 m '
      'chosen, the line',
      (tester) async {
        final p = _Positioned();
        final a = await _boot(
          tester,
          source: p.source,
          visibilities: const [700],
        );
        await _tapShare(tester);
        p.fix();
        await _advance(tester, const Duration(seconds: 1), each: p.fix);
        expect(
          find.byKey(_testValueOnCard),
          findsNothing,
          reason: 'control: nothing but measurements on her card',
        );
        await _chooseBand(tester, 80);
        await _advance(tester, const Duration(seconds: 15), each: p.fix);
        expect(
          _card(a, _lowVis).rung,
          DriveAction.considerStopping,
          reason: 'control: the demo value is what the card shows',
        );
        expect(
          find.byKey(_testValueOnCard),
          findsOneWidget,
          reason: 'a demo visibility is shown as if the station measured it',
        );
        expect(
          _textOf(tester, _testValueOnCard),
          _cardWordsJa,
          reason: 'AQ3: the card line says its rung used a test value',
        );
        expect(
          _toldAsTest(a, _stopLine),
          isTrue,
          reason:
              'AQ4: the top rung a demo 80 m raised was spoken as if measured: '
              '${a.spoken}',
        );
        expect(
          _toldBare(a, _stopLine),
          isFalse,
          reason: 'AQ4: a bare top-rung line from a test value: ${a.spoken}',
        );
      },
    );

    testWidgets(
      'a fresh measured 80 m: a demo 1500 m is not what the card shows, and '
      'no test-value line claims it is',
      (tester) async {
        final p = _Positioned();
        final a = await _boot(tester, source: p.source);
        await _tapShare(tester);
        p.fix();
        await _advance(tester, const Duration(seconds: 1), each: p.fix);
        await _chooseBand(tester, 1500);
        await _advance(tester, const Duration(seconds: 15), each: p.fix);
        final c = _card(a, _lowVis);
        expect(
          c.rung == DriveAction.considerStopping && c.cause,
          isTrue,
          reason: 'the demo band lowered the card: ${c.rung}, cause ${c.cause}',
        );
        expect(
          find.byKey(_testValueOnCard),
          findsNothing,
          reason:
              'the measured reading is shown; a test-value line would '
              'tell her the whiteout is a test',
        );
        expect(
          _toldBare(a, _stopLine),
          isTrue,
          reason: 'control: the measured whiteout is told: ${a.spoken}',
        );
        expect(
          a.spoken.where((l) => l.text == _prefixJa),
          isEmpty,
          reason:
              'AQ4: a measured whiteout told as a test value: ${a.spoken}',
        );
      },
    );

    testWidgets(
      'P2 (AAA R52): no share, a fresh measured 700 m, a demo 80 m: the card '
      'shows no rung, and no line says it shows a test value',
      (tester) async {
        await _boot(tester, visibilities: const [700]);
        await _advance(tester, const Duration(seconds: 1));
        await _chooseBand(tester, 80);
        await _advance(tester, const Duration(seconds: 1));
        expect(rungOnCard(), isNull, reason: 'control: no rung on the card');
        expect(
          find.byKey(_testValueOnCard),
          findsNothing,
          reason:
              'the line says the card shows a test value when nothing on it '
              'came from one',
        );
      },
    );

    // W1 (AAA R58, produced by FSE at R106). The card-wide line said the card
    // shows a test value; under a measured 1500 m the RUNG came from the
    // measurement, so the line was wrong about the rung. AAA narrowed it to the
    // 理由 row carrying positionUncertain, and in the SAME ruling moved the
    // honesty into the position rows themselves, mock only. The two halves are
    // complementary and neither stands alone: measured at R106, a trusted mock
    // can NEVER reach positionUncertain (the mock cancels the position
    // watchdog, so nothing polls the estimate down), so the condition alone
    // does not narrow the mock case — it empties it, leaving her card reading
    // GPS 良好 · 誤差 約 35 m about a position nobody measured. AAA R52 AQ3
    // already ruled the separate モック位置 banner "not enough".
    //
    // These two assertions are NOT of equal strength and the difference is
    // recorded on purpose: the ABSENT one below discriminates (red before W1,
    // green after); the PRESENT one cannot tell the two trees apart and is a
    // regression guard only. Its failability is proven by mutation, never
    // assumed.

    testWidgets(
      'W1: the Akita mock position under a measured 1500 m, nothing uncertain: '
      'no card-wide test-value line, and the position rows say it is a test',
      (tester) async {
        await _boot(tester, visibilities: const [1500]);
        await _advance(tester, const Duration(seconds: 1));
        expect(
          await _tapMockIfOffered(tester),
          isTrue,
          reason: 'control: the mock is offered with no share running',
        );
        await _advance(tester, const Duration(seconds: 1));
        expect(
          _shown(_reason(CautionReason.positionUncertain)),
          isFalse,
          reason: 'control: a trusted mock puts no positionUncertain on the card',
        );
        expect(
          find.byKey(_testValueOnCard),
          findsNothing,
          reason:
              'the card-wide line says the card shows a test value while its '
              'rung came from the measured 1500 m',
        );
        // The other half of AAA R58, without which the narrowing above just
        // removes what she was told: the card's own trust row must not dress a
        // fabricated fix in the words of a measured one.
        expect(
          find.textContaining('GPS 良好'),
          findsNothing,
          reason: 'a position nobody measured is on her card as a good GPS fix',
        );
        expect(
          _shown(_mockTrustWordsJa),
          isTrue,
          reason: 'the trust row does not say the position is a test',
        );
        expect(
          _shown(_mockRadiusWordsJa),
          isTrue,
          reason: 'the uncertainty row does not say the radius is a test value',
        );
      },
    );

    testWidgets(
      'W1: ten minutes with the mock in force reaches no positionUncertain of '
      'its own, so the position rows are the only thing telling her',
      (tester) async {
        await _boot(tester, visibilities: const [1500]);
        await _advance(tester, const Duration(seconds: 1));
        expect(await _tapMockIfOffered(tester), isTrue, reason: 'control');
        await _advance(tester, const Duration(minutes: 10));
        // The measurement the W1 ruling rests on, kept as an assertion so it
        // cannot quietly stop being true: taking the mock cancels the position
        // watchdog (`main.dart`, N8 — "the mock dot is a static dev tool"), so
        // no clock degrades the estimate and positionUncertain never arrives.
        // The card-wide line is therefore NEVER drawn for a trusted mock, and
        // the rows below are the whole of what she is told.
        expect(
          _shown(_reason(CautionReason.positionUncertain)),
          isFalse,
          reason: 'control: ten minutes did not make the mock uncertain',
        );
        expect(find.byKey(_testValueOnCard), findsNothing);
        expect(
          find.textContaining('GPS 良好'),
          findsNothing,
          reason: 'ten minutes on, a fabricated fix still reads as good GPS',
        );
        expect(
          _shown(_mockTrustWordsJa),
          isTrue,
          reason: 'the only line telling her this is a test has gone quiet',
        );
      },
    );

    testWidgets(
      'W1: the Akita mock position with an uncertain position on the card: the '
      'card-wide line (regression guard; does not discriminate W1)',
      (tester) async {
        await _boot(tester, visibilities: const [1500]);
        await _advance(tester, const Duration(seconds: 1));
        expect(await _tapMockIfOffered(tester), isTrue, reason: 'control');
        await _advance(tester, const Duration(seconds: 1));
        // The ONLY reach to positionUncertain while a mock is in force,
        // measured at R106: the simulated blackout polls the estimate down.
        // The card has no blackout check of its own (AAA R55 5(a)), so the
        // line below is drawn by the mock branch and by nothing else.
        for (var i = 0; i < 3; i++) {
          await _pressBlackout(tester);
          await _advance(tester, const Duration(seconds: 1));
        }
        expect(
          _shown(_reason(CautionReason.positionUncertain)),
          isTrue,
          reason: 'control: the card carries positionUncertain',
        );
        expect(
          find.byKey(_testValueOnCard),
          findsOneWidget,
          reason: 'a rung a position nobody measured raised, with no line',
        );
        expect(_textOf(tester, _testValueOnCard), _cardWordsJa, reason: 'AQ3');
      },
    );

    testWidgets(
      'AQ4: the Akita mock position under measured 700 m: the caution it '
      'raises is spoken as a test value',
      (tester) async {
        final a = await _boot(tester, visibilities: const [700]);
        await _advance(tester, const Duration(seconds: 1));
        final cautionLine = _hud.spokenGuidance(
          DriveAction.heightenedCaution,
          'ja',
        );
        expect(
          a.spoken.where((l) => l.text == cautionLine),
          isEmpty,
          reason: 'control: nothing told before the mock',
        );
        expect(await _tapMockIfOffered(tester), isTrue, reason: 'control');
        await _advance(tester, const Duration(seconds: 1));
        expect(
          _toldAsTest(a, cautionLine),
          isTrue,
          reason: 'a caution from a position nobody measured: ${a.spoken}',
        );
        expect(_toldBare(a, cautionLine), isFalse, reason: '${a.spoken}');
      },
    );
  });

  // ==================================================== (O2) the mock ====

  group('(Q2) the Akita mock position under a measured condition', () {
    for (final vis in const [80, 300]) {
      testWidgets(
        'no share, measured $vis m: the mock never lowers the rung or takes '
        'the cause off her card',
        (tester) async {
          final a = await _boot(tester, visibilities: [vis]);
          await _advance(tester, const Duration(seconds: 1));
          final before = _card(a, _lowVis);
          expect(
            await _tapMockIfOffered(tester),
            isTrue,
            reason: 'control: the mock is offered with no share running',
          );
          await _advance(tester, const Duration(seconds: 1));
          _expectNotLower(_card(a, _lowVis), before, 'mock under $vis m');
        },
      );

      testWidgets(
        'a failed start under measured $vis m: nothing replaces her failed '
        'share with a trusted mock fix',
        (tester) async {
          final a = await _boot(
            tester,
            source: _failedStart,
            visibilities: [vis],
          );
          await _tapShare(tester);
          await _advance(tester, const Duration(seconds: 16));
          final before = _card(a, _lowVis);
          expect(
            before.rung,
            DriveAction.considerStopping,
            reason:
                'control: a failed start in a measured $vis m is the top rung',
          );
          await _tapMockIfOffered(tester);
          await _advance(tester, const Duration(seconds: 16));
          _expectNotLower(
            _card(a, _lowVis),
            before,
            'mock during a failed share, $vis m',
          );
        },
      );
    }
  });

  // ================================================ (O3) the demo clock ====

  group('(O3) the simulated GPS blackout only ever raises', () {
    for (final (vis, floor) in const [
      (80, DriveAction.considerStopping),
      (700, DriveAction.heightenedCaution),
    ]) {
      testWidgets('a positioned share under measured $vis m: three presses', (
        tester,
      ) async {
        final p = _Positioned();
        final a = await _boot(tester, source: p.source, visibilities: [vis]);
        await _tapShare(tester);
        p.fix();
        await _advance(tester, const Duration(seconds: 1), each: p.fix);
        var before = _card(a, _lowVis);
        expect(before.rung, floor, reason: 'control');
        for (var i = 1; i <= 3; i++) {
          await _pressBlackout(tester);
          await _advance(tester, const Duration(seconds: 1));
          final after = _card(a, _lowVis);
          _expectNotLower(after, before, 'blackout press $i');
          before = after;
        }
      });
    }

    // AAA R52 P1. Every press above follows a fresh fix, where the simulated
    // clock is ahead of the real one. Here her real drought is already 68 s:
    // a press polled at fix + 60 s moved the clock back, and a degraded dot
    // dropped from the top rung to the middle one.
    testWidgets(
      'P1 (AAA R52): a positioned share under measured 700 m, 68 s without a '
      'fix: one press does not lower the top rung',
      (tester) async {
        final p = _Positioned();
        await _boot(tester, source: p.source, visibilities: const [700]);
        await _tapShare(tester);
        await _advance(tester, const Duration(seconds: 7));
        p.fix();
        await tester.pump();
        await tester.pump();
        await _advance(tester, const Duration(seconds: 68));
        final before = rungOnCard();
        expect(
          before,
          DriveAction.considerStopping,
          reason: 'control: a 68 s drought under 700 m reads the top rung',
        );
        await _pressBlackout(tester);
        for (var i = 0; i < 3; i++) {
          await tester.pump();
        }
        final after = rungOnCard();
        expect(
          after,
          isNot(DriveAction.heightenedCaution),
          reason: 'P1: the press lowered the top rung to the middle one',
        );
        expect(
          _rank(after),
          greaterThanOrEqualTo(_rank(before)),
          reason: 'P1: the rung fell from $before to $after',
        );
      },
    );

    // AQ4, the simulated drought (FSE extension beyond AAA's text, for AAA to
    // rule): a top rung only the simulated clock raised is a test value too.
    testWidgets(
      'AQ4: a positioned share under measured 1500 m: the top rung the '
      'simulated blackout raises is spoken as a test value',
      (tester) async {
        final p = _Positioned();
        final a = await _boot(
          tester,
          source: p.source,
          visibilities: const [1500],
        );
        await _tapShare(tester);
        p.fix();
        await _advance(tester, const Duration(seconds: 1), each: p.fix);
        expect(
          a.spoken.where((l) => l.text == _stopLine),
          isEmpty,
          reason: 'control: nothing told under a clear measurement',
        );
        for (var i = 0; i < 3; i++) {
          await _pressBlackout(tester);
          await tester.pump();
          await tester.pump();
        }
        expect(
          rungOnCard(),
          DriveAction.considerStopping,
          reason: 'control: three simulated minutes reach the top rung',
        );
        expect(
          _toldAsTest(a, _stopLine),
          isTrue,
          reason: 'a drought nobody measured, told as measured: ${a.spoken}',
        );
        expect(_toldBare(a, _stopLine), isFalse, reason: '${a.spoken}');
      },
    );
  });

  // ========================================== (O5) settings: driver type ====

  testWidgets(
    '(O5) a positioned share under measured 80 m: every driver type leaves '
    'the rung and the cause',
    (tester) async {
      final p = _Positioned();
      final a = await _boot(tester, source: p.source);
      await _tapShare(tester);
      p.fix();
      await _advance(tester, const Duration(seconds: 1), each: p.fix);
      final before = _card(a, _lowVis);
      expect(before.rung, DriveAction.considerStopping, reason: 'control');
      var chosen = 0;
      for (final profile in const ['noviceUrban', 'ageingRural']) {
        await _chooseEnum(tester, 'DriverProfile', profile);
        chosen++;
        await _advance(tester, const Duration(seconds: 15), each: p.fix);
        _expectNotLower(_card(a, _lowVis), before, 'driver type $profile');
      }
      expect(chosen, 2, reason: 'control: both driver types were chosen');
    },
  );

  // ============================================ (O4) the road condition ====

  group('(Q3) a simulated road condition on her next-turn card', () {
    // Hoisted to _routeWithOneTurn/_turnCard (FSE R114) so the (Q5) group runs
    // the SAME route recipe this group runs; these keep the local names.
    Future<void> routeWithOneTurn(WidgetTester t) => _routeWithOneTurn(t);
    Finder turnCard() => _turnCard();

    for (final (condition, marked) in const [
      ('unknown', false),
      ('ice', true),
    ]) {
      testWidgets(
        'a positioned share, simulated $condition: '
        '${marked ? 'the icy mark, and the card says it is a test value' : 'no mark and no test-value line'}',
        (tester) async {
          final p = _Positioned();
          final a = await _boot(
            tester,
            source: p.source,
            visibilities: const [1500],
            route: true,
          );
          await routeWithOneTurn(tester);
          await _tapShare(tester);
          p.fix();
          await _advance(tester, const Duration(seconds: 1), each: p.fix);
          if (condition != 'unknown') {
            await _chooseEnum(tester, 'RoadSurfaceCondition', condition);
            await _advance(tester, const Duration(seconds: 1), each: p.fix);
          }
          final icy = find.descendant(
            of: turnCard(),
            matching: find.textContaining('凍結のおそれ'),
          );
          expect(
            _drawn(icy),
            marked,
            reason: 'control: the icy mark follows the simulated condition',
          );
          expect(
            _drawn(
              find.descendant(
                of: turnCard(),
                matching: find.byKey(_testRoadOnTurnCard),
              ),
            ),
            marked,
            reason: marked
                ? 'her turn is marked icy with nothing measured, and the card '
                      'does not say it is a test value'
                : 'a test-value line with no test value in force',
          );
          if (marked) {
            expect(_textOf(tester, _testRoadOnTurnCard), _iceWordsJa,
                reason: 'AQ3');
          }
          // AQ4: the icy line is spoken with the prefix before it.
          final narrate = find.byKey(const Key('maneuver-narrate-button'));
          await tester.ensureVisible(narrate);
          await tester.pump();
          final spokenBefore = a.spoken.length;
          await tester.tap(narrate);
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
          final told = a.spoken.sublist(spokenBefore);
          expect(
            told.where((l) => l.text != _prefixJa),
            isNotEmpty,
            reason: 'control: the next turn was narrated',
          );
          expect(
            told.isNotEmpty && told.first.text == _prefixJa,
            marked,
            reason: marked
                ? 'AQ4: an icy turn nobody measured, spoken as measured: $told'
                : 'AQ4: a test-value prefix with no test value: $told',
          );
        },
      );
    }
  });

  // ================= (Q5) AAA R58 W1 re-audit: the THIRD modeLabel site ====
  //
  // WHY, written before the act. FSE R106 measured `GPS 良好` exactly once
  // under a trusted mock and read that as no reachable defect left open. AAA
  // refuted the measurement at the genba: it is true only of a session with NO
  // ROUTE SET. With a route set, the turn-preview panel draws its own
  // 現在地の信頼度 row — the SAME label as the drive card's trust row — from a
  // third modeLabel call that never received isMock. The card then said the
  // position was a test while the turn panel called it GPS 良好: two honesty
  // labels for one fabricated fix, disagreeing, on one screen.
  //
  // _fetchRoute is gated on tapped origin and destination only. Nothing about
  // a route depends on the position being real, so this is reachable whenever
  // she sets a route with the mock in force.
  group('(Q5) the turn-preview panel under the Akita mock position', () {
    testWidgets(
      'a route set and the mock taken, ten minutes on: the turn panel says the '
      'position is a test, and GPS 良好 is nowhere on her screen',
      (tester) async {
        await _boot(tester, route: true);
        await _routeWithOneTurn(tester);
        expect(
          await _tapMockIfOffered(tester),
          isTrue,
          reason: 'control: the mock position was taken',
        );
        await _advance(tester, const Duration(minutes: 10));

        final card = _turnCard();
        expect(
          _drawn(find.descendant(
            of: card,
            matching: find.textContaining('現在地の信頼度'),
          )),
          isTrue,
          reason: 'control: the turn panel draws a position-trust row at all',
        );
        // Scoped first, so a failure names WHICH surface lied.
        expect(
          _drawn(find.descendant(
            of: card,
            matching: find.textContaining('GPS 良好'),
          )),
          isFalse,
          reason: 'the turn panel calls a fabricated fix a good GPS fix',
        );
        expect(
          _drawn(find.descendant(
            of: card,
            matching: find.textContaining(_mockTrustWordsJa),
          )),
          isTrue,
          reason: 'the turn panel trust row does not say the position is a test',
        );
        // And the whole screen, which is what she actually looks at: the R106
        // assertion that held only because no route was set.
        expect(
          find.textContaining('GPS 良好'),
          findsNothing,
          reason: 'a position nobody measured is somewhere on her screen as a '
              'good GPS fix',
        );
      },
    );

    // The OTHER direction, on AAA's published re-audit bar. Without this, the
    // test above is satisfied by a panel that calls EVERY fix a test position
    // — honest about the mock by being dishonest about hers. Proven failable
    // by mutation M2 (isMock: true at the site): this test goes red, the one
    // above stays green.
    testWidgets(
      'a route set and a REAL share: the turn panel still reads GPS 良好 — the '
      'marker is for a fabricated fix, never for the position she is driving on',
      (tester) async {
        final p = _Positioned();
        await _boot(
          tester,
          source: p.source,
          visibilities: const [1500],
          route: true,
        );
        await _routeWithOneTurn(tester);
        await _tapShare(tester);
        p.fix();
        await _advance(tester, const Duration(seconds: 1), each: p.fix);

        final card = _turnCard();
        expect(
          _drawn(find.descendant(
            of: card,
            matching: find.textContaining('現在地の信頼度'),
          )),
          isTrue,
          reason: 'control: the turn panel draws a position-trust row at all',
        );
        expect(
          _drawn(find.descendant(
            of: card,
            matching: find.textContaining('GPS 良好'),
          )),
          isTrue,
          reason: 'her measured fix lost its honest label to the mock marker',
        );
        expect(
          _drawn(find.descendant(
            of: card,
            matching: find.textContaining(_mockTrustWordsJa),
          )),
          isFalse,
          reason: 'the position she is actually driving on is labelled a test',
        );
      },
    );
  });

  // ======================= (Q6) the same two rows on an English device ====
  //
  // WHY, written before the act. The ja harness above is this FILE's default,
  // never the app's: AppL10n.supportedLocales is [ja, en] and the app follows
  // the device. The mock position rows were asserted in ja only, so the
  // English words they ship to an English-locale driver were unasserted. This
  // is the parity assertion, and it fails on a tree without the W1 pair.
  group('(Q6) the Akita mock position rows on an English device', () {
    testWidgets(
      'en: the position rows say the position is a test and the radius is a '
      'test value, and never GPS good',
      (tester) async {
        await _boot(
          tester,
          visibilities: const [1500],
          locale: const Locale('en'),
        );
        await _advance(tester, const Duration(seconds: 1));
        expect(
          await _tapMockIfOffered(tester),
          isTrue,
          reason: 'control: the mock is offered with no share running',
        );
        await _advance(tester, const Duration(seconds: 1));
        expect(
          _shown('Position trust'),
          isTrue,
          reason: 'control: the drive card is in English and draws the row',
        );
        expect(
          find.textContaining('GPS good'),
          findsNothing,
          reason: 'an English driver is shown a fabricated fix as a good GPS fix',
        );
        expect(
          _shown(_mockTrustWordsEn),
          isTrue,
          reason: 'the English trust row does not say the position is a test',
        );
        expect(
          _shown(_mockRadiusWordsEn),
          isTrue,
          reason: 'the English uncertainty row does not say the radius is a '
              'test value',
        );

        // AAA R114 bar: her_position_locale_test.dart:138 sweeps the English
        // drive panel for CJK, but never in the mock state. Same range, now
        // reaching it — an English driver must not meet Japanese here just
        // because the position is a test one.
        final cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff]');
        for (final label in const ['Position trust:', 'Uncertainty:']) {
          final l = find.text(label);
          expect(l, findsOneWidget, reason: 'control: $label row is drawn');
          final row = find.ancestor(of: l, matching: find.byType(Row)).first;
          final texts = [
            for (final e in find
                .descendant(of: row, matching: find.byType(Text))
                .evaluate())
              (e.widget as Text).data ?? '',
          ];
          expect(texts.where((t) => t.isNotEmpty), isNotEmpty,
              reason: 'control: $label row has text');
          expect(texts.where(cjk.hasMatch), isEmpty,
              reason: 'Japanese reached an English driver in $label: $texts');
        }
      },
    );
  });
}

// ------------------------------------------------- the route recipe, hoisted ----
// One recipe, used by (Q3) and (Q5). Moved out of the (Q3) group unchanged
// (FSE R114) so the turn-panel assertions run exactly the route this file
// already proved sets a next maneuver.
Future<void> _routeWithOneTurn(WidgetTester tester) async {
  final open = find.byKey(const Key('route-act-open'));
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final actMap = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(AkitaMap),
  );
  final r = tester.getRect(actMap);
  await tester.tapAt(r.center + const Offset(-80, -30));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tapAt(r.center + const Offset(80, 30));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.byKey(const Key('route-act-get-route')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('route-consent-accept')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 3));
  expect(
    find.byKey(const Key('maneuver-narration-banner')),
    findsOneWidget,
    reason: 'control: the route has a next maneuver',
  );
}

Finder _turnCard() => find
    .ancestor(
      of: find.byKey(const Key('maneuver-narration-banner')),
      matching: find.byType(Card),
    )
    .first;
