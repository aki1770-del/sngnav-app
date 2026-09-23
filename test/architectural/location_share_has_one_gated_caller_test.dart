/// The location share must keep exactly ONE caller, and it must be the gated one.
///
/// WHY A SOURCE-LEVEL GUARD AND NOT ANOTHER WIDGET TEST. The behavioural guard
/// for the consent act
/// (test/widgets/location_consent_act_and_privacy_surface_test.dart) taps the
/// share button and proves that path asks first. It cannot see a SECOND caller
/// being added — a retry, a lifecycle resume, an auto-restart. Such a caller
/// would bypass the act and every existing guard would stay green, because none
/// of them taps anything else. That is Sakichi Vision 9 exactly: "The operator
/// must not be the last line of defense against defects — the machine itself
/// must catch them." Without this file the reviewer is that last line.
///
/// Found by VDE on an independent verification of the consent act, which is
/// also where the counts below were first measured; they are re-measured here
/// on every run rather than pinned from that report.
///
/// HONEST BOUND. This is a grep over source text, not a call graph. It cannot
/// see a call reached through a tear-off stored in a variable, through
/// reflection, or from another library. It catches the shape that actually
/// occurred and the shape a future edit is most likely to take — a second
/// `onPressed: _shareLocation` — and nothing wider is claimed for it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comments removed, so a mention of the symbol in prose — and
/// there are several, including in the very comments that explain this gate —
/// cannot satisfy or break the count.
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      if (t.startsWith('///') || t.startsWith('//')) return '';
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

void main() {
  test('_shareLocation is referenced exactly twice: its declaration and the '
      'one call inside the consent-gated handler', () {
    final code = _code('lib/main.dart');
    final refs = RegExp(r'\b_shareLocation\b').allMatches(code).length;
    expect(
      refs,
      2,
      reason: 'Expected the declaration plus exactly ONE call, which lives in '
          '_onShareLocationPressed AFTER `await _ensureLocationConsent()` '
          'returns true. Found $refs. A third reference is almost certainly a '
          'second route to the position stream that never asks her — the '
          'operating system prompt sits AFTER our act, so a bypass here '
          'reaches her GPS with no in-app consent at all. If you added a '
          'legitimate caller, route it through _onShareLocationPressed and '
          'this stays at 2.',
    );
  });

  test('the only call to _shareLocation is inside the gated handler', () {
    final code = _code('lib/main.dart');
    final handler = RegExp(
      r'Future<void> _onShareLocationPressed\(\) async \{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(code);
    expect(handler, isNotNull,
        reason: 'the gated handler must exist and keep its name');
    final body = handler!.group(1)!;
    expect(body, contains('_ensureLocationConsent()'),
        reason: 'the handler must ASK before it shares');
    expect(body, contains('_shareLocation()'),
        reason: 'and the share must happen inside it');
    // The ask must precede the share, textually — a share before the ask is
    // an ask that decides nothing.
    expect(body.indexOf('_ensureLocationConsent()'),
        lessThan(body.indexOf('_shareLocation()')),
        reason: 'the act must come first');
  });

  test('the share control is wired to the gated handler, not to the share',
      () {
    final code = _code('lib/main.dart');
    final button = RegExp(
      r"key: const Key\('share-location-button'\),(.*?)\),",
      dotAll: true,
    ).firstMatch(code);
    expect(button, isNotNull, reason: 'the share control must exist');
    expect(button!.group(1)!, contains('onPressed: _onShareLocationPressed'),
        reason: 'wiring it straight to _shareLocation is the exact bypass this '
            'file exists to catch');
  });
}
