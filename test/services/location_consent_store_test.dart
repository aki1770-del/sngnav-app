/// What the location consent store keeps, and which of it is honoured
/// (2026-09-25).
///
/// A yes is honoured only when it recorded the words of the current revision.
/// Everything else read from disk leaves her undecided, so her next tap asks:
/// a withdrawal, a yes written before revisions existed, a yes to another
/// revision, a yes whose words are missing, or a file that cannot be read.
/// Nothing on disk is ever a refusal. See lib/services/location_consent.dart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/location_consent.dart';

void main() {
  late Directory tmp;
  late File file;
  late LocationConsentStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sngnav_location_consent');
    file = File('${tmp.path}/${LocationConsentStore.fileName}');
    store = LocationConsentStore(file: file);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  const words = ['title', 'drive', 'body', 'decline', 'accept'];

  test('a yes records the revision, the language and the exact words', () async {
    await store.saveYes(
        revision: 7, locale: 'ja', words: words, variant: DrivePromise.keepsGoing);
    final raw = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(raw['schema'], 2);
    expect(raw['locationShareConsent'], isTrue);
    expect(raw['disclosureRevision'], 7);
    expect(raw['disclosureLocale'], 'ja');
    expect(raw['disclosureWords'], words);
    expect(DateTime.tryParse(raw['decidedAt'] as String), isNotNull);

    final r = (await store.load())!;
    expect(r.granted, isTrue);
    expect(r.revision, 7);
    expect(r.locale, 'ja');
    expect(r.words, words);
    expect(r.answers(7, shown: DrivePromise.keepsGoing), isTrue, reason: 'a yes to these words, now');
    expect(r.isYesToOtherWords(7), isFalse);
    expect(r.isYesToOtherRevision(7), isFalse);
  });

  test('a yes to another revision is not honoured, and is a yes to other '
      'words', () async {
    await store.saveYes(
        revision: 1, locale: 'en', words: words, variant: DrivePromise.keepsGoing);
    final r = (await store.load())!;
    expect(r.answers(2, shown: DrivePromise.keepsGoing), isFalse, reason: 'the words changed what sharing does');
    expect(r.isYesToOtherWords(2), isTrue, reason: 'so she is asked');
    expect(r.isYesToOtherRevision(2), isTrue,
        reason: 'the description changed, and the dialog says so');
    expect(r.answers(0, shown: DrivePromise.keepsGoing), isFalse, reason: 'nor to an earlier one');
  });

  test('a yes written before revisions existed (schema 1) is asked once more',
      () async {
    // Exactly what the store wrote until 2026-09-25.
    file.writeAsStringSync(json.encode({
      'schema': 1,
      'locationShareConsent': true,
      'decidedAt': '2026-09-24T00:00:00.000Z',
    }));
    final r = (await store.load())!;
    expect(r.granted, isTrue);
    expect(r.revision, isNull);
    expect(r.words, isNull);
    expect(r.answers(kLocationConsentRevision, shown: DrivePromise.keepsGoing), isFalse,
        reason: 'it answered words this build no longer shows, and the record '
            'cannot say which');
    expect(r.isYesToOtherWords(kLocationConsentRevision), isTrue);
    expect(r.isYesToOtherRevision(kLocationConsentRevision), isTrue,
        reason: 'the words changed since then, so the dialog says so');
  });

  test('a withdrawal is kept as a record and never read as a refusal to ask',
      () async {
    await store.saveYes(
        revision: 1, locale: 'ja', words: words, variant: DrivePromise.keepsGoing);
    await store.saveWithdrawal();
    final r = (await store.load())!;
    expect(r.granted, isFalse, reason: 'what she did is kept');
    expect(r.answers(1, shown: DrivePromise.keepsGoing), isFalse);
    expect(r.isYesToOtherWords(1), isFalse,
        reason: 'she withdrew; asking again needs no explanation');
    expect(r.isYesToOtherRevision(1), isFalse);
  });

  test('the withdrawal written until 2026-09-25 is read the same way', () async {
    // What _withdrawLocationConsent wrote before this change. On the next
    // launch it used to be read back as her answer, and the share button did
    // nothing at all.
    file.writeAsStringSync(json.encode({
      'schema': 1,
      'locationShareConsent': false,
      'decidedAt': '2026-09-24T00:00:00.000Z',
    }));
    final r = (await store.load())!;
    expect(r.granted, isFalse);
    expect(r.answers(kLocationConsentRevision, shown: DrivePromise.keepsGoing), isFalse);
  });

  test('a yes that names the current revision but carries no words is not '
      'honoured', () async {
    file.writeAsStringSync(json.encode({
      'schema': 2,
      'locationShareConsent': true,
      'disclosureRevision': kLocationConsentRevision,
    }));
    final r = (await store.load())!;
    expect(r.answers(kLocationConsentRevision, shown: DrivePromise.keepsGoing), isFalse,
        reason: 'a yes that cannot say which words it answered is not one');
    // 2026-09-25, a dignity review: this record is DAMAGED, not changed.
    // Until then the dialog's "this description has changed" line was chosen
    // by isYesToOtherWords, which is true here, so she would have been told
    // the words changed when they had not.
    expect(r.isYesToOtherWords(kLocationConsentRevision), isTrue,
        reason: 'she is asked');
    expect(r.isYesToOtherRevision(kLocationConsentRevision), isFalse,
        reason: 'and not told the description changed: it did not');
  });

  test('absent, unreadable or malformed is "not decided", never a grant or a '
      'refusal', () async {
    expect(await store.load(), isNull, reason: 'absent');
    file.writeAsStringSync('{not json');
    expect(await store.load(), isNull, reason: 'malformed');
    file.writeAsStringSync('[true]');
    expect(await store.load(), isNull, reason: 'not an object');
    file.writeAsStringSync(json.encode({'locationShareConsent': 'yes'}));
    expect(await store.load(), isNull, reason: 'not a bool');
    file.writeAsStringSync(json.encode({
      'locationShareConsent': true,
      'disclosureRevision': '1',
      'disclosureWords': [1, 2],
    }));
    final r = (await store.load())!;
    expect(r.revision, isNull, reason: 'a revision that is not a number');
    expect(r.words, isNull, reason: 'words that are not strings');
    expect(r.answers(1, shown: DrivePromise.keepsGoing), isFalse);
  });

  // 2026-10-06, a dignity review: a yes covers only the variants its own words
  // cover, and the record says which variant she answered.
  group('a yes covers by the variant it answered', () {
    const all = DrivePromise.values;
    test('the coverage table, every pair', () {
      const covered = {
        DrivePromise.ifNotificationsAllowed: {
          DrivePromise.keepsGoing,
          DrivePromise.ifNotificationsAllowed,
          DrivePromise.onScreenOnly,
        },
        DrivePromise.keepsGoing: {
          DrivePromise.keepsGoing,
          DrivePromise.onScreenOnly,
        },
        DrivePromise.onScreenOnly: {DrivePromise.onScreenOnly},
      };
      for (final answered in all) {
        for (final shown in all) {
          expect(answered.covers(shown), covered[answered]!.contains(shown),
              reason: 'a yes to $answered, a dialog showing $shown');
        }
      }
    });

    LocationConsentRecord yes(DrivePromise? variant, {bool unreadable = false}) =>
        LocationConsentRecord(
          granted: true,
          revision: 1,
          locale: 'ja',
          words: const ['t', 'd', 'b', 'n', 'y'],
          variant: variant,
          variantUnreadable: unreadable,
        );

    test('a yes stored before variants existed reads as the can-post words', () {
      final r = yes(null);
      expect(r.answeredVariant, DrivePromise.keepsGoing);
      expect(r.answers(1, shown: DrivePromise.keepsGoing), isTrue);
      expect(r.answers(1, shown: DrivePromise.onScreenOnly), isTrue);
      expect(r.answers(1, shown: DrivePromise.ifNotificationsAllowed), isFalse);
    });

    test('a yes to the cannot-post words holds, and answers only its own', () {
      final r = yes(DrivePromise.onScreenOnly);
      expect(r.holdsYes(1), isTrue, reason: 'she did agree');
      expect(r.answers(1, shown: DrivePromise.onScreenOnly), isTrue);
      expect(r.answers(1, shown: DrivePromise.keepsGoing), isFalse,
          reason: 'more of her location running than she read');
      expect(r.answers(1, shown: DrivePromise.ifNotificationsAllowed), isFalse);
    });

    test('a record naming a variant this build cannot read covers nothing', () {
      final r = yes(null, unreadable: true);
      expect(r.holdsYes(1), isFalse);
      for (final shown in all) {
        expect(r.answers(1, shown: shown), isFalse);
      }
    });

    test('the store writes the variant and reads it back', () async {
      final dir = Directory.systemTemp.createTempSync('sngnav_variant');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = LocationConsentStore(file: File('${dir.path}/c.json'));
      for (final v in all) {
        await store.saveYes(
            revision: 1, locale: 'ja', words: const ['a'], variant: v);
        final raw = json.decode(File('${dir.path}/c.json').readAsStringSync())
            as Map<String, dynamic>;
        expect(raw['disclosureVariant'], v.recordName);
        expect((await store.load())!.variant, v);
      }
      File('${dir.path}/c.json').writeAsStringSync(json.encode({
        'schema': 2,
        'locationShareConsent': true,
        'disclosureRevision': 1,
        'disclosureLocale': 'ja',
        'disclosureWords': ['a'],
        'disclosureVariant': 'somethingElse',
      }));
      final odd = (await store.load())!;
      expect(odd.variantUnreadable, isTrue);
      expect(odd.holdsYes(1), isFalse);
    });
  });
}
