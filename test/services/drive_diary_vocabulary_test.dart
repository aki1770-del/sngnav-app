/// DRIFT GUARD — HER diary chips are pinned to the catalog's canonical JP
/// vocabulary, not to app-local translations-from-English.
///
/// WHY this file exists (measured 2026-08-10): `DiaryRoadCondition`'s ja
/// labels were hand-authored inside the app while the unit already shipped
/// `japanese_snow_vocabulary`, whose stated purpose is to prevent *"the
/// silent erasure of finer-grained JA vocabulary by English-language
/// collapse."* A hand-authored chip list is that erasure, one layer down: the
/// enum cases are NAMED in English (dry/wet/snow/ice) with the ja as a
/// translation afterthought. These tests make the binding mechanical, so a
/// catalog vocabulary change can never leave HER chip reading a stale word
/// while every other suite stays green.
///
/// This is a guard, not a style check: the word on the chip is the whole of
/// what the season's evidence reader receives. If it drifts from the term
/// the driver actually says, the entry stops being collatable against the
/// vocabulary the rest of the stack speaks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:sngnav_app/services/drive_diary.dart';

void main() {
  group('diary vocabulary is sourced from the catalog, not the app', () {
    test('every bound chip reads the package term VERBATIM', () {
      final bound =
          DiaryRoadCondition.values.where((c) => c.vocabulary != null);

      // Guard the guard: if every binding were null this test would pass
      // vacuously and protect nothing.
      expect(bound, isNotEmpty,
          reason: 'no chip is bound to the vocabulary package — the drift '
              'guard would be vacuous');

      for (final c in bound) {
        final entry = jafAuthoritativeData[c.vocabulary];
        expect(entry, isNotNull,
            reason: '${c.name} names ${c.vocabulary} but the package has no '
                'entry for it');
        expect(
          c.ja,
          entry!.termJa,
          reason: 'chip ${c.name} reads "${c.ja}" but the catalog term is '
              '"${entry.termJa}" — HER chip has drifted from the vocabulary '
              'the rest of the stack speaks',
        );
      }
    });

    test('ブラックアイスバーン is reportable — the flagship warning has a chip',
        () {
      // The app's most-hardened in-drive advisory speaks and draws
      // 「ブラックアイスバーン」. Before 2026-08-10 the diary had no chip for it,
      // so a driver could not report the surface the app had just warned her
      // about, and the season's falsifier #2 ("did the warning match
      // reality?") was unanswerable for that warning.
      final blackIce = DiaryRoadCondition.values
          .where((c) => c.vocabulary == JapaneseSnowSurfaceClass.blackIceBahn);

      expect(blackIce, hasLength(1),
          reason: 'exactly one chip must report black ice');
      expect(blackIce.single.ja, 'ブラックアイスバーン');
      expect(blackIce.single.token, 'black-ice');
    });

    test('black ice is DISTINCT from visible ice — the distinction that '
        'decides a true positive', () {
      // These two must never collapse back into one chip. 凍結・アイスバーン is
      // ice she could SEE; black ice is defined by being invisible. Collapsing
      // them makes "fired, road visibly frozen" and "fired, road looked merely
      // wet" the same entry.
      expect(DiaryRoadCondition.blackIce,
          isNot(equals(DiaryRoadCondition.ice)));
      expect(DiaryRoadCondition.blackIce.token,
          isNot(equals(DiaryRoadCondition.ice.token)));
      expect(DiaryRoadCondition.blackIce.ja,
          isNot(equals(DiaryRoadCondition.ice.ja)));
    });

    test('a spanning chip still quotes the package terms it spans', () {
      // `ice` deliberately spans 凍結 + アイスバーン (vocabulary == null, so the
      // verbatim guard above skips it). It must still be built FROM the
      // catalog's words rather than invented ones, or the span silently
      // becomes a third vocabulary.
      final frozen = jafAuthoritativeData[JapaneseSnowSurfaceClass.surfaceFrozen]!;
      final iceBahn = jafAuthoritativeData[JapaneseSnowSurfaceClass.iceBahn]!;
      expect(DiaryRoadCondition.ice.ja, contains(frozen.termJa));
      expect(DiaryRoadCondition.ice.ja, contains(iceBahn.termJa));

      final slush = jafAuthoritativeData[JapaneseSnowSurfaceClass.slush]!;
      expect(DiaryRoadCondition.wet.ja, contains(slush.termJa));
    });

    test('tokens already on a beta driver device are never renamed', () {
      // Entries written before 2026-08-10 carry these exact tokens. Renaming
      // one silently orphans her existing testimony from the reader's
      // collation. New distinctions arrive as NEW tokens only.
      const shippedTokens = {
        'dry',
        'wet-slush',
        'snow',
        'compacted-snow',
        'ice',
        'whiteout',
        'unknown',
      };
      final live = DiaryRoadCondition.values.map((c) => c.token).toSet();
      expect(live.containsAll(shippedTokens), isTrue,
          reason: 'a shipped token disappeared: '
              '${shippedTokens.difference(live)} — entries already written to '
              "a beta driver's device would no longer collate");
    });

    test('tokens are unique — two chips may never write the same token', () {
      final tokens = DiaryRoadCondition.values.map((c) => c.token).toList();
      expect(tokens.toSet(), hasLength(tokens.length));
    });

    test('the unanswered default is not an observation', () {
      // 'わからない' must stay a distinct, non-taxonomy value: a driver who
      // did not answer must never be recorded as having observed something.
      expect(DiaryRoadCondition.unknown.vocabulary, isNull);
      expect(DiaryRoadCondition.unknown.ja, 'わからない');
    });
  });

  group('the new chip round-trips to the file she shares', () {
    test('a black-ice entry records both the ja term and the stable token',
        () {
      // The reader cross-checks a dated entry against AMeDAS; both halves
      // must survive to the file, or the entry is unreadable by one of the
      // two audiences (a human reader / a collating script).
      expect(DiaryRoadCondition.blackIce.ja, 'ブラックアイスバーン');
      expect(DiaryRoadCondition.blackIce.token, 'black-ice');
    });
  });
}
