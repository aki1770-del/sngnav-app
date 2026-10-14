/// The build that writes into code 16's record in tests (2026-10-14).
///
/// Production names the writer from the installed package
/// ([BuildIdentity.fromPlatform]). A test names one explicitly, with values
/// no constant in lib/ carries, so a writer that substituted a literal for
/// the platform's answer could not pass by luck.
library;

import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';

/// versionCode 16, commit c0de16a, APK hash beginning 16a1b2c3d4e5.
const String kTestGitSha = 'c0de16a';
final String kTestSelfSha256 = '16a1b2c3d4e5${'0' * 52}';

final RecordWriter kTestRecordWriter = RecordWriter(
    versionCode: 16, gitSha: kTestGitSha, selfSha256: kTestSelfSha256);

/// The boundary line [kTestRecordWriter] writes.
const String kTestBoundaryLine =
    's=0 t=0 k=build vc=16 sha=c0de16a apk=16a1b2c3d4e5 launch=engine';

/// The identity [openCode15FixIntervalRecord] reads in a test.
Future<BuildIdentity> testBuildIdentity() async => BuildIdentity(
      versionName: '0.0.2',
      versionCode: 16,
      packageName: 'dev.aki1770del.sngnav_app',
      selfSha256: kTestSelfSha256,
      gitSha: kTestGitSha,
      artifactCount: 1,
    );
