// The SURFACE gates. WDA's Item 1 is a list of things that must NEVER happen,
// and a rule nothing checks is not a rule -- so each is asserted here against
// the real widget, not described in a comment.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/update_check.dart';
import 'package:sngnav_app/services/update_manifest.dart';
import 'package:sngnav_app/widgets/update_notice.dart';

const kPkg = 'dev.aki1770del.sngnav_app';

final entry = UpdateManifestEntry(
  versionCode: 11,
  versionName: '0.0.2',
  artifactUrl: Uri.parse('https://example.test/app-11.apk'),
  package: kPkg,
  sha256: 'fd2cdf4b615b275bdfbe1902ee8249473e603f83b8325def2552020f85038937',
  sizeBytes: 94671699,
  signerSha256:
      '6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14',
);

const runningId = BuildIdentity(
  versionName: '0.0.2',
  versionCode: 10,
  packageName: kPkg,
  selfSha256:
      'ff988f09a7b1000000000000000000000000000000000000000000000000abcd',
  gitSha: '5794d0c-dirty',
);

UpdateCheckResult announceable() => UpdateCheckResult(
      status: UpdateCheckStatus.updateAvailable,
      running: runningId,
      available: entry,
      runningIsPublished: false,
    );

Widget host(Widget child, {Locale locale = const Locale('ja')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('it renders when a reachable newer build exists', (t) async {
    await t.pumpWidget(host(UpdateNoticeHarness(result: announceable())));
    await t.pumpAndSettle();
    expect(find.textContaining('0.0.2+11'), findsOneWidget);
  });

  testWidgets('WDA -- DRIVING renders NOTHING, not a smaller thing',
      (t) async {
    await t.pumpWidget(
      host(UpdateNoticeHarness(result: announceable(), driving: true)),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('0.0.2+11'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('WDA -- a DISMISSED versionCode never reappears', (t) async {
    await t.pumpWidget(host(
      UpdateNoticeHarness(result: announceable(), dismissedVersionCode: 11),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('0.0.2+11'), findsNothing);
  });

  testWidgets('dismissing 11 does NOT suppress a later 12', (t) async {
    await t.pumpWidget(host(
      UpdateNoticeHarness(result: announceable(), dismissedVersionCode: 10),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('0.0.2+11'), findsOneWidget);
  });

  testWidgets('a status short of updateAvailable renders NOTHING', (t) async {
    for (final s in [
      UpdateCheckStatus.upToDate,
      UpdateCheckStatus.noAnswer,
      UpdateCheckStatus.newerButUnreachable,
      UpdateCheckStatus.packageMismatch,
      UpdateCheckStatus.unknownSelf,
    ]) {
      await t.pumpWidget(host(UpdateNoticeHarness(
        result: UpdateCheckResult(
          status: s,
          running: runningId,
          available: entry,
        ),
      )));
      await t.pumpAndSettle();
      expect(find.textContaining('0.0.2+11'), findsNothing,
          reason: 'status $s must not announce');
    }
  });

  testWidgets('WDA -- it is NOT a dialog, sheet, snackbar or banner',
      (t) async {
    await t.pumpWidget(host(UpdateNoticeHarness(result: announceable())));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the bounds ride the announcement, in ja and en', (t) async {
    await t.pumpWidget(host(UpdateNoticeHarness(result: announceable())));
    await t.pumpAndSettle();
    expect(find.textContaining('存在する'), findsOneWidget);
    expect(find.textContaining('署名鍵'), findsOneWidget);
    expect(find.textContaining('ff988f09a7b1'), findsOneWidget);

    await t.pumpWidget(host(
      UpdateNoticeHarness(result: announceable()),
      locale: const Locale('en'),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('EXISTS'), findsOneWidget);
    expect(find.textContaining('signed with a different key'), findsOneWidget);
  });

  testWidgets('an UNIDENTIFIED build says so rather than showing a pair that '
      'names nothing', (t) async {
    await t.pumpWidget(host(UpdateNoticeHarness(
      result: UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        running: const BuildIdentity(
          versionName: '0.0.2',
          versionCode: 10,
          packageName: kPkg,
        ),
        available: entry,
      ),
    )));
    await t.pumpAndSettle();
    expect(find.textContaining('特定できません'), findsOneWidget);
  });

  test('egress disclosure NAMES the update check in BOTH locales -- the '
      'closed-list claim would otherwise be false (WDA Item 2)', () {
    const ja = AppL10n(Locale('ja'));
    const en = AppL10n(Locale('en'));
    expect(ja.egressDisclosure, contains('次の場合のみ'));
    expect(ja.egressDisclosure, contains('更新確認'));
    expect(ja.egressDisclosure, contains('raw.githubusercontent.com'));
    expect(en.egressDisclosure, contains('The only other times'));
    expect(en.egressDisclosure, contains('Update check'));
    expect(en.egressDisclosure, contains('raw.githubusercontent.com'));
  });
}


/// Harness: [UpdateNotice] with the gates defaulted, so each test states only
/// the gate it exercises. Lives in the TEST, never in lib/.
class UpdateNoticeHarness extends StatelessWidget {
  const UpdateNoticeHarness({
    super.key,
    required this.result,
    this.driving = false,
    this.dismissedVersionCode,
  });

  final UpdateCheckResult? result;
  final bool driving;
  final int? dismissedVersionCode;

  @override
  Widget build(BuildContext context) => UpdateNotice(
        result: result,
        driving: driving,
        dismissedVersionCode: dismissedVersionCode,
        onDismiss: () {},
      );
}
