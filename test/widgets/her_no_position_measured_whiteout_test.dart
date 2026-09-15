/// What a driver with no position is given while a measured whiteout stands
/// on the road, in four cases (ruled 2026-09-15).
///
/// Why, written before the act. Under a fresh measured visibility below 200 m
/// the app's own advisor puts the road at its top rung whatever is known of
/// her position: a driver with a trusted position there is shown the top rung,
/// given the line inviting a safe stop, and the critical haptic. Measured on
/// this app before the ruling, with the same weather for every driver:
/// * a later share in the same whiteout showed the top rung and said and
///   buzzed nothing, positioned or not: what an earlier share told was carried
///   into it;
/// * a share whose first position never arrived was given nothing, to 11 min;
/// * a driver who never shared, or who said no to location, was given nothing
///   of the whiteout at all;
/// * after 停止, the ended share's old position went on deciding what she was
///   told at each weather refresh: slow down and a warning haptic when 700 m
///   came, for a share ended under a clear 1,500 m.
///
/// Ruled. The whiteout is the road's, so it reaches her whatever her position:
/// * A first share whose position failed: the top rung, the stop line once,
///   the critical haptic once. Unchanged.
/// * Any later share, positioned or not: the same as a first share. A share she
///   starts herself begins with nothing told, and nothing else resets it.
/// * The first fix never arrives: once the position stream is subscribed, and
///   by the first check after it (15 s at most), what a driver with a trusted
///   position under the same reading is given; from 60 s, what a failed start
///   is given. Nothing while the permission dialog is up.
/// * No share running, whether she never shared, said no, or pressed 停止: the
///   whiteout is told once when it opens, spoken and felt, at the top rung,
///   with its cause on screen. Nothing comes from an ended share's position,
///   and nothing answers her no.
/// It must not be told again when only the reading's age flickers, and a
/// position failure must not alarm where nothing measured raises caution.
///
/// Read without the card's words or colours: the rung from the caution
/// banner's own headline, mapped back through the app's own localizer; the
/// lines through the same localizer; the cause as the localizer's words for a
/// low visibility; 停止 through the app's own words. Every reading is station
/// 32402's, stamped when the app fetches it, so it is fresh for 300 s after
/// each 10-minute refresh.
library;

import 'dart:async';

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show CautionReason, DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/fake_alert_actuators.dart';

const _hud = DriveHudLocalizer();
const _words = AppL10n(Locale('ja'));
final _stopLine = _hud.spokenGuidance(DriveAction.considerStopping, 'ja');
final _slowLine = _hud.spokenGuidance(DriveAction.heightenedCaution, 'ja');
final _lowVisibility = _hud.reasonLabel(CautionReason.lowVisibility, 'ja');

const _top = 'considerStopping';
const _heightened = 'heightenedCaution';
const _none = 'none';

final _start = DateTime.utc(2026, 1, 14, 21);
var _now = _start;

// ------------------------------------------------------------- the weather ----

/// Visibility per fetch, in order; the last one repeats. A fetch whose index
/// is `true` in [_failing] fails.
var _visibilities = <int?>[80];
var _failing = <bool>[false];
var _fetches = 0;

/// Wind in m/s for every fetch. 2 m/s fires no watch; 12 m/s fires the app's
/// measured wind watch.
var _wind = 2.0;

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _jma() async {
  final i = _fetches;
  _fetches++;
  if (i < _failing.length && _failing[i]) {
    return const JmaFailure('test: this refresh failed');
  }
  return JmaSuccess(JmaObservation(
    stationId: '32402',
    stationName: '秋田',
    temperatureCelsius: 5,
    humidityPercent: 50,
    windMetersPerSecond: _wind,
    snowDepthCm: null,
    precipitation10mMm: 0,
    visibilityMeters: _visibilities[i < _visibilities.length
        ? i
        : _visibilities.length - 1],
    observedAtJstKey: _jstKey(_now),
    fetchedAt: _now,
  ));
}

// ----------------------------------------------------------- what she has ----

typedef _Given = ({
  String rung,
  List<String> spoken,
  List<String> felt,
  bool cause,
});

typedef _Mark = ({int spoken, int felt});

/// The caution banner's rung, from its own headline mapped back through the
/// app's localizer. [_none] when no banner is built; a headline no rung
/// produces fails loudly.
String _rung(WidgetTester tester) {
  final banner = find.byKey(const Key('drive-hud-caution-banner'));
  if (banner.evaluate().isEmpty) return _none;
  final texts = [
    for (final e in find
        .descendant(of: banner, matching: find.byType(Text))
        .evaluate())
      (e.widget as Text).data ?? '',
  ];
  final rungs = <String>{
    for (final s in texts)
      for (final r in DriveAction.values)
        for (final advisory in const [false, true])
          for (final measured in const [false, true])
            for (final calm in const [false, true])
              if (s ==
                  _hud.actionHeadline(r, 'ja',
                      advisoryUnconfirmed: advisory,
                      measuredUnconfirmed: measured,
                      calmNoteInForce: calm))
                r.name,
  };
  return rungs.length == 1 ? rungs.single : 'UNREADABLE $texts';
}

String _name(String line) => line == _stopLine
    ? 'stop'
    : line == _slowLine
        ? 'slow'
        : line;

_Mark _mark(FakeAlertActuators a) =>
    (spoken: a.spoken.length, felt: a.haptics.length);

_Given _given(WidgetTester tester, FakeAlertActuators a, [_Mark? from]) => (
      rung: _rung(tester),
      spoken: [
        for (final s in a.spoken.skip(from?.spoken ?? 0)) _name(s.text),
      ],
      felt: [
        for (final h in a.haptics.skip(from?.felt ?? 0)) '$h'.split('.').last,
      ],
      cause: find.textContaining(_lowVisibility).evaluate().isNotEmpty,
    );

void _expectGiven(
  _Given g, {
  required String rung,
  required List<String> spoken,
  required List<String> felt,
  bool? cause,
  required String when,
}) {
  expect(g.rung, rung, reason: '$when: the rung');
  expect(g.spoken, spoken, reason: '$when: spoken');
  expect(g.felt, felt, reason: '$when: felt');
  if (cause != null) {
    expect(g.cause, cause, reason: '$when: the cause on screen');
  }
}

void _expectSame(_Given g, _Given other, String when) {
  expect(g.rung, other.rung, reason: '$when: the rung');
  expect(g.spoken, other.spoken, reason: '$when: spoken');
  expect(g.felt, other.felt, reason: '$when: felt');
  expect(g.cause, other.cause, reason: '$when: the cause on screen');
}

// --------------------------------------------------------------- the app ----

Future<FakeAlertActuators> _boot(
  WidgetTester tester, {
  Stream<PositionFix> Function()? source,
  List<int?> visibilities = const [80],
  List<bool> failing = const [false],
  double wind = 2,
}) async {
  final a = FakeAlertActuators();
  _now = _start;
  _visibilities = [...visibilities];
  _failing = [...failing];
  _fetches = 0;
  _wind = wind;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    actuators: a,
    locale: const Locale('ja'),
    clock: () => _now,
    jmaFetch: _jma,
    positionSource: source,
  ));
  await tester.pump();
  await tester.pump();
  return a;
}

Future<void> _advance(WidgetTester tester, Duration d,
    {void Function()? each}) async {
  var left = d;
  while (left > Duration.zero) {
    final step =
        left > const Duration(seconds: 15) ? const Duration(seconds: 15) : left;
    _now = _now.add(step);
    each?.call();
    await tester.pump(step);
    left -= step;
  }
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// Starts a share and returns what had been told before her tap.
Future<_Mark> _tapShare(WidgetTester tester, FakeAlertActuators a) async {
  final mark = _mark(a);
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  expect(find.byKey(const Key('share-location-button')), findsNothing,
      reason: 'control: sharing started');
  return mark;
}

/// 停止, found through the app's own words, never a literal.
Future<void> _tapStop(WidgetTester tester) async {
  final s = find.widgetWithText(TextButton, _words.stop);
  expect(s, findsOneWidget, reason: 'control: the row offers 停止');
  await tester.ensureVisible(s);
  await tester.pump();
  await tester.tap(s);
  await tester.pump();
  await tester.pump();
}

Position _position(DateTime at, {bool hasAccuracy = true}) => Position(
      latitude: 39.7186,
      longitude: 140.1024,
      timestamp: at,
      accuracy: hasAccuracy ? 10 : 0,
      hasAccuracy: hasAccuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Stream<PositionFix> _granted(StreamController<Position> platform) =>
    herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      positionStream: () => platform.stream,
    );

/// The platform start throws: the stream's "GPS init error".
Stream<PositionFix> _failedStart() => herPositionStream(
    isServiceEnabled: () async => throw StateError('no location provider'));

Stream<PositionFix> _servicesOff() =>
    herPositionStream(isServiceEnabled: () async => false);

/// Her "no" on the permission dialog.
Stream<PositionFix> _refused() => herPositionStream(
      isServiceEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async => LocationPermission.denied,
    );

/// A driver with a trusted position: a fresh fix now and at every step.
class _Positioned {
  final platform = StreamController<Position>();
  Stream<PositionFix> source() => _granted(platform);
  void fix() => platform.add(_position(_now));
}

void main() {
  // ------------------------------------------------- a first share, failed ----

  group('a first share whose position failed, under a measured 80 m', () {
    for (final (name, source, sample) in <(
      String,
      Stream<PositionFix> Function()?,
      bool
    )>[
      ('a failed start', _failedStart, false),
      ('location services off', _servicesOff, false),
      ('a first sample with no measured accuracy', null, true),
    ]) {
      testWidgets(
          '$name: the top rung, the stop line once and the critical haptic '
          'once, through the refreshes at 10 and 20 min', (tester) async {
        final platform = StreamController<Position>();
        final a = await _boot(tester,
            source: source ?? () => _granted(platform));
        final share = await _tapShare(tester, a);
        if (sample) platform.add(_position(_now, hasAccuracy: false));
        for (final (at, step) in [
          ('at 1 s', const Duration(seconds: 1)),
          ('at 21 min', const Duration(minutes: 21)),
        ]) {
          await _advance(tester, step);
          _expectGiven(_given(tester, a, share),
              rung: _top,
              spoken: ['stop'],
              felt: ['critical'],
              cause: true,
              when: at);
        }
      });
    }
  });

  // --------------------------------------------------------- a later share ----

  group('a later share in the same measured 80 m is told as a first share is',
      () {
    for (final first in ['positioned', 'a failed start']) {
      for (final second in ['positioned', 'a failed start']) {
        testWidgets(
            '$first, 停止, and 20 min later $second: the top rung, the stop '
            'line once and the critical haptic once in that share',
            (tester) async {
          final p1 = _Positioned(), p2 = _Positioned();
          var shares = 0;
          Stream<PositionFix> source() {
            final kind = ++shares == 1 ? first : second;
            final p = shares == 1 ? p1 : p2;
            return kind == 'positioned' ? p.source() : _failedStart();
          }

          final a = await _boot(tester, source: source);
          final share1 = await _tapShare(tester, a);
          if (first == 'positioned') p1.fix();
          await _advance(tester, const Duration(seconds: 1),
              each: first == 'positioned' ? p1.fix : null);
          _expectGiven(_given(tester, a, share1),
              rung: _top,
              spoken: ['stop'],
              felt: ['critical'],
              when: 'control: the first share was told');
          await _tapStop(tester);
          await _advance(tester, const Duration(minutes: 20));

          final share2 = await _tapShare(tester, a);
          expect(shares, 2, reason: 'control: a second share started');
          if (second == 'positioned') p2.fix();
          await _advance(tester, const Duration(seconds: 1),
              each: second == 'positioned' ? p2.fix : null);
          _expectGiven(_given(tester, a, share2),
              rung: _top,
              spoken: ['stop'],
              felt: ['critical'],
              cause: true,
              when: 'the second share at 1 s');
          if (second == 'a failed start') {
            await _advance(tester, const Duration(minutes: 11));
            _expectGiven(_given(tester, a, share2),
                rung: _top,
                spoken: ['stop'],
                felt: ['critical'],
                when: 'the second share at 11 min, after a refresh at the '
                    'same 80 m: not told again');
          }
        });
      }
    }

    testWidgets(
        '停止 resets nothing: a whiteout that opens during a positioned share is '
        'told in it; after 停止 the next refresh at the same 80 m tells '
        'nothing more', (tester) async {
      final p = _Positioned();
      final a = await _boot(tester,
          source: p.source, visibilities: const [700, 80]);
      final share = await _tapShare(tester, a);
      p.fix();
      await _advance(tester, const Duration(minutes: 10, seconds: 15),
          each: p.fix);
      _expectGiven(_given(tester, a, share),
          rung: _top,
          spoken: ['slow', 'stop'],
          felt: ['warning', 'critical'],
          when: 'control: 700 m at the start, and the whiteout that opened at '
              'the 10-minute refresh, told in the share');
      await _tapStop(tester);
      final stopped = _mark(a);
      await _advance(tester, const Duration(minutes: 10));
      expect(_fetches, greaterThanOrEqualTo(3),
          reason: 'control: the 20-minute refresh ran');
      final g = _given(tester, a, stopped);
      expect(g.spoken, isEmpty, reason: 'after 停止, at 20 min 15 s');
      expect(g.felt, isEmpty, reason: 'after 停止, at 20 min 15 s');
    });

    testWidgets(
        '停止 resets nothing, between refreshes: a share started just before '
        'the whiteout opens is told it at its first check; after 停止 the next '
        'refresh at the same 80 m tells nothing more', (tester) async {
      final p = _Positioned(); // subscribed, and no fix ever comes
      final a = await _boot(tester,
          source: p.source, visibilities: const [700, 80]);
      await _advance(tester, const Duration(minutes: 9, seconds: 55));
      expect(_given(tester, a).spoken, isEmpty,
          reason: 'control: nothing told under 700 m before she shares');
      final share = await _tapShare(tester, a);
      await _advance(tester, const Duration(seconds: 25));
      expect(_fetches, greaterThanOrEqualTo(2),
          reason: 'control: the 10-minute refresh brought 80 m');
      _expectGiven(_given(tester, a, share),
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          when: 'at 10 min 20 s: the whiteout that opened at 10 min, told in '
              'the share at its first check');
      await _tapStop(tester);
      final stopped = _mark(a);
      await _advance(tester, const Duration(minutes: 10));
      expect(_fetches, greaterThanOrEqualTo(3),
          reason: 'control: the 20-minute refresh ran');
      final g = _given(tester, a, stopped);
      expect(g.spoken, isEmpty, reason: 'after 停止, at 20 min 20 s');
      expect(g.felt, isEmpty, reason: 'after 停止, at 20 min 20 s');
    });
  });

  // ---------------------------------------------- the first fix never comes ----

  group('the first fix never arrives', () {
    testWidgets(
        'under a measured 80 m: the top rung, the stop line once and the '
        'critical haptic once by 16 s, and nothing more at 61 s or 11 min',
        (tester) async {
      final p = _Positioned();
      final a = await _boot(tester, source: p.source);
      final share = await _tapShare(tester, a);
      for (final (at, step) in [
        ('at 16 s', const Duration(seconds: 16)),
        ('at 61 s', const Duration(seconds: 45)),
        ('at 11 min', const Duration(seconds: 599)),
      ]) {
        await _advance(tester, step);
        _expectGiven(_given(tester, a, share),
            rung: _top,
            spoken: ['stop'],
            felt: ['critical'],
            cause: true,
            when: at);
      }
    });

    testWidgets(
        'under a measured 300 m: what a positioned driver there is given until '
        '60 s, then the top rung at 61 s, told once', (tester) async {
      final control = _Positioned();
      var a = await _boot(tester,
          source: control.source, visibilities: const [300]);
      var share = await _tapShare(tester, a);
      control.fix();
      await _advance(tester, const Duration(seconds: 1), each: control.fix);
      final positioned = _given(tester, a, share);
      _expectGiven(positioned,
          rung: _heightened,
          spoken: ['slow'],
          felt: ['warning'],
          when: 'control: a positioned driver under 300 m');

      final p = _Positioned();
      a = await _boot(tester, source: p.source, visibilities: const [300]);
      share = await _tapShare(tester, a);
      for (final (at, step) in [
        ('at 16 s', const Duration(seconds: 16)),
        ('at 46 s, before 60 s', const Duration(seconds: 30)),
      ]) {
        await _advance(tester, step);
        _expectSame(_given(tester, a, share), positioned,
            '$at: given what a positioned driver under 300 m is');
      }
      for (final (at, step) in [
        ('at 61 s', const Duration(seconds: 15)),
        ('at 11 min', const Duration(seconds: 599)),
      ]) {
        await _advance(tester, step);
        _expectGiven(_given(tester, a, share),
            rung: _top,
            spoken: ['slow', 'stop'],
            felt: ['warning', 'critical'],
            when: '$at: what a failed start under 300 m is given, the rise '
                'told once');
      }
    });

    testWidgets(
        'under a measured 700 m: heightened caution, the slow line once and a '
        'warning haptic once, at 16 s, 61 s and 11 min', (tester) async {
      final p = _Positioned();
      final a = await _boot(tester, source: p.source, visibilities: const [700]);
      final share = await _tapShare(tester, a);
      for (final (at, step) in [
        ('at 16 s', const Duration(seconds: 16)),
        ('at 61 s', const Duration(seconds: 45)),
        ('at 11 min', const Duration(seconds: 599)),
      ]) {
        await _advance(tester, step);
        _expectGiven(_given(tester, a, share),
            rung: _heightened, spoken: ['slow'], felt: ['warning'], when: at);
      }
    });

    testWidgets(
        'under a firing wind watch with no visibility reading: what a '
        'positioned driver is given until 60 s, the watch felt and heightened '
        'caution shown with no line of its own; then the top rung at 61 s',
        (tester) async {
      final control = _Positioned();
      var a = await _boot(tester,
          source: control.source, visibilities: const [null], wind: 12);
      var share = await _tapShare(tester, a);
      control.fix();
      await _advance(tester, const Duration(seconds: 1), each: control.fix);
      final positioned = _given(tester, a, share);
      _expectGiven(positioned,
          rung: _heightened,
          spoken: [],
          felt: [],
          when: 'control: a positioned driver under the wind watch, after '
              'her tap');

      final p = _Positioned();
      a = await _boot(tester,
          source: p.source, visibilities: const [null], wind: 12);
      share = await _tapShare(tester, a);
      for (final (at, step) in [
        ('at 16 s', const Duration(seconds: 16)),
        ('at 46 s, before 60 s', const Duration(seconds: 30)),
      ]) {
        await _advance(tester, step);
        _expectSame(_given(tester, a, share), positioned,
            '$at: given what a positioned driver under the watch is');
      }
      await _advance(tester, const Duration(seconds: 15));
      _expectGiven(_given(tester, a, share),
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          when: 'at 61 s: a watch compounds with an unlocated position');
    });

    testWidgets(
        'under a measured 80 m, a fix that then arrives is not told twice',
        (tester) async {
      final p = _Positioned();
      final a = await _boot(tester, source: p.source);
      final share = await _tapShare(tester, a);
      await _advance(tester, const Duration(seconds: 16));
      _expectGiven(_given(tester, a, share),
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          when: 'at 16 s, before any fix');
      await _advance(tester, const Duration(seconds: 4));
      p.fix();
      await _advance(tester, const Duration(seconds: 2), each: p.fix);
      _expectGiven(_given(tester, a, share),
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          when: 'at 22 s, a trusted fix given at 20 s');
    });

    for (final (label, visibility) in <(String, int?)>[
      ('no visibility reading', null),
      ('a measured clear 1,500 m', 1500),
    ]) {
      testWidgets(
          '$label: nothing measured raises caution, so what the never-shared '
          'driver is given, at 16 s, 61 s and 11 min', (tester) async {
        const marks = [
          Duration(seconds: 16),
          Duration(seconds: 61),
          Duration(minutes: 11),
        ];
        var a = await _boot(tester, visibilities: [visibility]);
        final never = <_Given>[];
        var at = Duration.zero;
        for (final m in marks) {
          await _advance(tester, m - at);
          at = m;
          never.add(_given(tester, a));
        }
        expect(never.first.rung, _none,
            reason: 'control: the never-shared driver has no rung');

        final p = _Positioned();
        a = await _boot(tester, source: p.source, visibilities: [visibility]);
        final share = await _tapShare(tester, a);
        at = Duration.zero;
        for (var i = 0; i < marks.length; i++) {
          await _advance(tester, marks[i] - at);
          at = marks[i];
          _expectSame(_given(tester, a, share), never[i], 'at ${marks[i]}');
        }
      });
    }
  });

  // -------------------------------------- the dialog, through the platform ----

  group('the app\'s own position stream, through the platform channels', () {
    const method = MethodChannel('flutter.baseflow.com/geolocator');
    const updates = EventChannel('flutter.baseflow.com/geolocator_updates');
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger().setMockMethodCallHandler(method, null);
      messenger().setMockStreamHandler(updates, null);
    });

    /// 50 s on the permission dialog, then [answer]: 2 allows while in use,
    /// 0 is her no. With [refuseAtSubscribe] the platform allows and then
    /// refuses when the stream is listened to (PERMISSION_DENIED).
    void platform({required int answer, bool refuseAtSubscribe = false}) {
      messenger().setMockMethodCallHandler(method, (call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 0;
          case 'requestPermission':
            await Future<void>.delayed(const Duration(seconds: 50));
            return answer;
        }
        return null;
      });
      messenger().setMockStreamHandler(
        updates,
        MockStreamHandler.inline(
          onListen: (_, events) {
            if (refuseAtSubscribe) {
              events.error(
                code: 'PERMISSION_DENIED',
                message:
                    "User denied permissions to access the device's location.",
              );
            }
          },
        ),
      );
    }

    testWidgets(
        'under a measured 80 m: nothing while the dialog is up; once she '
        'allows, the top rung, the stop line once and the critical haptic '
        'once within 15 s of the subscription', (tester) async {
      platform(answer: 2);
      final a = await _boot(tester); // no injected source: the app's own
      final share = await _tapShare(tester, a);
      await _advance(tester, const Duration(seconds: 45));
      final onDialog = _given(tester, a, share);
      expect(onDialog.spoken, isEmpty, reason: 'at 45 s, on the dialog');
      expect(onDialog.felt, isEmpty, reason: 'at 45 s, on the dialog');
      for (final (at, step) in [
        ('at 66 s, 16 s after she allowed', const Duration(seconds: 21)),
        ('at 135 s', const Duration(seconds: 69)),
      ]) {
        await _advance(tester, step);
        _expectGiven(_given(tester, a, share),
            rung: _top,
            spoken: ['stop'],
            felt: ['critical'],
            cause: true,
            when: at);
      }
    });

    for (final (label, refuseAtSubscribe, answer) in <(String, bool, int)>[
      ('her no on the dialog', false, 0),
      ('a refusal the platform sends when the stream subscribes', true, 2),
    ]) {
      testWidgets(
          'under a measured 80 m, $label is not answered: nothing is spoken '
          'or felt after her tap, to the 10-minute refresh', (tester) async {
        platform(answer: answer, refuseAtSubscribe: refuseAtSubscribe);
        final a = await _boot(tester);
        final share = await _tapShare(tester, a);
        for (final when in [
          const Duration(seconds: 51),
          const Duration(seconds: 66),
          const Duration(minutes: 10, seconds: 15),
        ]) {
          await _advance(tester, when - (_now.difference(_start)));
          final g = _given(tester, a, share);
          expect(g.spoken, isEmpty, reason: 'at $when');
          expect(g.felt, isEmpty, reason: 'at $when');
        }
      });
    }
  });

  // -------------------------------------------------------- no share running ----

  group('no share running', () {
    testWidgets(
        'never shared, a measured 80 m at start: the top rung with its cause, '
        'the stop line once and the critical haptic once; nothing more at 61 s '
        'or after the 10-minute refresh', (tester) async {
      final a = await _boot(tester);
      for (final (at, step) in [
        ('at 1 s', const Duration(seconds: 1)),
        ('at 61 s', const Duration(seconds: 60)),
        ('at 10 min 15 s', const Duration(minutes: 9, seconds: 14)),
      ]) {
        await _advance(tester, step);
        _expectGiven(_given(tester, a),
            rung: _top,
            spoken: ['stop'],
            felt: ['critical'],
            cause: true,
            when: at);
      }
      expect(_fetches, greaterThanOrEqualTo(2),
          reason: 'control: the 10-minute refresh ran');
    });

    testWidgets(
        'never shared, 80 m arriving at the 10-minute refresh: nothing before '
        'it, then told once', (tester) async {
      final a = await _boot(tester, visibilities: const [1500, 80]);
      await _advance(tester, const Duration(seconds: 1));
      _expectGiven(_given(tester, a),
          rung: _none,
          spoken: [],
          felt: [],
          cause: false,
          when: 'at 1 s, under a measured clear 1,500 m');
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      _expectGiven(_given(tester, a),
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          cause: true,
          when: 'at 10 min 16 s, 80 m measured at 10 min');
    });

    testWidgets(
        'a reading whose age flickers does not open the whiteout again: 80 m, '
        'a failed refresh, then 80 m: told once', (tester) async {
      final a = await _boot(tester,
          visibilities: const [80], failing: const [false, true, false]);
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      expect(_fetches, 2, reason: 'control: the failed refresh ran');
      await _advance(tester, const Duration(minutes: 10));
      expect(_fetches, 3, reason: 'control: 80 m came back at 20 min');
      // A failed refresh speaks its own feed-loss line, so only the rung's own
      // lines and the critical haptic are counted.
      final g = _given(tester, a);
      expect(g.rung, _top, reason: 'at 20 min 15 s');
      expect(g.spoken.where((s) => s == 'stop' || s == 'slow').toList(),
          ['stop'],
          reason: 'at 20 min 15 s: told once, at the start');
      expect(g.felt.where((h) => h == 'critical').toList(), ['critical'],
          reason: 'at 20 min 15 s: felt once, at the start');
    });

    testWidgets(
        'a new opening is told again: 80 m, a measured 300 m, then 80 m: told '
        'once per opening', (tester) async {
      final a = await _boot(tester, visibilities: const [80, 300, 80]);
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      _expectGiven(_given(tester, a),
          rung: _none,
          spoken: ['stop'],
          felt: ['critical'],
          when: 'at 10 min 15 s: 300 m measured, the whiteout closed');
      await _advance(tester, const Duration(minutes: 10));
      _expectGiven(_given(tester, a),
          rung: _top,
          spoken: ['stop', 'stop'],
          felt: ['critical', 'critical'],
          cause: true,
          when: 'at 20 min 15 s: 80 m measured again');
    });

    testWidgets(
        'her no to location, in a measured 80 m told at start: nothing after '
        'her no, and she is given what the never-shared driver is given at '
        '61 s and after the refresh', (tester) async {
      final never = await _boot(tester);
      await _advance(tester, const Duration(seconds: 61));
      final never61 = _given(tester, never);
      await _advance(tester, const Duration(minutes: 10));
      final never11 = _given(tester, never);
      _expectGiven(never61,
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          cause: true,
          when: 'the never-shared driver at 61 s');

      final a = await _boot(tester, source: _refused);
      final share = await _tapShare(tester, a);
      await _advance(tester, const Duration(seconds: 61));
      _expectSame(_given(tester, a), never61, 'at 61 s');
      await _advance(tester, const Duration(minutes: 10));
      _expectSame(_given(tester, a), never11, 'at 11 min 1 s');
      expect(_given(tester, a, share).spoken, isEmpty,
          reason: 'nothing spoken after her no');
      expect(_given(tester, a, share).felt, isEmpty,
          reason: 'nothing felt after her no');
    });

    testWidgets(
        'her no to location under a measured clear 1,500 m, then 80 m at the '
        'refresh: the measured whiteout is told once', (tester) async {
      final a = await _boot(tester,
          source: _refused, visibilities: const [1500, 80]);
      final share = await _tapShare(tester, a);
      await _advance(tester, const Duration(seconds: 5));
      _expectGiven(_given(tester, a, share),
          rung: _none,
          spoken: [],
          felt: [],
          when: 'control: nothing after her no under 1,500 m');
      await _advance(tester, const Duration(minutes: 10, seconds: 10));
      _expectGiven(_given(tester, a, share),
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          cause: true,
          when: 'at 10 min 15 s, 80 m measured at 10 min');
    });

    testWidgets(
        'nothing comes from an ended share\'s position: positioned under a '
        'measured clear 1,500 m, 停止, and 700 m at the refresh: no rung, '
        'nothing spoken or felt', (tester) async {
      final p = _Positioned();
      final a = await _boot(tester,
          source: p.source, visibilities: const [1500, 700]);
      await _tapShare(tester, a);
      p.fix();
      await _advance(tester, const Duration(seconds: 1), each: p.fix);
      expect(_rung(tester), isNot(_none),
          reason: 'control: the share gave the drive brain a position');
      await _tapStop(tester);
      final stopped = _mark(a);
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      expect(_fetches, greaterThanOrEqualTo(2),
          reason: 'control: 700 m was fetched');
      _expectGiven(_given(tester, a, stopped),
          rung: _none,
          spoken: [],
          felt: [],
          when: 'after 停止, at the refresh that brought 700 m');
    });

    testWidgets(
        'a whiteout that opens after 停止 is given to her as to the '
        'never-shared driver', (tester) async {
      final never = await _boot(tester, visibilities: const [700, 80]);
      final neverBefore = _mark(never);
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      final neverGiven = _given(tester, never, neverBefore);
      _expectGiven(neverGiven,
          rung: _top,
          spoken: ['stop'],
          felt: ['critical'],
          cause: true,
          when: 'the never-shared driver at 10 min 15 s');

      final p = _Positioned();
      final a = await _boot(tester,
          source: p.source, visibilities: const [700, 80]);
      await _tapShare(tester, a);
      p.fix();
      await _advance(tester, const Duration(seconds: 1), each: p.fix);
      await _tapStop(tester);
      final stopped = _mark(a);
      await _advance(tester, const Duration(minutes: 10, seconds: 14));
      _expectSame(_given(tester, a, stopped), neverGiven,
          'after 停止, at 10 min 15 s');
    });

    testWidgets(
        'recorded, not ruled: with no share running, a measured 300 m is told '
        'nothing', (tester) async {
      final a = await _boot(tester, visibilities: const [300]);
      await _advance(tester, const Duration(minutes: 10, seconds: 15));
      _expectGiven(_given(tester, a),
          rung: _none, spoken: [], felt: [], when: 'at 10 min 15 s');
    });
  });
}
