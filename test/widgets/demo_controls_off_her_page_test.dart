/// The controls built to demonstrate the live-drive card are not on her page,
/// and nothing she can reach from her page changes her card under a measured
/// whiteout.
///
/// Why, written before the act (2026-09-15). On b0f74e7 three demo controls
/// sat on her page with no release condition: the Akita mock position beside
/// 現在地を共有, the visibility band over the live-drive card, and the GPS
/// blackout simulator. Under a measured 80 m, one tap on the band's クリア
/// took the rung, its cause and the announce line off her card. They move to
/// the development page, which a release build never offers.
///
/// A release-shaped build here is `SngnavApp(developerPageEntry: false)`:
/// under test kReleaseMode is false, so this is the build that does not ask
/// for the development page, which is what every release build is.
///
/// The second test taps every enabled control her page draws, one per boot,
/// and chooses every item of every selector through the selector's own
/// callback, and reads her card after each. The third
/// is its control: the same reading sees the card change when the band is set
/// to clear, from the development page.
///
/// Bound: raw gestures on the map (pan, zoom) are not tapped; a map gesture
/// moves the camera, and the card reads no camera.
library;

import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show CautionReason, DriveAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/jma_fetch.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/main.dart' show SngnavApp;
import 'package:sngnav_app/services/drive_hud_localizer.dart';

import '../support/developer_page.dart';
import '../support/fake_alert_actuators.dart';
import '../support/rung_on_card.dart';

const _hud = DriveHudLocalizer();

final _t0 = DateTime.utc(2026, 1, 14, 21);

String _jstKey(DateTime utc) {
  final j = utc.add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${j.year}${two(j.month)}${two(j.day)}${two(j.hour)}${two(j.minute)}00';
}

Future<JmaResult> _measured80m() => _measured(80);

Future<JmaResult> _measured(int meters) async => JmaSuccess(JmaObservation(
      stationId: '32402',
      stationName: '秋田',
      temperatureCelsius: -3,
      humidityPercent: 90,
      windMetersPerSecond: 9,
      snowDepthCm: 40,
      precipitation10mMm: 1,
      visibilityMeters: meters,
      observedAtJstKey: _jstKey(_t0),
      fetchedAt: _t0,
    ));

Future<void> _boot(WidgetTester tester, String lang,
    {bool developerPageEntry = false, int visibility = 80}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(SngnavApp(
    key: UniqueKey(),
    locale: Locale(lang),
    actuators: FakeAlertActuators(),
    clock: () => _t0,
    jmaFetch: visibility == 80 ? _measured80m : () => _measured(visibility),
    developerPageEntry: developerPageEntry,
  ));
  await tester.pump();
  await tester.pump();
}

/// What her card tells her: the rung, whether its cause is on the card, and
/// the announce line.
String _card(WidgetTester tester, String lang) {
  final rung = rungOnCard();
  final cause = find
      .textContaining(_hud.reasonLabel(CautionReason.lowVisibility, lang))
      .evaluate()
      .isNotEmpty;
  final announce = find.byKey(const Key('drive-hud-announce-status'));
  final line = announce.evaluate().isEmpty
      ? '(none)'
      : tester.widget<Text>(announce).data;
  return 'rung ${rung?.name ?? 'none'} | cause $cause | announce $line';
}

/// Every enabled control drawn on the page on top, in tree order, with a label.
List<(String, Finder)> _controls(WidgetTester tester) {
  final out = <(String, Finder)>[];
  final all = find.byWidgetPredicate((w) =>
      (w is ButtonStyleButton && w.onPressed != null) ||
      (w is IconButton && w.onPressed != null) ||
      // Read through dynamic: DropdownButton<T>'s callback types are
      // covariant, and a DropdownButton<double?> read as DropdownButton<dynamic>
      // throws on the read.
      (w is DropdownButton && (w as dynamic).onChanged != null) ||
      (w is Switch && w.onChanged != null) ||
      (w is SwitchListTile && w.onChanged != null) ||
      (w is Checkbox && w.onChanged != null) ||
      (w is CheckboxListTile && w.onChanged != null) ||
      (w is PopupMenuButton && w.enabled) ||
      (w is InkWell && w.onTap != null));
  final elements = all.evaluate().toList();
  for (var i = 0; i < elements.length; i++) {
    final e = elements[i];
    // An InkWell inside another control is that control's own surface.
    if (e.widget is InkWell) {
      var inside = false;
      e.visitAncestorElements((a) {
        final w = a.widget;
        if (w is ButtonStyleButton ||
            w is IconButton ||
            w is DropdownButton ||
            w is SwitchListTile ||
            w is CheckboxListTile ||
            w is PopupMenuButton) {
          inside = true;
          return false;
        }
        return true;
      });
      if (inside) continue;
    }
    final texts = [
      for (final t in find
          .descendant(of: find.byElementPredicate((x) => x == e),
              matching: find.byType(Text))
          .evaluate())
        (t.widget as Text).data ?? '',
    ].where((s) => s.isNotEmpty).join(' / ');
    final key = e.widget.key;
    out.add((
      '${e.widget.runtimeType}${key == null ? '' : ' $key'} 「$texts」',
      find.byElementPredicate((x) => x == e),
    ));
  }
  return out;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _backToHerPage(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r.isFirst);
  await _settle(tester);
}

void main() {
  testWidgets('a release-shaped build draws none of the three demo controls '
      'on her page, in either language', (tester) async {
    for (final lang in const ['ja', 'en']) {
      final l = AppL10n(Locale(lang));
      await _boot(tester, lang);
      expect(find.byKey(kDeveloperPageEntryKey), findsNothing, reason: lang);
      final left = <String>[
        for (final k in const [
          'use-mock-button',
          'drive-hud-visibility-label',
          'drive-hud-visibility',
          'drive-hud-blackout-button',
          'drive-hud-blackout-seconds',
        ])
          if (find.byKey(Key(k), skipOffstage: false).evaluate().isNotEmpty) k,
        for (final t in [
          l.useAkitaMock,
          l.driveHudVisibilityOverrideLabel,
          l.driveHudSimulateBlackout,
          for (final m in const [null, 1500.0, 700.0, 300.0, 80.0])
            l.driveHudVisibilityBand(m),
        ])
          if (find.text(t, skipOffstage: false).evaluate().isNotEmpty) t,
        if (find
            .byWidgetPredicate((w) => w is DropdownButton<double?>,
                skipOffstage: false)
            .evaluate()
            .isNotEmpty)
          'a visibility selector',
      ];
      expect(left, isEmpty, reason: '$lang: still on her page: $left');
    }
  });

  testWidgets('under a measured whiteout, no control on her page changes what '
      'her card tells her', (tester) async {
    const lang = 'ja';
    await _boot(tester, lang);
    final before = _card(tester, lang);
    expect(before,
        'rung ${DriveAction.considerStopping.name} | cause true | announce '
        '${AppL10n(const Locale(lang)).driveHudAnnounceCritical}',
        reason: 'precondition: her card tells the measured whiteout');
    final labels = [for (final c in _controls(tester)) c.$1];
    expect(labels, isNotEmpty, reason: 'precondition: her page has controls');
    // ignore: avoid_print
    print('controls on her page (${labels.length}):\n  ${labels.join('\n  ')}');

    final changed = <String>[];
    for (var i = 0; i < labels.length; i++) {
      await _boot(tester, lang);
      final controls = _controls(tester);
      expect([for (final c in controls) c.$1], labels,
          reason: 'the same controls after a fresh boot');
      final (label, control) = controls[i];
      final dropdown = tester.widget(control) is DropdownButton;
      final items = dropdown
          ? ((tester.widget(control) as dynamic).items as List?)?.length ?? 0
          : 1;
      for (var item = 0; item < items; item++) {
        if (item > 0) {
          await _boot(tester, lang);
        }
        final c = _controls(tester)[i].$2;
        var picked = '';
        if (dropdown) {
          // A selector is exercised the way a choice reaches the app: its own
          // onChanged with each of its items' values, not through the menu's
          // layout.
          final w = tester.widget(c) as dynamic;
          final value = ((w.items as List)[item] as dynamic).value;
          picked = ' item $item (value $value)';
          (w.onChanged as Function)(value);
          await _settle(tester);
        } else {
          await tester.ensureVisible(c);
          await tester.pump();
          await tester.tap(c, warnIfMissed: false);
          await _settle(tester);
        }
        await _backToHerPage(tester);
        final after = _card(tester, lang);
        if (after != before) {
          changed.add('$label$picked: $after');
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 3));
    expect(changed, isEmpty,
        reason: 'before: $before\nchanged by a control on her page:\n  '
            '${changed.join('\n  ')}');
  });

  // Since 2026-09-16 a demo value may add caution and never take it away, so
  // under a measured whiteout no demo control changes her card at all. The
  // control reads a change a demo value may still make: under a measured
  // 700 m, with the mock position in force, the band set to 80 m raises her.
  testWidgets('control: the same reading sees her card change when the demo '
      'band is set to 80 m on the development page', (tester) async {
    const lang = 'ja';
    final l = AppL10n(const Locale(lang));
    await _boot(tester, lang, developerPageEntry: true, visibility: 700);
    await tapOnDeveloperPage(tester, const Key('use-mock-button'));
    await _settle(tester);
    final before = _card(tester, lang);
    await openDeveloperPage(tester);
    final band = find.byKey(const Key('drive-hud-visibility'));
    expect(band, findsOneWidget,
        reason: 'the band is on the development page');
    await tester.ensureVisible(band);
    await tester.pump();
    await tester.tap(band);
    await _settle(tester);
    await tester.tap(find.text(l.driveHudVisibilityBand(80)).last);
    await _settle(tester);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    expect(_card(tester, lang), isNot(before),
        reason: 'the reading sees a change made by a demo control');
  });
}
