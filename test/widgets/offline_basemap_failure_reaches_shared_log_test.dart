/// When the offline basemap cannot be built, the reason reaches the log she
/// can share (ログを共有), not only the console.
///
/// Why this test exists. Before 2026-10-01 the loader returned the builder's
/// future without `await`, so a failure escaped it. It then reached the crash
/// boundary's `PlatformDispatcher.onError`, which writes into this same
/// `LocalErrorLog`. Adding the `await` put the failure inside the loader's
/// catch, which only called `debugPrint`. `debugPrint` goes to the console and
/// logcat, never to this log. So fixing the promise in the loader's doc
/// comment took the failure out of the one log a tester can send. The map
/// looked the same either way: it falls back to the network basemap.
///
/// This drives the real app with a real `LocalErrorLog`. path_provider's
/// temporary directory is answered with a directory that does not exist, so
/// the archive write inside the builder fails, as it would on a phone with no
/// room left. Only the offline basemap loader asks for the temporary directory
/// (`lib/`, measured 2026-10-01), so that channel call shows the loader got as
/// far as the builder. The positive control answers with a directory that
/// exists, and the same wait sees the archive written there with nothing
/// logged. That shows the harness lets the loader run to its end.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/error_log.dart';
import 'package:sngnav_app/services/offline_basemap.dart'
    show akitaOfflineMbtilesAsset;

import '../support/fake_alert_actuators.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _entryTag = '[offline-basemap]';

void main() {
  late Directory root;
  late List<String> channelCalls;

  setUp(() {
    root = Directory.systemTemp.createTempSync('offline_basemap_shared_log');
    channelCalls = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Starts the app with [log] and path_provider's temporary directory at
  /// [temporaryDirectory]. Every other directory the app asks for is a real
  /// one under [root]. Then gives the app's real file work real time, in
  /// short slices with the app's microtasks flushed between them, until
  /// [done] holds or ten seconds pass.
  Future<void> startApp(
    WidgetTester tester, {
    required LocalErrorLog log,
    required String temporaryDirectory,
    required bool Function() done,
  }) async {
    final other = Directory('${root.path}/support')..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async {
          channelCalls.add(call.method);
          return call.method == 'getTemporaryDirectory'
              ? temporaryDirectory
              : other.path;
        });
    await tester.pumpWidget(
      SngnavApp(
        locale: const Locale('ja'),
        actuators: FakeAlertActuators(),
        jmaFetch: () async => const JmaFailure('test: deterministic, no feed'),
        errorLog: log,
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'control: with a temporary directory to write into, the app builds the '
    'offline basemap and her log gets no entry for it',
    (tester) async {
      final log = LocalErrorLog(file: File('${root.path}/error_log.txt'));
      final archive = File(
        '${root.path}/${akitaOfflineMbtilesAsset.split('/').last}',
      );

      await startApp(
        tester,
        log: log,
        temporaryDirectory: root.path,
        done: archive.existsSync,
      );

      expect(
        channelCalls,
        contains('getTemporaryDirectory'),
        reason: 'the app started the offline basemap loader',
      );
      expect(
        archive.existsSync(),
        isTrue,
        reason: 'the loader ran to the builder, which wrote the archive',
      );
      expect(
        log.readAll(),
        isNot(contains(_entryTag)),
        reason: 'nothing failed, so nothing is logged for the basemap',
      );
    },
  );

  testWidgets(
    'a failure building the offline basemap reaches the log she can share',
    (tester) async {
      final log = LocalErrorLog(file: File('${root.path}/error_log.txt'));
      final absent = '${root.path}/not_there';

      await startApp(
        tester,
        log: log,
        temporaryDirectory: absent,
        done: () => log.readAll().contains(_entryTag),
      );

      expect(
        channelCalls,
        contains('getTemporaryDirectory'),
        reason:
            'the loader got as far as the builder: the asset loaded and '
            'the temporary directory was asked for',
      );
      final text = log.readAll();
      expect(
        text,
        contains(_entryTag),
        reason:
            'the failure did not reach the log ログを共有 shares. What '
            'is in it: "$text"',
      );
      expect(
        text,
        contains(absent),
        reason:
            'the entry is the builder\'s write into the directory that '
            'is not there',
      );
    },
  );
}
