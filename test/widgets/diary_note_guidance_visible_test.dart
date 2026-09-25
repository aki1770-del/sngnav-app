// The diary note's guidance is drawn when the form opens (2026-09-25).
//
// WHY: the guidance line (e.g. "the warning came late on the bridge, or was a
// false alarm") was an InputDecoration hintText beside a labelText. Flutter
// paints such a hint at opacity 0 until the field has focus, so a screen
// review found it invisible in all 6 cases (2 languages x 3 text scales) when
// the form opened. It is now a helperText, which is always drawn.
//
// WHAT THIS DOES NOT CHECK, and it is the larger half: WHERE the line is. In
// Japanese the note field opens below the dialog's fold at every text scale,
// so she still has to scroll to see it. This test checks that the line is
// drawn, not that it is in view.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart';
import 'package:sngnav_app/services/drive_diary.dart';

/// The opacity a widget is actually painted with: the product of every
/// Opacity and FadeTransition above it. AnimatedOpacity paints through a
/// FadeTransition, so it is counted there, once.
double _paintedOpacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  tester.element(finder).visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Opacity) opacity *= w.opacity;
    if (w is FadeTransition) opacity *= w.opacity.value;
    return true;
  });
  return opacity;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sngnav_diary_guidance');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: the note guidance is painted, unfocused, as the form '
        'opens', (tester) async {
      await tester.pumpWidget(SngnavApp(
        locale: Locale(lang),
        diary: DriveDiary(file: File('${tmp.path}/drive_diary.txt')),
        diaryShareSink: (_) async {},
      ));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('diary-write-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('diary-write-button')));
      await tester.pumpAndSettle();

      final guidance = find.text(AppL10n(Locale(lang)).diaryNoteHint);
      expect(guidance, findsOneWidget);
      expect(_paintedOpacity(tester, guidance), 1.0,
          reason: 'the guidance must be drawn before she taps the field');
    });
  }

  testWidgets('NEGATIVE CONTROL: a hintText beside a labelText is painted at '
      'opacity 0 until focus (the measure can see the old defect)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TextField(
          decoration: InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'guidance',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(_paintedOpacity(tester, find.text('guidance')), 0.0);
  });
}
