/// When building the offline basemap fails, the loader returns `null`, and
/// its own `catch` is the code that sees the failure.
///
/// Why this test exists. `loadOfflineTileProvider` returned
/// `buildOfflineTileProviderFromBytes(...)` from inside its `try` without
/// `await`. The builder is `async`. So when it failed (writing the archive
/// into the temporary directory, moving it into place, or opening it in
/// SQLite), the returned future completed with that error only after the
/// `try` had been left. The `catch` meant to turn the failure into a logged
/// `null` never ran, and the error escaped the loader. No test called either
/// loader, so nothing had driven that path. The first thing to report it was
/// a newer analyzer's `unawaited_return_in_try_block`, on Flutter 3.47.5.
///
/// The failure used here is one the builder can meet on her phone: the
/// temporary directory the platform names cannot be written into. The test
/// points path_provider at it by mocking its channel, as
/// test/services/update_check_test.dart does. A positive control runs the same
/// loader against a directory that exists. So the failing case cannot pass
/// just because the loader never reached the builder.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/offline_basemap.dart';

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _fallbackLine = 'offline basemap unavailable, falling back to network: ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late List<String> channelCalls;
  late List<String> printed;

  /// Points path_provider's temporary directory at [path], and records every
  /// call the loader makes on the channel.
  void temporaryDirectoryIs(String path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async {
          channelCalls.add(call.method);
          return call.method == 'getTemporaryDirectory' ? path : null;
        });
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('offline_basemap_fail_soft');
    channelCalls = [];
    printed = [];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    addTearDown(() => debugPrint = previous);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, null),
    );
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test('control: with a temporary directory to write into, the loader builds '
      'a provider and logs no fallback', () async {
    temporaryDirectoryIs(root.path);

    final provider = await loadAkitaOfflineTileProvider();
    addTearDown(() => provider?.dispose());

    expect(
      channelCalls,
      ['getTemporaryDirectory'],
      reason:
          'the loader asks path_provider for the directory this test '
          'controls, and for nothing else',
    );
    expect(
      provider,
      isNotNull,
      reason: 'the bundled Akita archive loads, is written and opens',
    );
    expect(
      printed.where((m) => m.startsWith(_fallbackLine)),
      isEmpty,
      reason: 'no fallback is logged when nothing failed',
    );
    expect(
      File(
        '${root.path}/${akitaOfflineMbtilesAsset.split('/').last}',
      ).existsSync(),
      isTrue,
      reason: 'the builder wrote the archive where the platform said',
    );
  });

  test('a failure inside the builder returns null, and the loader\'s catch '
      'logs it', () async {
    final absent = '${root.path}/not_there';
    temporaryDirectoryIs(absent);

    Object? escaped;
    Object? provider;
    try {
      provider = await loadAkitaOfflineTileProvider();
    } catch (e) {
      escaped = e;
    }

    expect(
      channelCalls,
      ['getTemporaryDirectory'],
      reason:
          'the loader got as far as the builder: the asset loaded and '
          'the temporary directory was asked for',
    );
    expect(
      escaped,
      isNull,
      reason:
          'the builder\'s failure escaped the loader. Its doc comment '
          'promises null on any failure, and its catch did not see this '
          'one. Escaped: $escaped',
    );
    expect(provider, isNull);
    final fallbacks = printed
        .where((m) => m.startsWith(_fallbackLine))
        .toList();
    expect(
      fallbacks,
      hasLength(1),
      reason:
          'the loader\'s catch ran once and logged why. Printed: '
          '$printed',
    );
    expect(
      fallbacks.single,
      contains(absent),
      reason:
          'the catch saw the write into the directory that is not '
          'there, not some earlier failure',
    );
  });
}
