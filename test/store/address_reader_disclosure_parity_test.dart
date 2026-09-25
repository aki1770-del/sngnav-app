// The pages describe the manifest address reader if, and only if, this tree
// has one (2026-09-25).
//
// WHY: a parallel change teaches the update check to follow its manifest to a
// new https address: the manifest may name a new home for itself, the app then
// makes one extra request there, and from the next launch fetches from the new
// address. The in-app disclosure (AppL10n.egressDisclosure) and the privacy
// policy must say so in the SAME build, because a holder keeps the text of the
// build she holds. The text and the reader are separate commits, and either
// could be merged without the other. This test fails in both directions:
//   - the reader is in the tree and the pages do not describe it;
//   - the pages describe it and the reader is not in the tree.
//
// HOW the tree is read: the reader is present when lib/ CALLS
// UpdateChecker.persistManifestUrl (before the reader, that method existed
// with no caller at all). The pages describe it when the policy carries the
// marker `<!-- describes: manifest-address-reader -->` in both halves and the
// in-app card names the new address in both languages.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

const _policyPath = 'docs/store/privacy_policy_ja.md';
final _marker =
    RegExp(r'<!--\s*describes:\s*manifest-address-reader\s*-->');

/// True when some file in lib/ calls persistManifestUrl (not only declares it).
bool _treeHasReader() {
  final call = RegExp(r'persistManifestUrl\(');
  // Any return type: the method was `Future<void>` before the reader and is
  // `Future<bool>` with it.
  final declaration = RegExp(r'Future<[^>]*>\s+persistManifestUrl\(');
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final line in f.readAsLinesSync()) {
      final code = line.split('//').first;
      if (call.hasMatch(code) && !declaration.hasMatch(code)) return true;
    }
  }
  return false;
}

/// Every way the pages and the tree disagree about the address reader.
List<String> _disagreements({
  required bool hasReader,
  required String policy,
  required String cardJa,
  required String cardEn,
}) {
  final markers = _marker.allMatches(policy).length;
  final cardJaSays = cardJa.contains('置き場所');
  final cardEnSays = cardEn.contains('new https address');
  final problems = <String>[];
  if (hasReader) {
    if (markers != 2) {
      problems.add('the tree has the address reader, but the privacy policy '
          'describes it in $markers of its 2 halves');
    }
    if (!cardJaSays || !cardEnSays) {
      problems.add('the tree has the address reader, but the in-app card does '
          'not describe it (ja: $cardJaSays, en: $cardEnSays)');
    }
  } else {
    if (markers != 0) {
      problems.add('the privacy policy describes an address reader this tree '
          'does not have ($markers markers)');
    }
    if (cardJaSays || cardEnSays) {
      problems.add('the in-app card describes an address reader this tree '
          'does not have');
    }
  }
  return problems;
}

void main() {
  final policy = File(_policyPath).readAsStringSync();
  const ja = AppL10n(Locale('ja'));
  const en = AppL10n(Locale('en'));

  test('the pages describe the address reader exactly when the tree has it',
      () {
    expect(
      _disagreements(
        hasReader: _treeHasReader(),
        policy: policy,
        cardJa: ja.egressDisclosure,
        cardEn: en.egressDisclosure,
      ),
      isEmpty,
      reason: 'ship the address reader and the text that describes it in the '
          'same build, or neither',
    );
  });

  test('NEGATIVE CONTROL: each half of the rule can fail', () {
    // The reader present, the pages silent.
    expect(
        _disagreements(
            hasReader: true, policy: '', cardJa: '', cardEn: ''),
        isNotEmpty);
    // The pages describing it, the reader absent.
    expect(
        _disagreements(
            hasReader: false,
            policy: '<!-- describes: manifest-address-reader -->',
            cardJa: '置き場所',
            cardEn: 'new https address'),
        isNotEmpty);
  });
}
