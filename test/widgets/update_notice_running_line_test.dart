// The running-build line on the update notice: what each part of it says
// must stay next to the part it is about.
//
// When the self-hash did not answer, the line adds a note about the version
// number: （この番号だけでは特定できません） / "this number alone does not
// name one build". The note used to follow the whole identity string, which
// was the version pair alone. Once the commit slot was always shown, the note
// followed the commit word instead, and read as an explanation of UNREADABLE.
// The note now follows the pair it was written about, and the commit slot
// comes after it. Nothing is dropped from the line.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/update_check.dart';
import 'package:sngnav_app/services/update_manifest.dart';
import 'package:sngnav_app/widgets/update_notice.dart';

const kPkg = 'dev.aki1770del.sngnav_app';
const kSelf =
    '6fe92aecaff5000000000000000000000000000000000000000000000000abcd';

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

BuildIdentity _running({String? selfSha, String? gitSha}) => BuildIdentity(
      versionName: '0.0.2',
      versionCode: 10,
      packageName: kPkg,
      selfSha256: selfSha,
      gitSha: gitSha,
    );

/// Pumps the real notice and returns its running-build line.
Future<String> _line(
  WidgetTester t,
  BuildIdentity running, {
  Locale locale = const Locale('ja'),
}) async {
  await t.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppL10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppL10n.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: UpdateNotice(
          result: UpdateCheckResult(
            status: UpdateCheckStatus.updateAvailable,
            running: running,
            available: _entry,
            runningIsPublished: false,
          ),
          driving: false,
          dismissedVersionCode: null,
          onDismiss: () {},
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  final prefix = locale.languageCode == 'ja' ? '現在のビルド' : 'Running build';
  final lines = t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .where((s) => s.startsWith(prefix))
      .toList();
  expect(lines, hasLength(1), reason: 'exactly one running-build line');
  return lines.single;
}

void main() {
  group('no self-hash: the note follows the version number it is about', () {
    testWidgets('no channel at all (ja)', (t) async {
      expect(
        await _line(t, _running()),
        '現在のビルド: 0.0.2 (10)（この番号だけでは特定できません） · UNREADABLE',
      );
    });

    testWidgets('no channel at all (en)', (t) async {
      expect(
        await _line(t, _running(), locale: const Locale('en')),
        'Running build: 0.0.2 (10) (UNIDENTIFIED — this number alone does '
        'not name one build) · UNREADABLE',
      );
    });

    for (final commit in ['4370561', 'UNKNOWN', 'UNREADABLE']) {
      testWidgets('a commit slot of $commit stays after the note', (t) async {
        expect(
          await _line(t, _running(gitSha: commit)),
          '現在のビルド: 0.0.2 (10)（この番号だけでは特定できません） · $commit',
        );
      });
    }
  });

  group('with a self-hash: the triple, and no note', () {
    for (final commit in ['4370561', 'UNKNOWN', 'UNREADABLE']) {
      testWidgets('commit slot $commit', (t) async {
        final line = await _line(t, _running(selfSha: kSelf, gitSha: commit));
        expect(line, '現在のビルド: 0.0.2 (10) · 6fe92aecaff5 · $commit');
        expect(line, isNot(contains('特定できません')));
      });
    }
  });
}
