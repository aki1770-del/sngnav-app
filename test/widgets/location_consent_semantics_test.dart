// W2 ladder fixes (a) + (b) — the location-consent card.
//
// (b) OPS-059 correction-class: the emulator ladder flagged the consent
// actions' semantics (ladder_out/api30/ui_dump_06.xml showed
// bounds=[0,0][0,0]; FINDINGS.md item 2). This test pins the assistive-tech
// floor: both consent actions must expose BUTTON semantics with a TAP
// action, be focusable, carry their label, and occupy a real (non-zero,
// >=48px-tall) on-screen rect when visible. If a future change buries them
// in a widget that defeats semantics, this fails.
//
// (a) Layout: the status line ("Location not yet shared.") must sit ABOVE
// the action buttons at full card width — never crammed into a narrow
// column beside them (the one-syllable-per-line mangling in
// ladder_out/api30/02b_location_consent.png).

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/main.dart';

void main() {
  Future<void> pumpAndReveal(WidgetTester tester) async {
    await tester.pumpWidget(const SngnavApp(locale: Locale('en')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('share-location-button')));
    await tester.pump();
  }

  testWidgets(
      'consent actions expose real tap targets to assistive tech '
      '(button + tap action + focusable + non-zero >=48px rect)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAndReveal(tester);

    for (final (key, label) in [
      ('share-location-button', 'Share my location'),
      ('use-mock-button', 'Use Akita mock (dev)'),
    ]) {
      final finder = find.byKey(Key(key));
      final node = tester.getSemantics(finder);
      expect(
        node,
        matchesSemantics(
          label: label,
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
        reason: '$key must be a real, labelled, tappable semantics target',
      );
      // Zero-size was the ladder defect-signal: the node must occupy the
      // widget's real on-screen rect, tall enough to tap (>= 48 logical px
      // -- the Material minimum tap target the ladder measured as 132
      // physical px at 2.75x).
      final paintBounds = node.rect;
      expect(paintBounds.isEmpty, isFalse,
          reason: '$key semantics rect must not be zero-size when visible');
      expect(paintBounds.height, greaterThanOrEqualTo(48.0),
          reason: '$key tap target must be at least 48 logical px tall');
      expect(paintBounds.width, greaterThan(0));
    }

    semantics.dispose();
  });

  testWidgets(
      'status line sits ABOVE the consent buttons at full card width '
      '(no narrow-column mangling)', (tester) async {
    await pumpAndReveal(tester);

    final statusFinder = find.text('Location not yet shared.');
    expect(statusFinder, findsOneWidget);

    final statusRect = tester.getRect(statusFinder);
    final shareRect =
        tester.getRect(find.byKey(const Key('share-location-button')));
    final disclosureRect =
        tester.getRect(find.byKey(const Key('location-disclosure')));

    // Above the buttons — not beside them.
    expect(statusRect.bottom, lessThanOrEqualTo(shareRect.top),
        reason: 'the status line must be a full row above the buttons');
    // Full card width: the status text box spans (at least) the same width
    // the disclosure paragraph gets — the old defect gave it a sliver.
    final statusBox = tester.renderObject<RenderBox>(statusFinder);
    expect(statusBox.size.width, greaterThanOrEqualTo(disclosureRect.width),
        reason: 'the status line must get the full card width');
    // And it renders on ONE line at this width (the mangling regression
    // guard): height of the laid-out text == a single line's height.
    final oneLineHeight =
        (statusBox as RenderParagraph).getMaxIntrinsicHeight(double.infinity);
    expect(statusBox.size.height, moreOrLessEquals(oneLineHeight),
        reason: '"Location not yet shared." must render as one sentence line');
  });
}
