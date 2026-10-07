/// The consent dialog's words cannot change without a decision about what a
/// stored yes means (2026-09-25).
///
/// WHY. A stored yes is honoured only while it answered the current revision
/// ([kLocationConsentRevision]). If the words change what sharing does and the
/// revision stays, a stored yes is held to words she never read. If the
/// revision rises for a comma, everyone is asked again for nothing, and a
/// question asked for nothing teaches her to stop reading it. Only a person
/// can tell those apart, so this test makes the person decide: it fails
/// whenever the dialog's words differ from the words registered for the
/// current revision.
///
/// WHEN IT FAILS, decide in the same change:
///  - the new words describe what sharing does exactly as before: put the new
///    words in `test/fixtures/location_consent_dialog/rev<N>.json`;
///  - they describe something different: add `rev<N+1>.json` with the new
///    words and what sharing now does, and raise [kLocationConsentRevision]
///    to N+1.
///    Every stored yes to revision N is then asked once more, and told why.
/// Earlier files stay. They are how a stored revision is read back as the
/// words she agreed to.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/location_consent.dart';

const _dir = 'test/fixtures/location_consent_dialog';

Map<String, dynamic> _registered(int revision) =>
    json.decode(File('$_dir/rev$revision.json').readAsStringSync())
        as Map<String, dynamic>;

List<String> _dialogWords(String lang) {
  final d = AppL10n(Locale(lang)).locationConsentDialog;
  return [d.title, d.drive, d.body, d.decline, d.accept];
}

void main() {
  test('the dialog shows the words registered for the current revision', () {
    final reg = _registered(kLocationConsentRevision);
    for (final lang in const ['ja', 'en']) {
      expect(_dialogWords(lang), reg[lang],
          reason: 'THE CONSENT DIALOG\'S WORDS CHANGED ($lang). Decide what a '
              'stored yes means before this goes in. Same meaning: put the new '
              'words in $_dir/rev$kLocationConsentRevision.json. New meaning: '
              'add $_dir/rev${kLocationConsentRevision + 1}.json and raise '
              'kLocationConsentRevision, so every stored yes is asked once '
              'more.');
    }
  });

  test('every revision up to the current one is registered, and none beyond',
      () {
    for (var r = 1; r <= kLocationConsentRevision; r++) {
      final f = File('$_dir/rev$r.json');
      expect(f.existsSync(), isTrue,
          reason: 'revision $r must stay readable as the words it recorded');
      final reg = _registered(r);
      expect(reg['revision'], r);
      expect((reg['whatSharingDoes'] as String).trim(), isNotEmpty,
          reason: 'a revision names what sharing does; say it');
      for (final lang in const ['ja', 'en']) {
        expect(reg[lang], hasLength(5),
            reason: 'title, drive sentences, body, decline, accept');
      }
    }
    expect(File('$_dir/rev${kLocationConsentRevision + 1}.json').existsSync(),
        isFalse,
        reason: 'a registered revision the app does not ask for would never '
            'be asked');
  });

  // 2026-10-06, a dignity review: a revision may hold keyed variants of the
  // drive block. Each is registered with its own words and what sharing does,
  // and the coverage a yes to each carries is registered beside them.
  test('every drive-block variant shows the words registered for it', () {
    final reg = _registered(kLocationConsentRevision);
    final variants = reg['variants'] as Map<String, dynamic>;
    expect(variants.keys.toSet(),
        DrivePromise.values.map((v) => v.recordName).toSet(),
        reason: 'every variant the app can show is registered, and no other');
    for (final v in DrivePromise.values) {
      final r = variants[v.recordName] as Map<String, dynamic>;
      expect((r['whatSharingDoes'] as String).trim(), isNotEmpty,
          reason: 'a variant names what sharing does; say it');
      for (final lang in const ['ja', 'en']) {
        final d = AppL10n(Locale(lang)).locationConsentDialogFor(v);
        expect([d.title, d.drive, d.body, d.decline, d.accept], r[lang],
            reason: 'THE ${v.recordName} VARIANT\'S WORDS CHANGED ($lang). '
                'Decide what a stored yes to it means before this goes in.');
      }
    }
    expect(variants['canPost']['ja'], reg['ja'],
        reason: 'the can-post variant is the words revision 1 registered');
    final coverage = reg['variantsCoverage'] as Map<String, dynamic>;
    for (final a in DrivePromise.values) {
      for (final s in DrivePromise.values) {
        expect((coverage[a.recordName] as List).contains(s.recordName),
            a.covers(s),
            reason: 'the registered coverage and the code agree: a yes to '
                '${a.recordName}, a dialog showing ${s.recordName}');
      }
    }
  });
}
