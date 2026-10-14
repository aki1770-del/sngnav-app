/// ShareStartRow's PIN rule yields to the reserved end when PIN would bring
/// 現在地を共有 within 24 dp of the column where 停止 or 閉じる is drawn
/// (code 16, 2026-10-14).
///
/// WHY. PIN keeps the share control where his thumb already goes, one
/// withdrawal-width plus 8 dp left of the row's end. That place is clear of the
/// end column only while the withdrawal's label is wider than 停止's and
/// 閉じる's by 16 dp or more. With the app's own labels it always is, at every
/// size the stop-spot guard covers, so the guard never sees the condition bind:
/// a mutant that removed it survived (the consent review, 2026-10-14). A label
/// change (a translation, a shorter withdrawal, a longer 停止) would reach the
/// one place no test had seen work. Sakichi Vision 15: detected instantly,
/// not found downstream.
///
/// WHAT A PASS MEANS. The real ShareStartRow, laid out with labels chosen so
/// the condition binds, takes the reserved end: start-aligned, its right edge
/// at least 24 dp left of the end column. A control with the app's own labels
/// takes PIN, at the place PIN defines. Not a device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/widgets/share_start_row.dart';

void main() {
  /// Lays out the row [width] dp wide (800: the test font draws every letter
  /// a full em, so code 15's one-line row needs room), starting at x = 0, and
  /// returns the
  /// share control's rectangle, the rule taken, and the end column's width as
  /// the row computed it.
  Future<(Rect, ShareStartRule, double, double)> layOut(
    WidgetTester tester, {
    required String withdraw,
    required String stop,
    required String close,
    double width = 800,
  }) async {
    late double endColumn;
    late double withdrawW;
    await tester.pumpWidget(
      MaterialApp(
        theme: sngnavTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Builder(
                builder: (context) {
                  endColumn = [stop, close]
                      .map((t) => textButtonNaturalWidth(context, t))
                      .reduce((a, b) => a > b ? a : b);
                  withdrawW = textButtonNaturalWidth(context, withdraw);
                  return ShareStartRow(
                    share: TextButton(
                      key: const Key('share'),
                      onPressed: () {},
                      child: const Text('Share'),
                    ),
                    withdrawLabel: withdraw,
                    stopLabel: stop,
                    closeLabel: close,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    // A component element reports its child's render object too: one object, seen twice.
    final row = tester.allRenderObjects
        .whereType<RenderShareStartRow>()
        .toSet()
        .single;
    return (
      tester.getRect(find.byKey(const Key('share'))),
      row.rule,
      endColumn,
      withdrawW,
    );
  }

  testWidgets('control: with a wide withdrawal, PIN holds the share control at '
      'its place, clear of the end column', (tester) async {
    final (r, rule, endColumn, withdrawW) = await layOut(
      tester,
      withdraw: 'Withdraw sharing consent',
      stop: 'Stop',
      close: 'Close',
    );
    expect(rule, ShareStartRule.pin);
    expect(
      r.right,
      closeTo(800 - withdrawW - 8, 0.01),
      reason: 'PIN: one withdrawal-width plus 8 dp left of the row\'s end',
    );
    expect(800 - endColumn - r.right, greaterThanOrEqualTo(kStopSpotClearance));
  });

  testWidgets('where PIN would come within 24 dp of the end column, the row '
      'takes the reserved end instead', (tester) async {
    // A narrow withdrawal and a wide end column: the one-line row fits, and
    // PIN's place would lie inside the end column.
    final (r, rule, endColumn, withdrawW) = await layOut(
      tester,
      withdraw: 'W',
      stop: 'Stop recording',
      close: 'Close',
    );
    expect(
      withdrawW + 8,
      lessThan(kStopSpotClearance + endColumn),
      reason: 'control: these labels make the condition bind',
    );
    expect(rule, ShareStartRule.reservedEnd);
    expect(r.left, 0, reason: 'start-aligned');
    expect(
      800 - endColumn - r.right,
      greaterThanOrEqualTo(kStopSpotClearance),
      reason: 'the share control stays 24 dp clear of the end column',
    );
  });
}
