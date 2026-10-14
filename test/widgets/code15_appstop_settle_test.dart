/// Code 15: the app's own ending of a share on the SETTLE path writes
/// `appstop`, and no `leave`.
///
/// Why, written before the act (2026-10-10). A share without its foreground
/// service that subscribes while the app is already away is ended by the app
/// when a 2 s settle window runs out (main b970dec). Its leave happened before
/// the share's stream subscribed, so the record holds no leave for it. Without
/// an `appstop` line the record shows a share that simply stops, which the
/// reading's bars misread several ways; the 2026-10-10 safety ruling (item 1,
/// pin 4) requires the line here too.
///
/// This runs through the REAL position path (the geolocator platform and the
/// notification channel faked), as test/widgets/
/// share_without_service_start_guard_test.dart does: an injected source counts
/// as subscribed at the tap and cannot reach the settle window.
///
/// HONEST BOUND. A test binding, not a phone.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/code15_fix_interval_record.dart';
import 'package:sngnav_app/services/notification_permission.dart';
import 'package:sngnav_app/services/share_without_service.dart'
    show kShareAwaySettle;

import '../support/fake_alert_actuators.dart';
import '../support/test_record_writer.dart';

const String _n1 = 'アプリが画面から離れたため、現在地の警告は止まりました。';

Future<void> _settleIO(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

class _FakeGeolocator extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  int requests = 0;
  Completer<LocationPermission>? _answer;
  final positions = StreamController<Position>.broadcast();
  int streamsStarted = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() {
    requests++;
    return (_answer = Completer<LocationPermission>()).future;
  }

  void answer(LocationPermission p) {
    permission = p;
    _answer?.complete(p);
    _answer = null;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamsStarted++;
    return positions.stream;
  }
}

class _NotificationChannel {
  Completer<bool>? _answer;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'read':
        return <String, Object>{
          'granted': false,
          'enabled': true,
          'needsRuntimeRequest': true,
        };
      case 'request':
        final yes = await (_answer = Completer<bool>()).future;
        _answer = null;
        return yes;
    }
    return null;
  }

  void answer({required bool allow}) => _answer?.complete(allow);
}

void main() {
  late Directory tmp;
  late GeolocatorPlatform originalGeolocator;
  late _FakeGeolocator geo;
  late _NotificationChannel notif;
  late FakeAlertActuators a;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('code15_appstop_settle');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    notif = _NotificationChannel();
    messenger.setMockMethodCallHandler(
      NotificationPermission.channel,
      notif.handle,
    );
    originalGeolocator = GeolocatorPlatform.instance;
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
    a = FakeAlertActuators();
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(NotificationPermission.channel, null);
    GeolocatorPlatform.instance = originalGeolocator;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void to(WidgetTester tester, AppLifecycleState s) =>
      tester.binding.handleAppLifecycleStateChanged(s);

  testWidgets('subscribed while away, still away at the end of the settle '
      'window: the record holds `appstop` for that share, no `leave`, no `end`',
      (tester) async {
    final recordDir = Directory('${tmp.path}/record')..createSync();
    final record = Code15FixIntervalRecord(writer: kTestRecordWriter, directory: recordDir);
    var now = DateTime.utc(2026, 1, 14, 21);
    await tester.pumpWidget(
      SngnavApp(
        locale: const Locale('ja'),
        actuators: a,
        clock: () => now,
        jmaFetch: () async => const JmaFailure('test: no observation'),
        code15Record: record,
      ),
    );
    await _settleIO(tester);
    final share = find.byKey(const Key('share-location-button'));
    await tester.ensureVisible(share);
    await tester.pump();
    await tester.tap(share);
    await _settleIO(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('location-consent-accept')));
    await _settleIO(tester);
    to(tester, AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));
    notif.answer(allow: false); // no notification: a share without its service
    to(tester, AppLifecycleState.resumed);
    await _settleIO(tester);
    expect(geo.requests, 1, reason: 'control: the location ask is pending');

    // She leaves while the share waits on her answer: nothing has subscribed.
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      to(tester, s);
      await tester.pump();
    }
    await _settleIO(tester);
    expect(record.readAll(), isNot(contains('k=leave')),
        reason: 'a leave before the subscription has no share t');

    geo.answer(LocationPermission.whileInUse);
    await _settleIO(tester);
    expect(geo.streamsStarted, 1, reason: 'control: it subscribed');
    expect(record.readAll(), contains(' k=start '),
        reason: 'control: the share\'s stream subscribed and was recorded');
    expect(record.readAll(), isNot(contains('k=appstop')),
        reason: 'inside the settle window nothing is ended yet');

    now = now.add(kShareAwaySettle);
    await tester.pump(kShareAwaySettle);
    await _settleIO(tester);
    expect(a.spoken.map((x) => x.text).where((t) => t == _n1), hasLength(1),
        reason: 'control: the app ended the share itself, told once');
    final lines =
        record.readAll().split('\n').where((l) => l.isNotEmpty).toList();
    final start = lines.firstWhere((l) => l.contains(' k=start '));
    final s = RegExp(r'^s=(\d+) ').firstMatch(start)!.group(1);
    final mine = [for (final l in lines) if (l.startsWith('s=$s ')) l];
    expect(mine.last, matches(RegExp('^s=$s t=\\d+ k=appstop\$')),
        reason: lines.join('\n'));
    expect(mine.where((l) => l.endsWith(' k=appstop')), hasLength(1));
    expect(record.readAll(), isNot(contains('k=leave')));
    expect(record.readAll(), isNot(contains('k=end')));

    for (final s in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      to(tester, s);
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
