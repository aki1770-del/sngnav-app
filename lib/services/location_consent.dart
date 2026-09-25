/// Persisted app-local consent for STARTING the location share.
///
/// WHY THIS EXISTS (2026-09-23). Until today this app had no affirmative
/// in-app consent act attached to the location disclosure at all. The share
/// control was a bare button: the next thing after her tap was the operating
/// system's own permission prompt, and the disclosure was prose sitting near
/// the button. Adjacency was doing work adjacency cannot do — a consent she is
/// presumed to have given because some text was once on the same screen is not
/// a consent she gave.
///
/// The app already shipped exactly the right pattern, and it was bolted to the
/// SMALLER egress: [RouteConsentStore] gates a one-shot coordinate send to the
/// OSRM demo server behind an accept/decline act, while the larger, repeating
/// location share had none. This is that pattern, applied to the larger one.
///
/// Same on-disk idiom as [RouteConsentStore] and TripHazardStore: plain JSON in
/// the app documents directory; absent, unreadable or malformed loads as null
/// ("not decided"), NEVER as a fabricated grant or a fabricated refusal.
///
/// A YES RECORDS THE WORDS IT ANSWERED (2026-09-25). Until then the store kept
/// only `schema`, `locationShareConsent` and `decidedAt`, and a remembered yes
/// skipped the dialog for good. The words had already changed in substance
/// between builds: one said sharing happens "only while the app is open",
/// the next that it continues with the screen off. A yes given to the first
/// would have been held against the second, and she would never have been
/// shown what changed. A yes now records the revision, the language and the
/// exact words of the dialog she answered, and a yes to any other revision is
/// not honoured: she is asked once more, and told why.
///
/// A WITHDRAWAL IS NEVER A REFUSAL TO ASK (2026-09-25). Withdrawing wrote
/// `locationShareConsent: false`, and on the next launch that false was read
/// back as her answer: the share button then did nothing at all, no question
/// and no share, while the card had just told her "you will be asked again".
/// Measured in the widget harness, not on a device. Only a yes to the current
/// words is honoured now; everything else leaves her undecided, and her next
/// tap asks.
///
/// SCOPE BOUND, stated so it is not over-read: this is the app's own consent
/// act. It is NOT the operating system's location permission, which still runs
/// afterwards and which she can still refuse there; and it is not a compliance
/// certification. A dignity review ruled the absence a material pre-ship risk
/// and said in as many words that it has no authority to certify compliance.
/// Neither has the author of this file.
library;

import 'dart:convert';
import 'dart:io';

/// Which revision of the consent dialog's words a yes must answer.
///
/// A revision names WHAT SHARING DOES as the dialog describes it. When the
/// dialog's words change what sharing does, this number goes up, and every
/// stored yes to an earlier revision is not honoured: she is asked once more.
/// A rewording that leaves what sharing does unchanged keeps the number.
///
/// The choice cannot be skipped. test/services/location_consent_revision_test.dart
/// compares the dialog's words with the words registered for this revision in
/// test/fixtures/location_consent_dialog/, and fails when they differ until the
/// change is registered: under this revision (same meaning), or under a new one
/// (new meaning, and every stored yes is asked again).
///
/// WHEN A NEW REVISION IS OWED (2026-09-25, a dignity review's test, for
/// whoever registers a change): when a yes to the old words would not cover
/// the new ones. That means more of her location used, sent, kept or running,
/// a new recipient, or less control for her; and it includes a correction
/// showing the old words understated what the app did. A rewording, or a
/// change that describes less, keeps the revision. A new revision is also
/// what makes the dialog tell her 「この説明が変わりました」, so it must never be
/// spent on a change she would not recognise as one.
///
/// Revision 1 is the first recorded one (2026-09-25). A yes stored before it
/// carries no revision and is asked once more: it answered either words that
/// said sharing happens only while the app is open, or words that did not yet
/// name location as what keeps running after the notification is swiped away,
/// and the record cannot tell which.
const int kLocationConsentRevision = 1;

/// What the store holds about her answer.
class LocationConsentRecord {
  const LocationConsentRecord({
    required this.granted,
    this.revision,
    this.locale,
    this.words,
    this.decidedAt,
  });

  /// true: she agreed. false: she withdrew (the only false this app writes).
  final bool granted;

  /// The revision of the words she answered. Null for a record written before
  /// revisions existed, and for a withdrawal.
  final int? revision;

  /// The language of the words she read, 'ja' or 'en'.
  final String? locale;

  /// The words of the dialog she answered, in the order she read them.
  final List<String>? words;

  /// When she answered, as written (UTC, ISO 8601).
  final String? decidedAt;

  /// True only for a yes that recorded the words of [current]. A withdrawal,
  /// a yes written before revisions existed, a yes to another revision, or a
  /// yes whose words are missing is not an answer to what the dialog says
  /// now: the caller asks her.
  bool answers(int current) =>
      granted && revision == current && (words?.isNotEmpty ?? false);

  /// A yes that does not answer [current]: she agreed once, and it is not
  /// honoured now, so she is asked.
  ///
  /// This is NOT the test for telling her the description changed; see
  /// [isYesToOtherRevision]. It is also true for a yes to the current revision
  /// whose words are missing or unreadable, and for that record the
  /// description has not changed: the record is damaged.
  bool isYesToOtherWords(int current) => granted && !answers(current);

  /// A yes to another revision of the words (or to words from before
  /// revisions existed): the description really has changed since she agreed.
  /// Only this record is told so when she is asked again (2026-09-25, a
  /// dignity review). A yes to the current revision with missing or
  /// unreadable words is asked plainly, because saying "this has changed" to
  /// her would be false.
  bool isYesToOtherRevision(int current) => granted && revision != current;
}

class LocationConsentStore {
  LocationConsentStore({required this.file});

  final File file;

  static const String fileName = 'location_consent.json';

  /// Record her yes, with the revision, the language and the exact words of
  /// the dialog she answered.
  Future<void> saveYes({
    required int revision,
    required String locale,
    required List<String> words,
  }) => _write({
    'schema': 2,
    'locationShareConsent': true,
    'decidedAt': DateTime.now().toUtc().toIso8601String(),
    'disclosureRevision': revision,
    'disclosureLocale': locale,
    'disclosureWords': words,
  });

  /// Record that she withdrew. It stays as a record of what she did and is
  /// never read back as a refusal: [LocationConsentRecord.answers] is false
  /// for it, so her next tap asks.
  Future<void> saveWithdrawal() => _write({
    'schema': 2,
    'locationShareConsent': false,
    'decidedAt': DateTime.now().toUtc().toIso8601String(),
  });

  Future<void> _write(Map<String, Object> record) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(record), flush: true);
  }

  /// Load what is stored. Returns null when absent, unreadable, or malformed:
  /// "not decided" asks; it never invents a grant or a refusal she did not
  /// make. Reads both the record written before 2026-09-25 (schema 1, no
  /// words) and the current one.
  Future<LocationConsentRecord?> load() async {
    try {
      if (!await file.exists()) return null;
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final granted = decoded['locationShareConsent'];
      if (granted is! bool) return null;
      final revision = decoded['disclosureRevision'];
      final locale = decoded['disclosureLocale'];
      final words = decoded['disclosureWords'];
      final decidedAt = decoded['decidedAt'];
      return LocationConsentRecord(
        granted: granted,
        revision: revision is int ? revision : null,
        locale: locale is String ? locale : null,
        words: words is List && words.every((w) => w is String)
            ? List<String>.unmodifiable(words.cast<String>())
            : null,
        decidedAt: decidedAt is String ? decidedAt : null,
      );
    } catch (_) {
      return null;
    }
  }
}
