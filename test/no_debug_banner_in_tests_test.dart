// The debug banner must not reach any golden, including the goldens nobody
// has written yet. test/flutter_test_config.dart turns it off for every test
// under test/. These tests fail if that stops being true.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'an app that leaves debugShowCheckedModeBanner at its default draws no '
      'debug banner', (tester) async {
    // The default is true. This is the host a new golden test writes when it
    // does not think about the banner.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(find.byType(CheckedModeBanner), findsNothing);
  });

  test('every flutter_test_config.dart under test/ turns the banner off', () {
    expect(File('test/flutter_test_config.dart').existsSync(), isTrue);
    // flutter_tools uses only the nearest config above a test file, so a
    // config added in a subdirectory would replace the root one for every
    // test below it. Each one must set the switch itself, in code.
    final setsIt = RegExp(
      r'^\s*WidgetsApp\.debugAllowBannerOverride\s*=\s*false\s*;',
      multiLine: true,
    );
    final configs = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last == 'flutter_test_config.dart');
    for (final f in configs) {
      expect(setsIt.hasMatch(f.readAsStringSync()), isTrue,
          reason: '${f.path} replaces the root config for the tests below it '
              'and does not turn the debug banner off');
    }
  });
}
