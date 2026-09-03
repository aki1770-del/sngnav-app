/// COLD-HANDS TAP TARGETS — the diary chips are MEASURED at the accessible
/// minimum, not asserted to be.
///
/// WHY (render-SEEN 2026-07-27, ladder_out/drive_diary/diary_form_ja.png): the
/// post-drive form's chips rendered at roughly 32 dp tall under the ambient
/// visual density. She fills this form in a parked car, in the dark, possibly
/// elderly, with cold or gloved fingers. A mis-tap does not merely annoy her —
/// it writes the WRONG road surface into the season's evidence, and a wrong
/// entry is worse than a missing one because the reader cannot tell that it is
/// wrong.
///
/// 48 dp is the platform minimum touch target on both Android and iOS. This
/// file measures the real rendered hit area from the real app tree, so the
/// claim can never decay into a comment that used to be true.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/drive_diary.dart';

/// Platform minimum touch target (Material + HIG agree at 48 / 44; the
/// stricter of the two is used).
const double kMinTouchTarget = 48.0;

void main() {
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('sngnav_diary_tap');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDownAll(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<void> openForm(WidgetTester tester) async {
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
    await tester.ensureVisible(find.byKey(const Key('diary-panel')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('diary-write-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('every road chip meets the 48 dp touch minimum',
      (tester) async {
    await openForm(tester);

    for (final c in DiaryRoadCondition.values) {
      final finder = find.byKey(Key('diary-road-${c.token}'));
      expect(finder, findsOneWidget,
          reason: 'road chip ${c.token} is missing from the form');

      // The chip's own gesture area, including the invisible padding that
      // MaterialTapTargetSize.padded adds — this is what her finger hits.
      final size = tester.getSize(finder);
      expect(
        size.height,
        greaterThanOrEqualTo(kMinTouchTarget),
        reason: 'road chip "${c.ja}" (${c.token}) renders '
            '${size.height.toStringAsFixed(1)} dp tall — below the '
            '$kMinTouchTarget dp minimum. A cold or gloved finger in a dark '
            'parked car will mis-tap it, writing the wrong surface into the '
            "season's evidence.",
      );
    }
  });

  testWidgets('every advisory chip meets the 48 dp touch minimum',
      (tester) async {
    await openForm(tester);

    for (final a in DiaryAdvisoryExperience.values) {
      final finder = find.byKey(Key('diary-advisory-${a.token}'));
      expect(finder, findsOneWidget);
      final size = tester.getSize(finder);
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
          reason: 'advisory chip "${a.ja}" (${a.token}) renders '
              '${size.height.toStringAsFixed(1)} dp tall — below the '
              '$kMinTouchTarget dp minimum.');
    }
  });

  testWidgets('the black-ice chip is present and selectable — she can report '
      'the surface the app warns her about', (tester) async {
    await openForm(tester);

    final blackIce = find.byKey(const Key('diary-road-black-ice'));
    expect(blackIce, findsOneWidget,
        reason: 'the app speaks and draws ブラックアイスバーン as its flagship '
            'in-drive advisory; the diary must let her report that surface');

    await tester.tap(blackIce);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diary-save-button')));
    await tester.pumpAndSettle();

    // The token must reach the file the reader collates, and the ja term must
    // reach the human who reads it.
    final text = File('${tmp.path}/drive_diary.txt').readAsStringSync();
    expect(text, contains('black-ice'));
    expect(text, contains('ブラックアイスバーン'));
  });

  testWidgets('the too-late / false-alarm guidance is HELPER text, so it '
      'renders without focusing the note field', (tester) async {
    await openForm(tester);

    // Before 2026-08-10 this line was a hintText. With an OutlineInputBorder
    // and a labelText, the floating label occupies the hint's position until
    // the field is focused, so the hint was invisible to a driver who never
    // tapped into the box — and she therefore never learned she could say
    // "the warning came, but too late", the most actionable thing she can
    // tell us. helperText renders unconditionally, below the box.
    //
    // ASSERTED ON THE DECORATION, NOT ON find.text: Flutter keeps the hint
    // widget in the tree at zero opacity, so a find.text probe passes
    // identically for hintText and helperText and would guard nothing. That
    // false-green was caught by deliberately reverting the fix and watching
    // this test stay green (2026-08-10).
    final field = tester.widget<TextField>(
      find.byKey(const Key('diary-note-field')),
    );
    final decoration = field.decoration!;

    expect(decoration.helperText, '例：橋の上で警告が遅かった、誤警告だった など',
        reason: 'the note guidance must be helperText so it renders before '
            'she taps the field');
    expect(decoration.hintText, isNull,
        reason: 'the guidance must not be re-hidden behind the floating '
            'label as a hintText');
  });
}
