/// Android backup: the error log and the fix-interval test records are kept
/// out, per file; the drive diary is kept IN.
///
/// Why, written before the act (2026-10-09). The app told every user the
/// error log has 「自動送信・テレメトリはなく」 and code 13's card told him the
/// record stays on the phone until he taps, while Android's default backup
/// (allowBackup unset, so true) could copy both to the user's Google account
/// and to a new phone. A sentence stating a guarantee the code does not hold
/// is a success-shaped value (Sakichi Vision 14). The diary is left IN on
/// purpose (the 2026-10-09 dignity read, WDA W4): excluding it would empty her
/// diary on a new phone to make our sentence true, so its words were
/// corrected instead.
///
/// What these hold, read from the source files themselves:
/// - the manifest names both rule files, and never sets allowBackup="false"
///   (that would take the diary out too) or a backupAgent;
/// - backup_rules.xml (Android 11 and lower) and BOTH sections of
///   data_extraction_rules.xml (Android 12 and later: cloud-backup and
///   device-transfer) exclude exactly the files the Dart code names, in the
///   domain those files are written to, and include nothing (so everything
///   else, the diary included, stays in);
/// - the files are where the domain says: the excluded ones in the
///   app-support directory (domain "file"), the diary in the documents
///   directory (under domain "root", which no rule touches).
///
/// HONEST BOUND. This reads the rule files as text. It proves the rules say
/// what the code needs; it cannot prove what a phone does with them. That is
/// the device check on API 29 and on one API of 31 or higher, which must also
/// see the diary PRESENT in the backup (a check that cannot see the diary has
/// not measured the exclusion). A phone maker's own backup is not covered by
/// either rule and is not checked here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/code13_record_cleanup.dart';
import 'package:sngnav_app/services/drive_diary.dart' show kDriveDiaryFileName;
import 'package:sngnav_app/services/error_log.dart' show kErrorLogFileName;
import 'package:sngnav_app/services/fix_interval_record_keeper.dart';

const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _legacy = 'android/app/src/main/res/xml/backup_rules.xml';
const _rules = 'android/app/src/main/res/xml/data_extraction_rules.xml';

String _noComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Every `<exclude .../>` and `<include .../>` in [xml], as (tag, domain, path).
List<(String, String?, String?)> _rulesIn(String xml) =>
    RegExp(r'<(exclude|include)\b([^>]*)/?>').allMatches(xml).map((m) {
      String? attr(String name) =>
          RegExp('$name="([^"]*)"').firstMatch(m.group(2)!)?.group(1);
      return (m.group(1)!, attr('domain'), attr('path'));
    }).toList();

String _section(String xml, String tag) {
  final m = RegExp('<$tag\\b[^>]*>(.*?)</$tag>', dotAll: true).firstMatch(xml);
  expect(m, isNotNull, reason: 'no <$tag> section in $_rules');
  return m!.group(1)!;
}

void main() {
  final excluded = <String>{
    kErrorLogFileName,
    ...kCode13RecordFileNames,
    ...kCode15RecordFileNames,
  };

  test('the manifest names both rule files and keeps allowBackup at its '
      'default', () {
    final m = _noComments(File(_manifest).readAsStringSync());
    final app = RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(m);
    expect(app, isNotNull);
    expect(
      app!.group(0),
      contains('android:fullBackupContent="@xml/backup_rules"'),
    );
    expect(
      app.group(0),
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(
      m,
      isNot(contains('android:allowBackup')),
      reason:
          'allowBackup="false" would take the diary out of backup too; '
          'the dignity read ruled per-file exclusion, never this flag',
    );
    expect(m, isNot(contains('android:backupAgent')));
  });

  test('Android 11 and lower: backup_rules.xml excludes exactly the log and '
      'the records, in domain "file", and includes nothing', () {
    final xml = _noComments(File(_legacy).readAsStringSync());
    expect(xml, contains('<full-backup-content>'));
    final rules = _rulesIn(xml);
    expect(
      rules.where((r) => r.$1 == 'include'),
      isEmpty,
      reason:
          'any include turns the scheme into "only what is included", '
          'which would drop the diary',
    );
    expect(rules.map((r) => r.$2).toSet(), {'file'});
    expect(rules.map((r) => r.$3).toSet(), excluded);
    expect(rules.length, excluded.length, reason: 'a duplicate rule');
  });

  for (final section in ['cloud-backup', 'device-transfer']) {
    test('Android 12 and later: <$section> excludes exactly the same files, '
        'in domain "file", and includes nothing', () {
      final xml = _noComments(File(_rules).readAsStringSync());
      expect(xml, contains('<data-extraction-rules>'));
      final body = _section(xml, section);
      final rules = _rulesIn(body);
      expect(rules.where((r) => r.$1 == 'include'), isEmpty);
      expect(rules.map((r) => r.$2).toSet(), {'file'});
      expect(rules.map((r) => r.$3).toSet(), excluded);
      expect(rules.length, excluded.length);
    });
  }

  test('the cloud-backup section does not make backup conditional on '
      'encryption (the diary\'s backup is unchanged)', () {
    final xml = _noComments(File(_rules).readAsStringSync());
    expect(xml, isNot(contains('disableIfNoEncryptionCapabilities')));
  });

  test('the diary is never excluded, by name or by domain', () {
    for (final path in [_legacy, _rules]) {
      final xml = _noComments(File(path).readAsStringSync());
      expect(xml, isNot(contains(kDriveDiaryFileName)));
      expect(xml, isNot(contains('domain="root"')));
      expect(xml, isNot(contains('app_flutter')));
    }
  });

  test('each file is written where its domain says', () {
    // domain="file" is Context.getFilesDir(): path_provider_android 2.3.1's
    // getApplicationSupportDirectory() (read in its source 2026-10-09).
    for (final path in [
      'lib/services/error_log.dart',
      'lib/services/code13_record_cleanup.dart',
      'lib/services/fix_interval_record_keeper.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(
        src,
        contains('getApplicationSupportDirectory()'),
        reason:
            '$path no longer writes under the app-support directory: '
            'the "file" domain rules would no longer reach it',
      );
      expect(src, isNot(contains('getApplicationDocumentsDirectory()')));
    }
    // The diary is under getDir("flutter"), in the data root: domain "root",
    // which no rule names, so it stays in backup and transfer.
    final diary = File('lib/services/drive_diary.dart').readAsStringSync();
    expect(diary, contains('getApplicationDocumentsDirectory()'));
  });
}
