// The privacy policy's list of network flows, in both languages, and the
// data-safety sheet's list are the SAME list (2026-09-25).
//
// WHY: an audit on 2026-09-25 found the two documents disagreeing with each
// other and with the code. The policy listed five flows as "all of it" and
// left out the JMA forecast request; the data-safety sheet listed five
// destinations too, but a different five: it had the forecast and left out
// route lookup. Each document also said its count was complete.
//
// HOW: each flow in each list carries a hidden marker, `<!-- flow: NAME -->`
// (an HTML comment, so it is not shown on the in-app policy page). This test
// reads the markers in order from the policy's Japanese half, its English
// half, and the data-safety sheet, and requires the three sequences to be
// identical. It also requires each "these N are all of it" sentence to state
// the same N.
//
// WHAT IT DOES NOT CHECK: whether the list matches the CODE. Hosts in the
// code are checked against the policy by tool/assert_disclosure_parity.sh;
// two different requests to the same host are visible to neither check.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _policyPath = 'docs/store/privacy_policy_ja.md';
const _sheetPath = 'docs/store/data_safety_declaration.md';

final _marker = RegExp(r'<!--\s*flow:\s*([a-z0-9-]+)\s*-->');
final _englishHeading =
    RegExp(r'^#\s+Privacy Policy.*\(English\)\s*$', multiLine: true);

List<String> _flows(String text) =>
    [for (final m in _marker.allMatches(text)) m.group(1)!];

({String ja, String en}) _halves(String policy) {
  final m = _englishHeading.firstMatch(policy);
  if (m == null) throw StateError('no English heading in the policy');
  return (ja: policy.substring(0, m.start), en: policy.substring(m.start));
}

/// Every disagreement between the three lists and their stated counts.
List<String> _disagreements(String policy, String sheet) {
  final problems = <String>[];
  final h = _halves(policy);
  final ja = _flows(h.ja), en = _flows(h.en), ds = _flows(sheet);
  if (ja.isEmpty) problems.add('the Japanese policy list has no flow markers');
  if (ja.join(',') != en.join(',')) {
    problems.add('policy ja $ja != policy en $en');
  }
  if (ja.join(',') != ds.join(',')) {
    problems.add('policy ja $ja != data-safety sheet $ds');
  }
  if (ja.toSet().length != ja.length) problems.add('a flow is listed twice: $ja');
  const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six',
      'seven', 'eight', 'nine', 'ten'];
  final n = ja.length;
  if (!h.ja.contains('この$nつがすべてです')) {
    problems.add('the Japanese heading does not say この$nつがすべてです');
  }
  if (!h.ja.contains('「端末の外に出るデータ」の$nつのみ')) {
    problems.add('the Japanese INTERNET row does not say $n');
  }
  if (n < words.length) {
    if (!h.en.contains('these ${words[n]} flows are all of it')) {
      problems.add('the English heading does not say "these ${words[n]} flows"');
    }
    if (!h.en.contains('only the ${words[n]} flows listed below')) {
      problems.add('the English INTERNET row does not say ${words[n]}');
    }
  }
  return problems;
}

void main() {
  final policy = File(_policyPath).readAsStringSync();
  final sheet = File(_sheetPath).readAsStringSync();

  test('policy (ja), policy (en) and the data-safety sheet list the same '
      'flows, in the same order, and each count says so', () {
    expect(_disagreements(policy, sheet), isEmpty);
    // The flows the 2026-09-25 audit counted in the code.
    expect(_flows(sheet), [
      'jma-amedas',
      'jma-forecast',
      'warnings',
      'route',
      'tiles',
      'update-check',
    ]);
  });

  test('NEGATIVE CONTROL: dropping one flow from the sheet is caught', () {
    final broken =
        sheet.replaceFirst(RegExp(r'<!--\s*flow:\s*jma-forecast\s*-->'), '');
    expect(_disagreements(policy, broken), isNotEmpty,
        reason: 'the sheet omitting the forecast is the defect this exists for');
  });

  test('NEGATIVE CONTROL: a count that no longer matches is caught', () {
    final broken = policy.replaceFirst('この6つがすべてです', 'この5つがすべてです');
    expect(_disagreements(broken, sheet), isNotEmpty);
  });
}
