/// OPS-066 render-SEE capture for the Ring-2 運転日記 card + entry form
/// (session-scope; NOT a CI pixel assertion) — three-month plan §2.
///
/// Produces PNGs under `ladder_out/drive_diary/` so a human LOOKS at what
/// the parked driver sees: the diary card (status + actions + consent
/// disclosure) and the open entry dialog (road/advisory chips incl. the
/// 圧雪 chip, area + note fields). Pumps the REAL SngnavApp with an
/// injected DriveDiary — the pixels are the app's own widget tree.
///
/// On-device render remains the device hour's job (OPS-066 / AAE lane):
/// nobody affirms these PNGs as HER-phone evidence, and on a fontless
/// host the comparator is a no-op (render pipeline still exercised).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'render_see_env.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/drive_diary.dart';

void main() {
  const ipa = '/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf';
  const droid = '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cjkLoaded = await loadCjkFamily('Roboto', [ipa, droid]);
    if (!cjkLoaded) installNoopGoldenComparator();
    tmp = await Directory.systemTemp.createTemp('sngnav_diary_capture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDownAll(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  testWidgets('the diary card and the entry form, from the real app tree',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final diary = DriveDiary(file: File('${tmp.path}/drive_diary.txt'));
    await tester.pumpWidget(SngnavApp(
      locale: const Locale('ja'),
      diary: diary,
      diaryShareSink: (_) async {},
    ));
    await tester.pump();

    final panel = find.byKey(const Key('diary-panel'));
    await tester.ensureVisible(panel);
    await tester.pump();
    await expectLater(
      panel,
      matchesGoldenFile('../../ladder_out/drive_diary/diary_card_ja.png'),
    );

    await tester.tap(find.byKey(const Key('diary-write-button')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../../ladder_out/drive_diary/diary_form_ja.png'),
    );
  });
}
