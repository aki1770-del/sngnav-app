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
    await store.saveYes(revision: 7, locale: 'ja', words: words);
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
    expect(r.answers(7), isTrue, reason: 'a yes to these words, now');
    expect(r.isYesToOtherWords(7), isFalse);
  });

  test('a yes to another revision is not honoured, and is a yes to other '
      'words', () async {
    await store.saveYes(revision: 1, locale: 'en', words: words);
    final r = (await store.load())!;
    expect(r.answers(2), isFalse, reason: 'the words changed what sharing does');
    expect(r.isYesToOtherWords(2), isTrue,
        reason: 'the dialog says why it asks again');
    expect(r.answers(0), isFalse, reason: 'nor to an earlier one');
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
    expect(r.answers(kLocationConsentRevision), isFalse,
        reason: 'it answered words this build no longer shows, and the record '
            'cannot say which');
    expect(r.isYesToOtherWords(kLocationConsentRevision), isTrue);
  });

  test('a withdrawal is kept as a record and never read as a refusal to ask',
      () async {
    await store.saveYes(revision: 1, locale: 'ja', words: words);
    await store.saveWithdrawal();
    final r = (await store.load())!;
    expect(r.granted, isFalse, reason: 'what she did is kept');
    expect(r.answers(1), isFalse);
    expect(r.isYesToOtherWords(1), isFalse,
        reason: 'she withdrew; asking again needs no explanation');
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
    expect(r.answers(kLocationConsentRevision), isFalse);
  });

  test('a yes that names the current revision but carries no words is not '
      'honoured', () async {
    file.writeAsStringSync(json.encode({
      'schema': 2,
      'locationShareConsent': true,
      'disclosureRevision': kLocationConsentRevision,
    }));
    final r = (await store.load())!;
    expect(r.answers(kLocationConsentRevision), isFalse,
        reason: 'a yes that cannot say which words it answered is not one');
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
    expect(r.answers(1), isFalse);
  });
}
