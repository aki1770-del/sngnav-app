// Standing loom: NO RenderFlex overflow anywhere in the app at phone width
// under the DEFAULT test font.
//
// Why the default font is the point: the test font's glyphs are wider than
// any real proportional font, so a Row that survives it survives real
// devices — and a Row that overflows under it is a brittle natural-size Row
// that will pinch on some real narrow/large-text device (accessibility
// text-scale users hit exactly this). This probe reproduces LOCALLY the
// conditions under which CI caught main.dart:621 and :2161 overflowing
// (2026-07-09) — every brittle Row fails HERE, with its file:line in the
// failure text, instead of one-per-CI-round.
//
// Deliberately does NOT load CJK fonts (unlike the render_see suites):
// tofu is fine, metrics are the test. Uses tester.takeException()
// collection — never overrides FlutterError.onError (the v1 probe did and
// fought the test binding).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';

Future<void> _probe(WidgetTester tester, Locale locale) async {
  tester.view.devicePixelRatio = 2.75;
  tester.view.physicalSize = const Size(393 * 2.75, 851 * 2.75);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final overflows = <String>[];
  void collect() {
    for (var e = tester.takeException(); e != null; e = tester.takeException()) {
      final s = e.toString();
      if (s.contains('overflowed')) {
        overflows.add(s);
      }
      // Non-overflow exceptions (e.g. blocked test-HttpClient tile fetches)
      // are swallowed here on purpose: this probe measures layout only; the
      // rest of the suite owns functional failures.
    }
  }

  await tester.pumpWidget(SngnavApp(locale: locale));
  await tester.pump();
  collect();

  // Walk the whole scrollable so every card lays out at phone width.
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 25; i++) {
    await tester.drag(scrollable, const Offset(0, -600), warnIfMissed: false);
    await tester.pump();
    collect();
  }

  expect(
    overflows.toSet().toList(),
    isEmpty,
    reason: 'Brittle fixed-size Rows at phone width '
        '(fix with Wrap/Expanded/Flexible):\n${overflows.toSet().join('\n---\n')}',
  );
}

void main() {
  testWidgets('no RenderFlex overflow at phone width (en)', (tester) async {
    await _probe(tester, const Locale('en'));
  });

  testWidgets('no RenderFlex overflow at phone width (ja)', (tester) async {
    await _probe(tester, const Locale('ja'));
  });
}
