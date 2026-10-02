// Every test under test/ runs through this file: flutter_tools uses the
// nearest flutter_test_config.dart above a test file and stops looking at
// the directory that holds pubspec.yaml.
//
// It keeps Flutter's debug banner out of every widget test, and so out of
// every stored golden. In debug mode the banner is drawn across the top-end
// corner of the app; a release build never draws it. A golden that carries
// it shows something she never sees, and can hide something she does. A
// golden host can set debugShowCheckedModeBanner: false, and many do, but
// eighteen goldens were stored with the banner because their hosts did not.
// One setting here also covers the hosts that have not been written yet.
//
// WidgetsApp.debugAllowBannerOverride is the switch Flutter itself uses to
// hide the banner for screenshots (`flutter run`, key "s"). It is set for
// tests only: nothing under lib/ changes, and a debug build of the app
// still shows the banner.
//
// It also loads the fonts the app ships (test/support/shipped_fonts.dart).
// `flutter test` leaves them out, so without this every icon is drawn as an
// empty box, and so is any symbol only the app's own symbols font carries:
// in her app bar, at the head of a warning row, on her map, and as the ⚠
// that opens a watch verdict. Goldens were stored with those boxes because their suites
// did not load the fonts one by one. Loading them here also covers the
// suites that have not been written yet.
//
// test/no_debug_banner_in_tests_test.dart and
// test/shipped_fonts_in_tests_test.dart fail if this stops being true.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'support/shipped_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetsApp.debugAllowBannerOverride = false;
  await loadShippedFonts();
  await testMain();
}
