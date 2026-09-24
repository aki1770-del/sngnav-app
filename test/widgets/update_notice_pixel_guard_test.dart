// PIXEL-SAMPLING guard for lib/widgets/update_notice.dart.
//
// WHY, written before the act (OPS-070(B)). The HIE glance-paint register
// (test/widgets/glance_paint_coverage_test.dart) fired on this file the moment
// it was written: 4 paint positions, no guard. It was right to. This is the
// guard, and it reads the RASTER BACK -- `toImage` + `toByteData` -- because
// that register's founding defect was a guard that read the declared style
// (#616161) while the painted pixel was #A1A3A4.
//
// WHAT IT MEASURES AND WHAT IT DOES NOT. It measures THE GATE, in ink: when a
// gate is closed this surface must paint NOTHING -- not a smaller thing, not a
// faint thing, nothing -- which is the exact form of WDA's Item 1 refusal, and
// it is AAE's to hold because it is the wiring. It does NOT measure legibility:
// contrast, size and whether HER eyes can take it in are HIE's (AAE-6
// correction, 2026-09-13: this seat does not certify its own surface as
// legible). Coverage is not a pass.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/update_check.dart';
import 'package:sngnav_app/services/update_manifest.dart';
import 'package:sngnav_app/widgets/update_notice.dart';

const kPkg = 'dev.aki1770del.sngnav_app';

final _entry = UpdateManifestEntry(
  versionCode: 11,
  versionName: '0.0.2',
  artifactUrl: Uri.parse('https://example.test/app-11.apk'),
  package: kPkg,
  sha256: 'fd2cdf4b615b275bdfbe1902ee8249473e603f83b8325def2552020f85038937',
  sizeBytes: 94671699,
  signerSha256:
      '6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14',
);

const _running = BuildIdentity(
  versionName: '0.0.2',
  versionCode: 10,
  packageName: kPkg,
  selfSha256:
      '6fe92aecaff5000000000000000000000000000000000000000000000000abcd',
  gitSha: '5794d0c-dirty',
);

UpdateCheckResult _announceable() => UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      running: _running,
      available: _entry,
      runningIsPublished: false,
    );

const Key _shot = Key('update-notice-shot');

Widget _host({required bool driving, int? dismissed}) => MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: RepaintBoundary(
          key: _shot,
          child: SizedBox(
            width: 400,
            height: 400,
            child: SingleChildScrollView(
              child: UpdateNotice(
                result: _announceable(),
                driving: driving,
                dismissedVersionCode: dismissed,
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );

/// Reads the raster back and counts pixels that differ from the white
/// background. This is INK, not style.
/// Reads the raster back and counts pixels that differ from the white
/// background. This is INK, not style. Follows the house pattern of
/// `advisory_card_contrast_floor_test.dart:235-243` -- `renderObject` by key,
/// `pixelRatio: 1.0`, and the bytes carried OUT of `runAsync`, because
/// `toImage` awaited inside the fake-async zone never completes.
Future<int> _inkPixels(WidgetTester tester) async {
  final raw = await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final img = await b.toImage(pixelRatio: 1.0);
    final d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final out = d!.buffer.asUint8List();
    img.dispose();
    return out;
  });
  final bytes = raw!;
  var ink = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2], a = bytes[i + 3];
    if (a == 0) continue;
    if (r < 245 || g < 245 || b < 245) ink++;
  }
  return ink;
}

void main() {
  testWidgets('ANNOUNCING state paints ink', (tester) async {
    await tester.pumpWidget(_host(driving: false));
    await tester.pumpAndSettle();
    final ink = await _inkPixels(tester);
    expect(ink, greaterThan(500),
        reason: 'the notice is supposed to be visible here; $ink ink pixels '
            'is not a surface anyone can see');
  });

  testWidgets('DRIVING paints ZERO ink — WDA Item 1, measured in pixels',
      (tester) async {
    await tester.pumpWidget(_host(driving: true));
    await tester.pumpAndSettle();
    expect(await _inkPixels(tester), 0,
        reason: 'while she is driving this surface must paint NOTHING, not a '
            'smaller or fainter thing');
  });

  testWidgets('DISMISSED paints ZERO ink', (tester) async {
    await tester.pumpWidget(_host(driving: false, dismissed: 11));
    await tester.pumpAndSettle();
    expect(await _inkPixels(tester), 0);
  });

  testWidgets('the guard can FAIL — the announcing and gated states are not '
      'the same raster (a guard that cannot tell them apart proves nothing)',
      (tester) async {
    await tester.pumpWidget(_host(driving: false));
    await tester.pumpAndSettle();
    final shown = await _inkPixels(tester);
    await tester.pumpWidget(_host(driving: true));
    await tester.pumpAndSettle();
    final hidden = await _inkPixels(tester);
    expect(shown, isNot(hidden));
    expect(hidden, lessThan(shown));
  });
}
