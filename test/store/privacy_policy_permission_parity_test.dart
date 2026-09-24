// The page a Play reviewer reads, and the page SHE reads, checked against the
// manifest we ship.
//
// WHY THIS EXISTS, and it is not hygiene.
//
// On 2026-08-10 this app's published privacy policy listed FOUR permissions and
// said "no other permissions are requested", while the artifact requested FIVE:
// the `vibration` plugin injects VIBRATE at manifest-MERGE time. The page was
// false for a month, in our favour, which is the worst direction. Gate 5 of
// tool/preflight_play_upload.sh was built for that, and it closed half the hole:
// it compares the manifest we AUTHOR against the artifact we BUILD.
//
// It never opens the privacy policy. Its failure message says
// "docs/store/privacy_policy_ja.md ... are now WRONG", which is a message to a
// human, not a check. So when manifest and artifact AGREE and only the PAGE
// disagrees, nothing in this repository notices.
//
// That is exactly what happened on 2026-09-24. FOREGROUND_SERVICE and
// FOREGROUND_SERVICE_LOCATION returned to the manifest with a real service
// behind them. Manifest and artifact agreed at seven. The page still said five
// and still said "no other permissions are requested". Gate 5 would have passed.
//
// This test closes that side. It runs in `flutter test`, so it fires on every
// run rather than only at upload time -- the drift is authored months before the
// upload, and a gate that only speaks on upload day speaks after the page has
// been public.
//
// It reads the AUTHORED manifest, not the merged one, because that is the file
// a human edits and the only one present without a build. Gate 5 remains the
// instrument for merge-time injection (the VIBRATE class of defect); the two
// together cover author -> artifact -> page. Neither alone does.
//
// D4: this page is read by a Play reviewer and by a Japanese driver. Both are
// weavers. The ja table and the en table are BOTH checked, because a correct
// English table beside a stale Japanese one is exactly the asymmetry AAE-4
// forbids -- and Japanese is the language of the driver this app is for.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `uses-permission` names that are DIRECT children of `<manifest>`.
/// XML, not a regex: a commented-out declaration grants nothing, and a regex
/// cannot tell the difference. Same discipline, and the same reason, as
/// tool/preflight_play_upload.sh gate 5.
Set<String> _declaredInManifest(String xml) {
  final doc = XmlLite.parse(xml);
  return doc
      .where((e) => e.name == 'uses-permission')
      .map((e) => e.attributes['android:name'])
      .whereType<String>()
      .map((n) => n.replaceFirst('android.permission.', ''))
      .toSet();
}

/// Permission names in a markdown table whose rows begin `| NAME |`.
Set<String> _rowsIn(String section) => RegExp(r'^\|\s*([A-Z][A-Z_]+)\s*\|',
        multiLine: true)
    .allMatches(section)
    .map((m) => m.group(1)!)
    .toSet();

String _section(String page, String startHeading) {
  final i = page.indexOf(startHeading);
  expect(i, isNot(-1),
      reason: 'the heading "$startHeading" is gone from the privacy policy; '
          're-point this guard rather than deleting it');
  final j = page.indexOf('\n## ', i + startHeading.length);
  return page.substring(i, j == -1 ? page.length : j);
}

void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final page = File('docs/store/privacy_policy_ja.md').readAsStringSync();

  final declared = _declaredInManifest(manifest);

  group('the privacy policy tells the truth about what the app requests', () {
    test('the manifest is readable and declares something at all', () {
      expect(declared, isNotEmpty,
          reason: 'no permissions parsed from the authored manifest -- '
              'UNVERIFIED, not clear');
    });

    test('the JAPANESE table lists exactly what the manifest declares', () {
      final listed = _rowsIn(_section(page, '## アプリが要求する権限（Android）'));
      expect(listed, declared,
          reason: 'MISSING FROM THE PAGE: ${declared.difference(listed)}\n'
              'ON THE PAGE BUT NOT REQUESTED: ${listed.difference(declared)}\n'
              'The page says "これ以外の権限...は要求しません". If that sentence '
              'stands beside a short list, the page is false in our favour, '
              'which is the direction that costs the reader.');
    });

    test('the ENGLISH table lists exactly the same set', () {
      final listed = _rowsIn(_section(page, '## Permissions the app requests (Android)'));
      expect(listed, declared,
          reason: 'MISSING FROM THE PAGE: ${declared.difference(listed)}\n'
              'ON THE PAGE BUT NOT REQUESTED: ${listed.difference(declared)}');
    });

    test('the data-safety declaration names the same set', () {
      final ds = File('docs/store/data_safety_declaration.md').readAsStringSync();
      for (final p in declared) {
        expect(ds, contains(p),
            reason: 'the Data safety declaration does not mention $p. A Data '
                'safety form that contradicts the app is a Play POLICY '
                'violation, not a typo.');
      }
    });
  });
}

/// Minimal XML element reader: enough to find direct children of the root and
/// their attributes, with no dependency added to the app for a test.
class XmlLite {
  XmlLite(this.name, this.attributes);
  final String name;
  final Map<String, String> attributes;

  static List<XmlLite> parse(String xml) {
    // Strip comments first: a commented-out <uses-permission> grants nothing.
    final body = xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final out = <XmlLite>[];
    for (final m in RegExp(r'<([a-zA-Z-]+)([^>]*?)/?>').allMatches(body)) {
      final attrs = <String, String>{};
      for (final a
          in RegExp(r'([\w:.-]+)\s*=\s*"([^"]*)"').allMatches(m.group(2)!)) {
        attrs[a.group(1)!] = a.group(2)!;
      }
      out.add(XmlLite(m.group(1)!, attrs));
    }
    return out;
  }
}
