/// On her map card a screen reader announces only the state's own words, once,
/// from a node of their own: never the whole card.
///
/// Why this test exists. Measured 2026-09-14 in the flutter_test semantics
/// tree: every live-region flag on the map card merged into the card's own
/// node, so the label announced was the whole card. With location not shared
/// that was 736 characters, both disclosures in full; with location off, 156
/// in Japanese. On Android the platform announces the label of the node that
/// holds the flag, so what she heard was the card, not the change.
///
/// The rules tested here, as decided 2026-09-14:
///
/// * The flag sits on a node of its own, labelled exactly the state's words,
///   which are already on screen: 位置情報オフ / No location access, 現在地不明 /
///   Position unknown (a share with no position 60 s after the subscription),
///   位置情報は共有されていません。 / Location is not being shared.
/// * The card's node never carries the flag.
/// * The line under the map is not announced.
///
/// The same whole-card merge was measured on three other cards that day: the
/// weather card's road-conditions line, the log-share card and the diary card.
/// They take the same one-line change, and are held here to the same rule.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:sngnav_app/her_position.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;

import '../support/fake_alert_actuators.dart';

var _clockNow = DateTime.utc(2026, 1, 14, 21);

/// The labels of every node, anywhere in the tree, that holds the live-region
/// flag.
List<String> _liveLabels(WidgetTester tester) {
  var node = tester.getSemantics(find.byType(Scaffold).first);
  while (node.parent != null) {
    node = node.parent!;
  }
  final out = <String>[];
  void visit(SemanticsNode n) {
    final data = n.getSemanticsData();
    if (data.flagsCollection.isLiveRegion) out.add(data.label);
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(node);
  return out;
}

String? _line(WidgetTester tester) {
  final f = find.byKey(const Key('her-status-line'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

Future<StreamController<PositionFix>> _boot(WidgetTester tester,
    {String lang = 'ja'}) async {
  _clockNow = DateTime.utc(2026, 1, 14, 21);
  final positions = StreamController<PositionFix>.broadcast();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
      // Not about the consent act; that is guarded in
      // test/widgets/location_consent_act_and_privacy_surface_test.dart.
      locationConsent: true,

    actuators: FakeAlertActuators(),
    locale: Locale(lang),
    clock: () => _clockNow,
    jmaFetch: () async => const JmaFailure('no network in this test'),
    positionSource: () => positions.stream,
  ));
  await tester.pump();
  await tester.pump();
  return positions;
}

Future<void> _share(WidgetTester tester) async {
  final b = find.byKey(const Key('share-location-button'));
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await tester.pump();
}

Future<void> _refuse(
    WidgetTester tester, StreamController<PositionFix> positions) async {
  final e = await tester.runAsync(() => herPositionStream(
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () async => LocationPermission.denied,
      ).first);
  positions.add(e!);
  await tester.pump();
  await tester.pump();
}

/// No live node reads a card: its title, or anything past its own words.
///
/// The map card's title is 地図 / Map since 2026-09-15 (was 'Map — Akita-shi
/// (station 32402)'). Live words contain 地図 on their own (「…地図は表示された
/// ままです。」), so the title is matched whole, or at the head of a merged read.
void _noCardAnnounced(List<String> live, String state) {
  final titles = [
    const AppL10n(Locale('ja')).mapSectionTitle,
    const AppL10n(Locale('en')).mapSectionTitle,
  ];
  for (final label in live) {
    for (final title in titles) {
      expect(label == title || label.startsWith('$title\n'), isFalse,
          reason: '$state: 「$label」');
    }
    expect(label, isNot(contains('\n')), reason: '$state: 「$label」');
  }
}

void main() {
  testWidgets('not shared: the consent line alone, in each locale',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (lang, words) in const [
      ('ja', '位置情報は共有されていません。'),
      ('en', 'Location is not being shared.'),
    ]) {
      final positions = await _boot(tester, lang: lang);
      final live = _liveLabels(tester);
      expect(live.where((l) => l == words), hasLength(1), reason: '$lang: $live');
      _noCardAnnounced(live, 'not shared $lang');
      await positions.close();
    }
    semantics.dispose();
  });

  testWidgets('location off: the words alone, and not the line under the map',
      (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (lang, words) in const [
      ('ja', '位置情報オフ'),
      ('en', 'No location access'),
    ]) {
      final positions = await _boot(tester, lang: lang);
      await _share(tester);
      await _refuse(tester, positions);
      final line = _line(tester)!;
      expect(line, startsWith(words), reason: 'precondition: refusal');
      final live = _liveLabels(tester);
      expect(live.where((l) => l == words), hasLength(1), reason: '$lang: $live');
      expect(live.where((l) => l.contains(line)), isEmpty,
          reason: 'the line is heard when she moves to it');
      _noCardAnnounced(live, 'location off $lang');
      await positions.close();
    }
    semantics.dispose();
  });

  testWidgets('no position 60 s after the share: 現在地不明 alone',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final positions = await _boot(tester);
    await _share(tester);
    for (var i = 0; i < 6; i++) {
      _clockNow = _clockNow.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 15));
    }
    await tester.pump();
    final line = _line(tester)!;
    expect(line, startsWith('現在地 不明'), reason: 'precondition: phase 2');
    final live = _liveLabels(tester);
    expect(live.where((l) => l == '現在地不明'), hasLength(1), reason: '$live');
    expect(live.where((l) => l.contains(line)), isEmpty);
    _noCardAnnounced(live, 'no position');
    await positions.close();
    semantics.dispose();
  });

  testWidgets('the other cards measured that day announce their own line only',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final positions = await _boot(tester);
    final live = _liveLabels(tester);
    for (final title in [
      // Was 'JMA AMeDAS — Akita-shi (station 32402)' until 2026-09-15.
      const AppL10n(Locale('ja')).akitaObservationSectionTitle,
      'フィードバック — ログを共有',
      '運転日記 — 走った後にひとこと',
    ]) {
      expect(live.where((l) => l.contains(title)), isEmpty,
          reason: '「$title」 card announced whole: $live');
    }
    _noCardAnnounced(live, 'at launch');
    await positions.close();
    semantics.dispose();
  });
}
