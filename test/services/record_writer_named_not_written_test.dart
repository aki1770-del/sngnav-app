// T-D, the safety reader's test, added unedited (code 16, 2026-10-14).
//
// WHY. A record object that has not written since its naming kept the
// naming's decision whether a boundary is owed. That is the record stopped or
// full at its open, in a second process of this build. So it did not see the
// second page's delete, and wrote into the fresh file with no boundary: its
// lines read as code 15's (Sakichi Vision 14: a success-shaped read over a
// wrong attribution), or his whole file was refused (Vision 20).
//
// SOURCE. Lines 14-52 and 96-112 of the safety reader's
// outputs/functional-safety-engineer/code16_a_fix_bytes_read_2026_10_14/
// evidence/fse_proposed_record_test.dart (sha256 5a68c0ae...), byte for byte.
// Line 13, `import 'dart:async';`, is left out: only its T-A uses it, and
// T-A is already in record_build_boundary_test.dart. T-D and its helpers are
// not edited and not reformatted.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/code15_fix_interval_record.dart';

final BuildIdentity id16 = BuildIdentity(
    versionName: '0.0.2',
    versionCode: 16,
    packageName: 'dev.aki1770del.sngnav_app',
    selfSha256: 'aa11bb22cc33${'0' * 52}',
    gitSha: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
    artifactCount: 1);

const String code15LeftOpen = 's=0 t=0 k=launch\n'
    's=1 t=0 k=start a=- v=- late=- fg=1\n'
    's=1 t=5000 k=fine a=4.0 v=13.4 late=900 fg=1\n'
    's=1 t=10000 k=fine a=4.0 v=13.4 late=900 fg=1\n'
    's=1 t=500000 k=fine a=4.0 v=0 late=900 fg=0\n';

bool fine(Code15FixIntervalRecord r, int t) => r.record(
    share: 1,
    msSinceStreamStart: t,
    kind: FixEventKind.fine,
    accuracyMeters: 4.0,
    reportedSpeedMps: 13.4,
    lateMs: 120,
    appInFront: true);

List<String> linesOf(Code15FixIntervalRecord r) =>
    r.readAll().split('\n').where((l) => l.isNotEmpty).toList();

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fse_record_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  File recordFile() => File('${dir.path}/fix_interval_record_15.txt');
  // T-D (added 2026-10-14 on f36d663f): a writer that has not written since its naming still sees another writer's
  // delete. Second process of this build, record stopped at both opens; his delete on the second page; his resume on
  // the first. The fresh file's first line must be the boundary, or its lines are read as code 15's.
  test('T-D a writer that has not yet written sees another writer\'s delete', () async {
    recordFile().writeAsStringSync('${code15LeftOpen}s=0 t=0 k=build vc=16 sha=a1b2c3d apk=aa11bb22cc33 launch=engine\n'
        's=0 t=0 k=launch\n');
    File('${dir.path}/fix_interval_record_15.stopped').writeAsStringSync('stopped\n');
    final a = (await openCode15FixIntervalRecord(directory: dir, identity: () async => id16))!;
    await a.named;
    final b = (await openCode15FixIntervalRecord(directory: dir, identity: () async => id16))!;
    await b.named;
    b.deleteRecordOnHisTap(); // his delete, on the second page
    a.resume(); // his resume, on the first
    fine(a, 1000);
    expect(linesOf(a).first, 's=0 t=0 k=build vc=16 sha=a1b2c3d apk=aa11bb22cc33 launch=engine');
  });
}
