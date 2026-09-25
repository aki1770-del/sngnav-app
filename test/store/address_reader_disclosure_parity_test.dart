// The pages describe the manifest address reader if, and only if, this tree
// has one (2026-09-25).
//
// WHY: the update check can follow its manifest to a new https address. The
// manifest may name a new home for itself; the app then makes one extra
// request there, and from the next launch fetches from the new address. The
// in-app policy page, the in-app card (AppL10n.egressDisclosure) and the
// data-safety sheet must say so in the SAME build, because a holder keeps the
// text of the build she holds. The text and the reader are separate commits,
// and either could be merged without the other. This test fails in both
// directions:
//   - the reader is in the tree and the pages do not describe it;
//   - the pages describe it and the reader is not in the tree.
//
// ⚑ REWRITTEN 2026-09-25 (round 5b). A control matrix run by the integration
// lead passed three defects through the first version of this test:
//   - M1: the call removed and its name left in a /* */ comment. The tree was
//     read as text and each line cut at its first `//`, so a block comment
//     read as a call (TRAP-19 in ENCOUNTERED_TRAPS.md).
//   - M2: the call spelled `(persistManifestUrl)(store)`. A text search for
//     `persistManifestUrl(` did not see it, so the reader RAN, her pages were
//     silent, and this test passed.
//   - M3: the policy's update-check prose reverted to the text from before the
//     reader, with the two HTML-comment markers kept. The policy half counted
//     those markers, which the in-app page never shows.
// The data-safety sheet's reader sentence was read by nothing at all. And the
// first version's negative control fed synthetic strings to the comparison
// and never ran the tree half on a real tree, so its own author could not have
// found any of this. Every control below runs on the real files.
//
// HOW THE TREE IS READ, twice, and the two readings must agree:
//   - BEHAVIOUR. This tree's UpdateChecker is served a manifest that names a
//     new home, and the home verifies. Does the check ask that home, and does
//     resolveManifestUrl() afterwards return it? That is the reader measured
//     by what it does, not by how it is spelled.
//   - SOURCE. Does lib/ refer to persistManifestUrl in CODE, other than in its
//     declaration? Read through dartCodeOnly (test/support/dart_source.dart),
//     so comments and string text are blank, and matched as an identifier,
//     called or not, so a tear-off or a parenthesised call counts.
//   When the two disagree the test fails and says which way: a dead call, or
//   a reader that stores by another path, is a tree whose pages this test
//   cannot write for her.
//
// HOW THE PAGES ARE READ. The policy goes through the app's own
// renderPolicyForDisplay, parsePolicyBlocks and policyInlineRuns, which is
// exactly what the in-app policy page draws, so nothing in an HTML comment can
// count. The update-check item of each language half must state the reader's
// three facts, in the words below. The sheet's update-check item is read the
// same way; it is not shown in the app, and a reader of the published sheet
// does not see its comments either. The card's strings are read as the app
// returns them.
//
// WHAT THIS DOES NOT CHECK: whether each sentence is true in detail (one
// request, no redirects, which address is kept, when). That is the reader's
// own suite, test/services/update_check_test.dart. This test holds presence
// against presence.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/privacy_policy.dart';
import 'package:sngnav_app/services/update_check.dart';
import 'package:sngnav_app/services/update_manifest.dart';

import '../support/dart_source.dart';

const _policyPath = 'docs/store/privacy_policy_ja.md';
const _sheetPath = 'docs/store/data_safety_declaration.md';

// ----- what the pages must say, in the words she reads -----
//
// Each entry is one fact the reader creates, keyed by what it means, in the
// certified wording. Reword the page and these in the SAME change: this table
// is the claim that the pages describe the reader.
const _policyJaFacts = {
  'the address can change': '一覧の置き場所は変わることがあります',
  'one request to the new address': 'そのアドレスへ 1 回だけ要求を送ります',
  'kept on the device and used from the next launch':
      'そのアドレスを端末に保存し、次の起動からそこを使います',
};
const _policyEnFacts = {
  'the address can change': "The list's own address can change",
  'one request to the new address':
      'the app sends one request to that address',
  'kept on the device and used from the next launch':
      'store the address on the device and use it from the next launch',
};
const _sheetFacts = {
  'one request to the new address': 'それを確かめる 1 回の要求を含む',
  'kept on the device and used from the next launch':
      '確かめられた置き場所は端末に保存し、次の起動から使う',
};
const _cardJaFacts = {'the new address': '置き場所'};
const _cardEnFacts = {'the new address': 'new https address'};

final _englishHeading = RegExp(r'^Privacy Policy.*\(English\)$');
final _policyItemJa = RegExp(r'^\d+\.\s*新しいビルドがあるかの確認');
final _policyItemEn = RegExp(r'^\d+\.\s*Update check');
final _sheetItem = RegExp(r'^\d+\.\s*更新確認');

/// A block's words as the in-app page draws them: bold markers dropped,
/// nothing else changed (lib/main.dart `_policyBlock`).
String _drawn(PolicyBlock block) {
  String runs(String t) => policyInlineRuns(t).map((r) => r.text).join();
  return switch (block) {
    PolicyHeading(:final text) => runs(text),
    PolicyParagraph(:final text) => runs(text),
    PolicyBullet(:final text) => runs(text),
    PolicyTable(:final rows) => [
        for (final r in rows) r.map(runs).join(' | '),
      ].join('\n'),
  };
}

/// [raw] as blocks of the words a reader is shown.
List<PolicyBlock> _blocks(String raw) =>
    parsePolicyBlocks(renderPolicyForDisplay(raw));

/// Every way the pages and the tree disagree about the address reader.
List<String> _disagreements({
  required bool hasReader,
  required String policy,
  required String sheet,
  required String cardJa,
  required String cardEn,
}) {
  final problems = <String>[];

  void judge(String where, String text, Map<String, String> facts) {
    final says = [
      for (final e in facts.entries)
        if (text.contains(e.value)) e.key,
    ];
    final lacks = [
      for (final e in facts.entries)
        if (!text.contains(e.value)) e.key,
    ];
    if (hasReader && lacks.isNotEmpty) {
      problems.add('the tree has the address reader, but $where does not '
          'say: ${lacks.join('; ')}');
    }
    if (!hasReader && says.isNotEmpty) {
      problems.add('$where describes an address reader this tree does not '
          'have: ${says.join('; ')}');
    }
  }

  void judgeItem(String where, Iterable<PolicyBlock> blocks, RegExp item,
      Map<String, String> facts) {
    final items = [
      for (final b in blocks)
        if (item.hasMatch(_drawn(b))) _drawn(b),
    ];
    if (items.length != 1) {
      problems.add('$where: expected one update-check item, found '
          '${items.length}, so this test cannot say what she reads about '
          'the reader');
      return;
    }
    judge(where, items.single, facts);
  }

  final page = _blocks(policy);
  final split = page.indexWhere((b) =>
      b is PolicyHeading && b.level == 1 && _englishHeading.hasMatch(b.text));
  if (split < 0) {
    problems.add('the privacy policy has no English half this test can find');
  } else {
    judgeItem('the privacy policy (ja)', page.take(split), _policyItemJa,
        _policyJaFacts);
    judgeItem('the privacy policy (en)', page.skip(split), _policyItemEn,
        _policyEnFacts);
  }
  judgeItem('the data-safety sheet', _blocks(sheet), _sheetItem, _sheetFacts);
  judge('the in-app card (ja)', cardJa, _cardJaFacts);
  judge('the in-app card (en)', cardEn, _cardEnFacts);
  return problems;
}

// ----- the tree, by SOURCE -----

final _name = RegExp(r'(^|[^A-Za-z0-9_])persistManifestUrl(?![A-Za-z0-9_$])');
final _declaration = RegExp(r'Future<[^>]*>\s+persistManifestUrl\s*\(');

/// The 1-based lines where [source] refers to persistManifestUrl in code,
/// other than its declaration: comments and string text never count, and a
/// reference counts whether or not it is followed by `(`.
List<int> _referencesIn(String source) {
  final code = dartCodeOnly(source);
  final starts = lineStartsOf(code);
  final declarations = [
    for (final d in _declaration.allMatches(code)) (d.start, d.end),
  ];
  return [
    for (final m in _name.allMatches(code))
      if (!declarations.any((d) =>
          m.start + m.group(1)!.length >= d.$1 &&
          m.start + m.group(1)!.length < d.$2))
        lineOfOffset(starts, m.start + m.group(1)!.length) + 1,
  ];
}

/// Every place in lib/ that refers to persistManifestUrl in code.
List<String> _sourceReferences() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      for (final line in _referencesIn(f.readAsStringSync())) '${f.path}:$line',
  ];
}

// ----- the tree, by BEHAVIOUR -----

const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _pkg = 'test.address.reader.disclosure';
const _from = 'https://disclosure.example.test/update_manifest.json';
const _home = 'https://moved.disclosure.example.test/update_manifest.json';
final _hex64 = List.filled(64, 'a').join();

/// A manifest the real parser accepts, for a build the running one already
/// is, so no artifact is probed: only the reader can make a second request.
String _manifest({String? home}) => jsonEncode({
      'schema': kUpdateManifestSchema,
      'manifest_url': ?home,
      'latest': {
        'versionName': '1.0.0',
        'versionCode': 1,
        'artifact_url': 'https://disclosure.example.test/app.apk',
        'package': _pkg,
        'sha256': _hex64,
        'size_bytes': 1,
        'signer_sha256': _hex64,
      },
    });

const _self = BuildIdentity(
  versionName: '1.0.0',
  versionCode: 1,
  packageName: _pkg,
);

/// One update check on this tree, served a manifest that names a new home.
/// [asks]: the check sent a request to that home. [keeps]: the NEXT check
/// would go there. With [serveHome] false the home answers 404; with
/// [nameHome] false the manifest names no home at all.
Future<({bool asks, bool keeps})> _readerBehaviour({
  bool serveHome = true,
  bool nameHome = true,
}) async {
  final dir = await Directory.systemTemp.createTemp('reader_disclosure_');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_pathChannel, (call) async => dir.path);
  try {
    final asked = <String>[];
    final client = MockClient((req) async {
      final url = '${req.url}';
      asked.add(url);
      if (url == _from) {
        return http.Response(_manifest(home: nameHome ? _home : null), 200);
      }
      if (url == _home && serveHome) {
        return http.Response(_manifest(home: _home), 200);
      }
      return http.Response('', 404);
    });
    await UpdateChecker(
      client: client,
      readIdentity: () async => _self,
      timeout: const Duration(seconds: 5),
    ).check(manifestUrl: Uri.parse(_from));
    final next = await UpdateChecker.resolveManifestUrl();
    return (asks: asked.contains(_home), keeps: '$next' == _home);
  } finally {
    messenger.setMockMethodCallHandler(_pathChannel, null);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// Whether this tree has the reader, or why that cannot be decided.
Future<({bool? hasReader, List<String> problems})> _tree() async {
  final seen = await _readerBehaviour();
  final refs = _sourceReferences();
  final problems = <String>[];
  if (seen.asks != seen.keeps) {
    problems.add(seen.asks
        ? 'the check asks a new home but never keeps it, so the pages can '
            'neither describe the reader nor stay silent truthfully'
        : 'the check keeps a new home it never asked');
  }
  if (refs.isNotEmpty != seen.keeps) {
    problems.add(refs.isNotEmpty
        ? 'lib/ refers to persistManifestUrl (${refs.join(', ')}), but the '
            'check kept no new home: a dead reference, or this test no '
            'longer exercises the reader'
        : 'the check kept a new home, but no code in lib/ refers to '
            'persistManifestUrl: the reader stores by a path this test does '
            'not read');
  }
  return (hasReader: problems.isEmpty ? seen.keeps : null, problems: problems);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final policy = File(_policyPath).readAsStringSync();
  final sheet = File(_sheetPath).readAsStringSync();
  const ja = AppL10n(Locale('ja'));
  const en = AppL10n(Locale('en'));

  test('the pages describe the address reader exactly when the tree has it',
      () async {
    final tree = await _tree();
    expect(tree.problems, isEmpty,
        reason: 'the tree half could not decide whether this build has the '
            'address reader');
    expect(
      _disagreements(
        hasReader: tree.hasReader!,
        policy: policy,
        sheet: sheet,
        cardJa: ja.egressDisclosure,
        cardEn: en.egressDisclosure,
      ),
      isEmpty,
      reason: 'ship the address reader and the words that describe it in the '
          'same build, or neither',
    );
  });

  group('CONTROLS, each on the real files', () {
    final reader = File('lib/services/update_check.dart').readAsStringSync();
    const call = 'await persistManifestUrl(store)';

    String edited(String from, String to) {
      expect(reader, contains(call),
          reason: 'the control cannot be built: the call it edits moved');
      return reader.replaceFirst(from, to);
    }

    test('SOURCE: the real call is seen, and so is a parenthesised one (M2)',
        () {
      expect(_referencesIn(reader), isNotEmpty,
          reason: 'positive control: the call in lib/ today');
      expect(
          _referencesIn(edited(call, 'await (persistManifestUrl)(store)')),
          isNotEmpty,
          reason: 'M2: the reader still runs, so it must still be seen');
      expect(_referencesIn(edited(call, 'await (persistManifestUrl).call(store)')),
          isNotEmpty);
    });

    test('SOURCE: a name left in a comment or a string is not a reference '
        '(M1)', () {
      expect(_referencesIn(edited(call, 'false /* persistManifestUrl(store) */')),
          isEmpty,
          reason: 'M1: the call is gone; its name in a block comment is not '
              'a reader');
      expect(
          _referencesIn(edited(call, 'false // persistManifestUrl(store)\n')),
          isEmpty);
      expect(_referencesIn(edited(call, "'persistManifestUrl(store)'.isEmpty")),
          isEmpty);
      expect(_referencesIn(edited(call, 'false')), isEmpty,
          reason: 'the declaration alone is not a reference');
    });

    test('BEHAVIOUR: each observation can come out false on the real checker',
        () async {
      final unserved = await _readerBehaviour(serveHome: false);
      expect((unserved.asks, unserved.keeps), (true, false),
          reason: 'a home that does not verify is asked and not kept');
      final unnamed = await _readerBehaviour(nameHome: false);
      expect((unnamed.asks, unnamed.keeps), (false, false),
          reason: 'a manifest naming no home makes no second request');
    });

    test('PAGES: the real pages are read as describing the reader, all five '
        'surfaces', () {
      final problems = _disagreements(
        hasReader: false,
        policy: policy,
        sheet: sheet,
        cardJa: ja.egressDisclosure,
        cardEn: en.egressDisclosure,
      );
      expect(problems, hasLength(5),
          reason: 'with no reader in the tree, the policy (ja, en), the sheet '
              'and the card (ja, en) must each be named: $problems');
    });

    test('PAGES: a fact moved into an HTML comment is a fact she does not '
        'read (M3)', () {
      for (final facts in [_policyJaFacts, _policyEnFacts]) {
        for (final e in facts.entries) {
          expect(policy, contains(e.value),
              reason: 'the control cannot be built: "${e.key}" is not in the '
                  'policy as written');
          final hidden = policy.replaceFirst(e.value, '<!-- ${e.value} -->');
          final problems = _disagreements(
            hasReader: true,
            policy: hidden,
            sheet: sheet,
            cardJa: ja.egressDisclosure,
            cardEn: en.egressDisclosure,
          );
          expect(problems.join('\n'), contains(e.key),
              reason: 'the fact "${e.key}" survives only in a note she never '
                  'sees, and must be missed');
        }
      }
    });

    test('PAGES: the sheet is read, fact by fact', () {
      for (final e in _sheetFacts.entries) {
        expect(sheet, contains(e.value),
            reason: 'the control cannot be built: "${e.key}" is not in the '
                'sheet as written');
        final problems = _disagreements(
          hasReader: true,
          policy: policy,
          sheet: sheet.replaceFirst(e.value, ''),
          cardJa: ja.egressDisclosure,
          cardEn: en.egressDisclosure,
        );
        expect(problems, hasLength(1));
        expect(problems.single, contains('the data-safety sheet'));
        expect(problems.single, contains(e.key));
      }
    });

    test('PAGES: an update-check item this test cannot find is a failure, '
        'never a pass', () {
      final retitled = policy.replaceFirst('**Update check**', '**Updates**');
      expect(retitled, isNot(policy),
          reason: 'the control cannot be built: the English title moved');
      final problems = _disagreements(
        hasReader: true,
        policy: retitled,
        sheet: sheet,
        cardJa: ja.egressDisclosure,
        cardEn: en.egressDisclosure,
      );
      expect(problems.join('\n'), contains('found 0'));
    });
  });
}
