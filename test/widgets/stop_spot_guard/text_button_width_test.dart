/// The widths ShareStartRow computes for 停止, 閉じる and the withdrawal are
/// the widths real TextButtons take, in the app's own theme, at both languages
/// and every text size the stop-spot guard covers (code 16, 2026-10-14).
///
/// WHY. ShareStartRow keeps 現在地を共有 clear of the column where 停止 or
/// 閉じる will be drawn, and it knows that column's width by computing it,
/// never by drawing a hidden button (a hidden 停止 in the element tree was
/// found by offstage finders and read as a running share). A computed width
/// that drifts from the real button's would move the reserved column without
/// a word. This pins the computation to the real thing.
///
/// WHAT A PASS MEANS. For every label and size, the computed width equals the
/// laid-out width of `TextButton(onPressed: …, child: Text(label))` to within
/// 0.01 dp, with the same face the guard loads. Not a device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/app_theme.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/widgets/share_start_row.dart';

import '../../render_see/render_see_env.dart';
import '../../support/d8_stop_spot_guard.dart' show kD8Scales;

void main() {
  for (final lang in const ['ja', 'en']) {
    testWidgets('$lang: computed TextButton widths equal real ones at every '
        'covered text size', (tester) async {
      final loaded = await tester.runAsync(() => loadDiscoveredFace('Roboto',
              lang == 'ja' ? FaceSearch.japanese : FaceSearch.roboto)) ??
          false;
      expect(loaded, isTrue, reason: 'a real face, as the guard loads');
      tester.view.devicePixelRatio = 2.75;
      tester.view.physicalSize = const Size(1080, 2340);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final l = AppL10n(Locale(lang));
      final labels = [
        l.stop,
        l.close,
        l.locationConsentWithdraw,
        l.shareMyLocation,
      ];
      var checked = 0;
      for (final scale in kD8Scales) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        final computed = <String, double>{};
        await tester.pumpWidget(MaterialApp(
          theme: sngnavTheme(),
          locale: Locale(lang),
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ja'), Locale('en')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final label in labels)
                    TextButton(
                      key: ValueKey('real $label'),
                      onPressed: () {},
                      child: Text(label),
                    ),
                  Builder(builder: (context) {
                    for (final label in labels) {
                      computed[label] = textButtonNaturalWidth(context, label);
                    }
                    return const SizedBox.shrink();
                  }),
                ],
              ),
            ),
          ),
        ));
        await tester.pump();
        for (final label in labels) {
          final real = tester.getSize(find.byKey(ValueKey('real $label'))).width;
          expect(computed[label], closeTo(real, 0.01),
              reason: '$lang x$scale "$label": computed ${computed[label]} dp, '
                  'real $real dp');
          checked++;
        }
      }
      expect(checked, kD8Scales.length * labels.length,
          reason: 'control: every label at every size was compared');
    });
  }
}
