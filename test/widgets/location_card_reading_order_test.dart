/// The location card and the consent dialog are read in the order they are
/// drawn (2026-09-25).
///
/// WHY. The map card is a plain Card, and a Card merges every child that is not
/// its own semantics node into the card's single label. Measured in this
/// suite's semantics tree on the tree before this file existed: the platform
/// permission sentence and both data-flow paragraphs were part of the card's
/// own label, 959 characters in Japanese and 2,089 in English, beginning with
/// the title 地図. A screen reader reaches a node's own label before its
/// children, so a driver using one heard where her coordinates go BEFORE the
/// drive sentences and the share button, which a sighted driver reads first.
/// The guards that existed measured on-screen position (getRect): the order
/// she SEES, not the order she HEARS.
///
/// WHAT A PASS MEANS. flutter_test's simulated traversal (depth-first, a node
/// before its children, siblings in geometric order) visits each paragraph as
/// its own stop, in the order the card draws it, and the card's own label no
/// longer carries any of them. It does NOT mean anyone has listened with a
/// screen reader on a device.
///
/// THE ORDER CHANGED 2026-09-25, on a screen review's ruling: status line,
/// then 現在地を共有 (with the withdraw button beside it), then the drive
/// sentences, then the rest. With the sentences above it the control sat below
/// her first screen at text size 1.3. So she now hears the control before the
/// drive sentences on the card; the consent dialog, which the control opens,
/// still reads them before either answer (the last test below).
///
/// The dialog is also named by its title now, rather than by 「通知」; that is
/// held by dialogs_named_by_their_titles_test.dart, which walks the whole
/// semantics tree. This file's simulated traversal does not visit the node
/// that names a route.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

String _label(SemanticsNode n) => n.getSemanticsData().label;

/// Index in [traversal] of the ONE node labelled exactly [words]. A paragraph
/// that is not its own stop has no such node, and that is the defect.
int _stop(List<SemanticsNode> traversal, String words, String what) {
  final at = <int>[
    for (var i = 0; i < traversal.length; i++)
      if (_label(traversal[i]) == words) i,
  ];
  expect(
    at,
    hasLength(1),
    reason:
        '$what must be exactly one stop of its own, labelled with its '
        'own words; found ${at.length}',
  );
  return at.single;
}

/// Asserts that the card's own label carries none of the PARAGRAPHS in
/// [order], and that every entry is its own stop, after the card, in the order
/// given.
///
/// Only paragraphs are checked against the card's label. A button is always a
/// node of its own, and its short words can occur inside a paragraph
/// (現在地を共有 opens 「現在地を共有すると…」), so checking a button's words
/// against a merged label would blame the button for the paragraph.
void _readInOrder(
  WidgetTester tester,
  AppL10n l,
  List<(String, String, {bool paragraph})> order,
) {
  final t = tester.semantics.simulatedAccessibilityTraversal().toList();
  final cards = <int>[
    for (var i = 0; i < t.length; i++)
      if (_label(t[i]) == l.mapSectionTitle ||
          _label(t[i]).startsWith('${l.mapSectionTitle}\n'))
        i,
  ];
  expect(cards, hasLength(1), reason: 'the map card node');
  final card = cards.single;
  final cardLabel = _label(t[card]);
  for (final (words, what, :paragraph) in order) {
    if (!paragraph) continue;
    expect(
      cardLabel.contains(words),
      isFalse,
      reason:
          '$what is read as part of the card itself, before anything '
          'the card draws above it (card label: ${cardLabel.length} '
          'characters)',
    );
  }
  var previous = card;
  var previousWhat = 'the card';
  for (final (words, what, paragraph: _) in order) {
    final at = _stop(t, words, what);
    expect(
      at,
      greaterThan(previous),
      reason: '$what must be heard after $previousWhat, as it is drawn',
    );
    previous = at;
    previousWhat = what;
  }
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_reading_order');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<StreamController<PositionFix>> boot(
    WidgetTester tester,
    String lang, {
    bool? consent,
  }) async {
    final positions = StreamController<PositionFix>.broadcast();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      SngnavApp(
        locale: Locale(lang),
        actuators: FakeAlertActuators(),
        clock: () => DateTime.utc(2026, 1, 14, 21),
        jmaFetch: () async => const JmaFailure('test: no observation'),
        positionSource: () => positions.stream,
        locationConsent: consent,
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return positions;
  }

  for (final lang in const ['ja', 'en']) {
    final l = AppL10n(Locale(lang));

    testWidgets('$lang, not shared: each paragraph is its own stop, heard '
        'where it is drawn', (tester) async {
      final semantics = tester.ensureSemantics();
      final positions = await boot(tester, lang);
      _readInOrder(tester, l, [
        (l.locationNotShared, 'the status line', paragraph: true),
        (l.shareMyLocation, 'the share button', paragraph: false),
        (l.driveDisclosure, 'the drive sentences', paragraph: true),
        (
          l.locationOsPermissionRoute,
          'the platform permission sentence',
          paragraph: true,
        ),
        (l.locationOpenOsSettings, 'the settings button', paragraph: false),
        (l.locationDisclosure, 'where her coordinates go', paragraph: true),
        (l.egressDisclosure, 'the other connections', paragraph: true),
      ]);
      await positions.close();
      semantics.dispose();
    });

    testWidgets('$lang, a remembered yes: the way back is heard beside the '
        'share button, and the paragraphs keep their places', (tester) async {
      final semantics = tester.ensureSemantics();
      final positions = await boot(tester, lang, consent: true);
      _readInOrder(tester, l, [
        (l.shareMyLocation, 'the share button', paragraph: false),
        (l.locationConsentWithdraw, 'the withdraw button', paragraph: false),
        (l.driveDisclosure, 'the drive sentences', paragraph: true),
        (
          l.locationOsPermissionRoute,
          'the platform permission sentence',
          paragraph: true,
        ),
        (l.locationDisclosure, 'where her coordinates go', paragraph: true),
        (l.egressDisclosure, 'the other connections', paragraph: true),
      ]);
      await positions.close();
      semantics.dispose();
    });

    testWidgets('$lang, after withdrawing: the note that says so is heard '
        'where it appears, not as part of the card', (tester) async {
      final semantics = tester.ensureSemantics();
      final positions = await boot(tester, lang, consent: true);
      final w = find.byKey(const Key('location-consent-withdraw'));
      await tester.ensureVisible(w);
      await tester.pump();
      await tester.tap(w);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const Key('location-consent-withdrawn-note')),
        findsOneWidget,
        reason: 'precondition: the withdrawal is said on the card',
      );
      _readInOrder(tester, l, [
        (l.shareMyLocation, 'the share button', paragraph: false),
        (
          l.locationConsentWithdrawnNote,
          'the withdrawal note',
          paragraph: true,
        ),
        // The note is under the control whose effect it reports, above the
        // drive sentences.
        (l.driveDisclosure, 'the drive sentences', paragraph: true),
        (
          l.locationOsPermissionRoute,
          'the platform permission sentence',
          paragraph: true,
        ),
        (l.locationDisclosure, 'where her coordinates go', paragraph: true),
        (l.egressDisclosure, 'the other connections', paragraph: true),
      ]);
      await positions.close();
      semantics.dispose();
    });

    // The dialog was already right, and this holds it so: AlertDialog gives
    // its content explicit child nodes. Measured here, with nothing from the
    // page beneath it in the traversal.
    testWidgets('$lang, the consent dialog: title, the drive sentences, where '
        'her coordinates go, then the two answers', (tester) async {
      final semantics = tester.ensureSemantics();
      final positions = await boot(tester, lang);
      final b = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(b);
      await tester.pump();
      await tester.tap(b);
      // The act reads a persisted answer first, under a 2 s hang-bound.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        find.byKey(const Key('location-consent-accept')),
        findsOneWidget,
        reason: 'precondition: the dialog is open',
      );
      final t = tester.semantics.simulatedAccessibilityTraversal().toList();
      var previous = -1;
      var previousWhat = 'nothing';
      for (final (words, what) in [
        (l.locationConsentTitle, 'the title'),
        (l.driveDisclosure, 'the drive sentences'),
        (l.locationDisclosure, 'where her coordinates go'),
        (l.locationConsentDecline, 'the decline button'),
        (l.locationConsentAccept, 'the agree button'),
      ]) {
        final at = _stop(t, words, what);
        expect(
          at,
          greaterThan(previous),
          reason: '$what must be heard after $previousWhat',
        );
        previous = at;
        previousWhat = what;
      }
      expect(
        t.where((n) => _label(n) == l.shareMyLocation),
        isEmpty,
        reason: 'the page beneath the dialog is not in its reading order',
      );
      await positions.close();
      semantics.dispose();
    });
  }
}
