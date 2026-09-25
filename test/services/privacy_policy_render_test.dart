/// The policy renderer may change PRESENTATION and not one word.
///
/// WHY THIS GUARD IS THE LOAD-BEARING PART. The page used to hand the markdown
/// source to a single Text widget, so she read `#` before every heading, `**`
/// around every emphasis, and the two Android permission tables as rows of
/// pipes — the tables being exactly what a person reads to decide whether to
/// trust us with her position. Repairing that means PARSING the document, and
/// a parser on a legal surface can silently drop a clause. That failure would
/// be worse than the pipes, and it would be invisible: a dropped paragraph
/// looks like a document that never had one.
///
/// So the renderer's contract is checked by reconstruction, not by inspection.
/// The source and the parsed blocks are each reduced to the same canonical
/// form — markdown syntax removed, whitespace collapsed — and compared for
/// EQUALITY. Equality catches a dropped clause, an added one, and a reordered
/// one, on the real shipped document rather than on a fixture.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/privacy_policy.dart';

/// Markdown syntax stripped, whitespace collapsed. The ONLY characters this
/// removes are ones the renderer also removes.
String _canonicalSource(String md) {
  final out = <String>[];
  for (final raw in md.split('\n')) {
    var t = raw.trim();
    if (t.isEmpty) continue;
    // A `|---|:--|` separator carries no words; it is the one thing the parser
    // discards, and this is where that is declared rather than assumed.
    final cells = t.startsWith('|')
        ? t.replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim())
        : const <String>[];
    if (cells.isNotEmpty &&
        cells.every((c) => c.isNotEmpty && RegExp(r'^[-: ]+$').hasMatch(c))) {
      continue;
    }
    t = t.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
    t = t.replaceFirst(RegExp(r'^[-*]\s+'), '');
    t = t.replaceAll('|', ' ');
    t = t.replaceAll('**', '');
    out.add(t);
  }
  return out.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _canonicalBlocks(List<PolicyBlock> blocks) {
  final out = <String>[];
  for (final b in blocks) {
    switch (b) {
      case PolicyHeading(:final text):
        out.add(text);
      case PolicyParagraph(:final text):
        out.add(text);
      case PolicyBullet(:final text):
        out.add(text);
      case PolicyTable(:final rows):
        for (final r in rows) {
          out.add(r.join(' '));
        }
    }
  }
  return out
      .join(' ')
      .replaceAll('**', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NOT ONE WORD CHANGES: the real shipped document survives parsing '
      'exactly', () async {
    final doc = (await loadPrivacyPolicy())!;
    final blocks = parsePolicyBlocks(doc);
    expect(_canonicalBlocks(blocks), _canonicalSource(doc),
        reason: 'a parser on a legal surface that drops a clause is worse '
            'than one that shows pipes, and a dropped clause is invisible');
  });

  // 2026-09-25. The 2026-09-24 correction note retracted a sentence by
  // striking it through. This renderer draws no strikethrough, so she read the
  // retracted guarantee in bold between literal tildes, and the next note
  // pointed at "the struck-through clause above", which she could not see. A
  // strikethrough is also a mark a screen reader does not speak: struck or
  // not, the sentence is read out as if it stood. A retraction has to be said
  // in words, on this page and on the published one.
  test('a retraction is said in words: no strikethrough in the document',
      () async {
    final doc = (await loadPrivacyPolicy())!;
    expect(doc.contains('~~'), isFalse,
        reason: 'the renderer does not draw ~~, and a screen reader does not '
            'speak it; quote the retracted sentence and say it was wrong');
    // The retracted sentence itself is kept, quoted, in both halves, so the
    // record of what the page once promised survives the edit. (The English
    // source wraps lines; compare with whitespace collapsed.)
    expect(doc, contains('「通知が出ていない状態での位置情報取得は、以前と同じく一切ありません。」'));
    expect(
        doc.replaceAll(RegExp(r'\s+'), ' '),
        contains('"what has NOT changed is that there is no location '
            'collection without a visible notification"'));
    expect(doc.contains('取り消し線'), isFalse,
        reason: 'no note may point at a line she cannot see');
    expect(doc.contains('struck-through'), isFalse);
  });

  test('the markdown syntax she used to read is gone from the blocks',
      () async {
    final blocks = parsePolicyBlocks((await loadPrivacyPolicy())!);
    final headings = blocks.whereType<PolicyHeading>().toList();
    expect(headings, isNotEmpty);
    for (final h in headings) {
      expect(h.text.startsWith('#'), isFalse,
          reason: 'the heading marker is removed, not shown');
    }
    // No block may still be carrying a table row as prose.
    for (final p in blocks.whereType<PolicyParagraph>()) {
      expect(p.text.trimLeft().startsWith('|'), isFalse,
          reason: 'a pipe row must become a table, not a paragraph');
    }
  });

  test('BOTH permission tables parse as tables, in both languages', () async {
    final blocks = parsePolicyBlocks((await loadPrivacyPolicy())!);
    final tables = blocks.whereType<PolicyTable>().toList();
    expect(tables.length, greaterThanOrEqualTo(2),
        reason: 'the document carries a permission table in ja and one in en');
    for (final t in tables) {
      expect(t.rows.length, greaterThan(1),
          reason: 'a header row and at least one permission');
      expect(t.rows.every((r) => r.isNotEmpty), isTrue);
      for (final r in t.rows) {
        expect(r.every((c) => !RegExp(r'^[-: ]+$').hasMatch(c) || c.isEmpty),
            isTrue,
            reason: 'the |---| separator is not a data row');
      }
    }
    // The ja table names the permissions this app actually declares.
    final cells = tables.expand((t) => t.rows.expand((r) => r)).join(' ');
    for (final perm in const [
      'INTERNET',
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'WAKE_LOCK',
      'VIBRATE',
    ]) {
      expect(cells, contains(perm),
          reason: '$perm is declared in the manifest and must be in the table '
              'she reads');
    }
  });

  test('bold runs keep their text and lose only the markers', () {
    final runs = policyInlineRuns('a **b** c');
    expect(runs.map((r) => r.text).join(), 'a b c');
    expect(runs.singleWhere((r) => r.bold).text, 'b');
  });

  test('the parser is total: nothing falls through', () {
    // A line matching no rule must still become a block.
    final blocks = parsePolicyBlocks('>>> odd line <<<');
    expect(blocks, hasLength(1));
    expect((blocks.single as PolicyParagraph).text, '>>> odd line <<<');
  });

  test('a table with a missing separator still parses as a table', () {
    final blocks = parsePolicyBlocks('| a | b |\n| c | d |');
    final t = blocks.single as PolicyTable;
    expect(t.hasHeader, isFalse);
    expect(t.rows, [
      ['a', 'b'],
      ['c', 'd'],
    ]);
  });
}
