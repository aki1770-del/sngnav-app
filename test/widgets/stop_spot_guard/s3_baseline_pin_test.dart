/// The stop-spot guard's S-3 fixture is pinned (code 16, 2026-10-14).
///
/// WHY. The fixture decides both what is skipped and every carried ceiling:
/// the census compares each carried geometry's yes and no with it. A fixture
/// regenerated from a worse head would carry the worse head, and the census
/// would read the worse numbers as the carry (the consent review's bound,
/// c7493c62). Pinned, a change to what is carried is a deliberate act in its
/// own commit, never a side effect of a regeneration. Sakichi Vision 16:
/// fail-closed beats fail-open; ambiguity must route toward halt, not pass.
///
/// WHAT A PASS MEANS. The fixture's bytes hash to the pin below, and its header
/// names the two runs it was generated from: code 15's tree (b7749a3d) and the
/// head the carry was recorded on (f1a47d46). The hash is FNV-1a, 64 bits, with
/// no package beyond the SDK. It is not cryptographic: it catches a change, not
/// an adversary.
///
/// TO CHANGE WHAT IS CARRIED: regenerate the fixture with its generator, say so
/// in the commit, and update this pin in the same commit.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kS3FixturePath = 'test/fixtures/stop_spot_guard/s3_baseline.tsv';

/// FNV-1a 64 of the fixture as committed with the no ceiling (2026-10-14).
const String kS3FixturePin = '953e7c776bffd37d';

/// FNV-1a, 64 bits, as 16 hex digits. Dart's integers wrap at 64 bits, and
/// one above 2^63 is negative, so it is printed as two 32-bit halves (a first
/// draft printed it signed; the published values below caught it).
String fnv1a64Hex(List<int> bytes) {
  var h = 0xcbf29ce484222325;
  for (final b in bytes) {
    h ^= b;
    h *= 0x100000001b3;
  }
  String half(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return half(h >> 32) + half(h);
}

void main() {
  test('control: the hash gives FNV-1a 64\'s published values', () {
    expect(fnv1a64Hex(const []), 'cbf29ce484222325');
    expect(fnv1a64Hex('a'.codeUnits), 'af63dc4c8601ec8c');
    expect(fnv1a64Hex('foobar'.codeUnits), '85944171f73967e8');
  });

  test('the S-3 fixture is the one carried: pinned by hash and by the two '
      'runs it names', () {
    final bytes = File(kS3FixturePath).readAsBytesSync();
    final text = String.fromCharCodes(bytes);
    expect(
      text,
      contains('code 15\'s tree (b7749a3d,'),
      reason: 'the fixture no longer names code 15\'s run it was made from',
    );
    expect(
      text,
      contains('the red sets on the head (f1a47d46)'),
      reason: 'the fixture no longer names the head the carry was recorded on',
    );
    expect(
      fnv1a64Hex(bytes),
      kS3FixturePin,
      reason:
          'the S-3 fixture changed, and with it what is skipped and every '
          'carried ceiling. What is carried may change only on purpose: '
          'regenerate it with its generator, say so in the commit, and update '
          'this pin in the same commit.',
    );
  });
}
