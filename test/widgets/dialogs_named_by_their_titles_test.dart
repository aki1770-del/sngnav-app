/// Each of the app's three AlertDialogs is announced by its own title, never
/// by the framework's word for any alert; and in both consent dialogs the two
/// answers are the same widget with the same weight.
///
/// WHY, written before the act (AAE, R122 round 5a).
///
/// (1) The spoken name. With no label, Flutter names an AlertDialog with
/// MaterialLocalizations.alertDialogLabel on Android, and in Japanese that is
/// 「通知」 (material_ja.arb:44, applied at material/dialog.dart:784). A screen
/// review heard TalkBack open the location consent by saying 「通知」 on an
/// Android 14 emulator. In this app 通知 is the drive notification, and in a
/// hazard app a dialog announced as 通知 can be heard as an incoming warning.
/// A dignity review found the same unlabelled shape in the route consent and
/// the diary dialogs, and ruled each is named by its own title.
///
/// (2) The two answers. 同意して共有する was a filled button and 共有しない bare
/// text, in the location consent and the route consent alike. At large text
/// the pair stacks and only the machine's preferred answer had a shape.
/// Declining costs her nothing, so it must not look like less of an answer
/// (Vision 24: the machine yields to the person).
///
/// WHAT A PASS MEANS. In the test semantics tree, the node that names the
/// dialog's route carries the dialog's title, and no node carries the alert
/// word. The two answers are the same widget type and paint the same
/// Material: colour, elevation and shape. It does NOT mean anyone has heard
/// TalkBack say the title, or looked at the buttons on a device.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_diary.dart';

import '../support/fake_alert_actuators.dart';

/// Every label in the semantics tree, with whether its node names a route.
/// The whole tree, not the simulated traversal: the traversal does not visit
/// the node that names a route.
List<(String, bool)> _labels(WidgetTester tester) => [
      for (final SemanticsNode n
          in find.semantics.byPredicate((_) => true).evaluate())
        (n.getSemanticsData().label,
            n.getSemanticsData().flagsCollection.namesRoute),
    ];

void _namedByTitle(WidgetTester tester, String title, String lang) {
  final labels = _labels(tester);
  final routeNames = [
    for (final (label, names) in labels)
      if (names) label,
  ];
  expect(routeNames, contains(title),
      reason: 'the dialog is announced by its title "$title"; the route '
          'names found: $routeNames');
  final alertWord = lang == 'ja' ? '通知' : 'Alert';
  expect(labels.where((e) => e.$1 == alertWord), isEmpty,
      reason: 'no node is labelled with the framework\'s word for any alert '
          '("$alertWord"); in this app 通知 is the drive notification');
}

/// The two answers are the same widget type and paint the same Material.
void _sameWeight(WidgetTester tester, Key decline, Key accept) {
  final d = tester.widget(find.byKey(decline));
  final a = tester.widget(find.byKey(accept));
  expect(d.runtimeType, a.runtimeType,
      reason: 'both answers are the same widget: $d / $a');
  Material m(Key k) => tester.widget<Material>(
      find.descendant(of: find.byKey(k), matching: find.byType(Material)).first);
  final md = m(decline);
  final ma = m(accept);
  expect(md.color, ma.color, reason: 'the same fill');
  expect(md.elevation, ma.elevation, reason: 'the same elevation');
  expect(md.shape, ma.shape, reason: 'the same outline and shape');
  expect(md.textStyle?.fontWeight, ma.textStyle?.fontWeight,
      reason: 'the same weight of words');
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_dialog_names');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  for (final lang in const ['ja', 'en']) {
    final l = AppL10n(Locale(lang));

    testWidgets('$lang: the location consent is named by its title, and its '
        'two answers weigh the same', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(SngnavApp(
        locale: Locale(lang),
        actuators: FakeAlertActuators(),
        clock: () => DateTime.utc(2026, 1, 14, 21),
        jmaFetch: () async => const JmaFailure('test: no observation'),
      ));
      await tester.pump();
      final b = find.byKey(const Key('share-location-button'));
      await tester.ensureVisible(b);
      await tester.pump();
      await tester.tap(b);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('location-consent-accept')), findsOneWidget,
          reason: 'control: the dialog is open');

      _namedByTitle(tester, l.locationConsentTitle, lang);
      _sameWeight(tester, const Key('location-consent-decline'),
          const Key('location-consent-accept'));
      semantics.dispose();
    });

    testWidgets('$lang: the route consent is named by its title, and its two '
        'answers weigh the same', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(SngnavApp(locale: Locale(lang)));
      await tester.pump();
      // The route act, as route_consent_gate_test.dart opens it: A, B, then
      // 「ルートを取得」, then the consent path's 2 s store bound.
      final open = find.byKey(const Key('route-act-open'));
      await tester.ensureVisible(open);
      await tester.pump();
      await tester.tap(open);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final actMap = find.descendant(
          of: find.byType(Dialog), matching: find.byType(AkitaMap));
      final rect = tester.getRect(actMap);
      for (final offset in const [Offset(-100, -40), Offset(100, 40)]) {
        await tester.tapAt(rect.center + offset);
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.tap(find.byKey(const Key('route-act-get-route')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('route-consent-accept')), findsOneWidget,
          reason: 'control: the route consent is open');

      _namedByTitle(tester, l.routeConsentTitle, lang);
      _sameWeight(tester, const Key('route-consent-decline'),
          const Key('route-consent-accept'));
      semantics.dispose();
    });

    testWidgets('$lang: the diary is named by its title', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(SngnavApp(
        locale: Locale(lang),
        diary: DriveDiary(file: File('${tmp.path}/drive_diary.txt')),
        diaryShareSink: (_) async {},
      ));
      await tester.pump();
      final w = find.byKey(const Key('diary-write-button'));
      await tester.ensureVisible(w);
      await tester.pump();
      await tester.tap(w);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diary-note-field')), findsOneWidget,
          reason: 'control: the diary is open');

      _namedByTitle(tester, l.diaryWriteButton, lang);
      semantics.dispose();
    });
  }
}
