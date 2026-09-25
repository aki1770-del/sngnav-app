/// What the policy says the User-Agent carries is what the requests send
/// (2026-09-25).
///
/// WHY. The policy said the weather requests carry a User-Agent containing
/// "this app's public repository URL". The constant the requests send names
/// https://github.com/aki1770-del/sngnav, the project's repository, while the
/// page's own contact line names .../sngnav-app. It is a contact address, not
/// an identifier, so no harm reached her; but a page that names one thing
/// while the wire carries another is the drift a disclosure cannot afford, and
/// nothing compared the two. This does, in both halves of the page.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/main.dart' show kSngnavAppUserAgent;

void main() {
  test('every repository address the policy puts in the User-Agent is the one '
      'the requests send', () {
    final policy = File('docs/store/privacy_policy_ja.md').readAsStringSync();
    final url = RegExp(r'https://github\.com/[A-Za-z0-9_.\-/]+');
    final uaLines = policy
        .split('\n')
        .where((l) => l.contains('User-Agent') && !l.trimLeft().startsWith('<!--'))
        .toList();
    // Flow 1 in each half states what the User-Agent carries.
    final stating = uaLines.where((l) => url.hasMatch(l)).toList();
    expect(stating, hasLength(2),
        reason: 'flow 1 in the Japanese half and in the English half each '
            'name the address the User-Agent carries; found ${stating.length} '
            'lines: $uaLines');
    // Exact addresses, not substrings: .../sngnav is a prefix of
    // .../sngnav-app, and a substring check passed when the constant was
    // changed to the other one.
    String clean(String a) => a.replaceFirst(RegExp(r'[).,]+$'), '');
    final sent =
        url.allMatches(kSngnavAppUserAgent).map((m) => clean(m.group(0)!)).toSet();
    expect(sent, hasLength(1), reason: 'the User-Agent names one address');
    for (final line in stating) {
      for (final m in url.allMatches(line)) {
        final address = clean(m.group(0)!);
        expect(sent, contains(address),
            reason: 'the policy says the User-Agent carries $address; the '
                'requests send $kSngnavAppUserAgent');
      }
      expect(line, contains('sngnav-app'),
          reason: 'the app name it carries is named too');
    }
    expect(kSngnavAppUserAgent, contains('sngnav-app'));
  });
}
