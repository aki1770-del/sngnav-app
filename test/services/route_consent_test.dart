// B27 — RouteConsentStore round-trip + honest-null discipline.
//
// The store remembers HER pre-send decision for the OSRM coordinate egress.
// The load-bearing property: absent/unreadable/malformed state loads as null
// ("not decided" → ask again) — NEVER as a fabricated grant (which would
// send her coordinates without consent) and NEVER as a fabricated refusal
// (which would silently lock a door she did not close).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_app/services/route_consent.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('route_consent_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File storeFile() => File('${tmp.path}/${RouteConsentStore.fileName}');

  test('grant round-trips', () async {
    final store = RouteConsentStore(file: storeFile());
    await store.save(true);
    expect(await store.load(), isTrue);
  });

  test('decline round-trips', () async {
    final store = RouteConsentStore(file: storeFile());
    await store.save(false);
    expect(await store.load(), isFalse);
  });

  test('a later decision overwrites the earlier one', () async {
    final store = RouteConsentStore(file: storeFile());
    await store.save(false);
    await store.save(true);
    expect(await store.load(), isTrue);
  });

  test('absent file loads as null (not decided) — never a fabricated grant',
      () async {
    final store = RouteConsentStore(file: storeFile());
    expect(await store.load(), isNull);
  });

  test('corrupt file loads as null', () async {
    final f = storeFile();
    await f.writeAsString('{not json');
    final store = RouteConsentStore(file: f);
    expect(await store.load(), isNull);
  });

  test('non-bool consent value loads as null (a string "true" is not a '
      'decision)', () async {
    final f = storeFile();
    await f.writeAsString('{"schema":1,"osrmCoordinateConsent":"true"}');
    final store = RouteConsentStore(file: f);
    expect(await store.load(), isNull);
  });

  test('non-map JSON loads as null', () async {
    final f = storeFile();
    await f.writeAsString('[true]');
    final store = RouteConsentStore(file: f);
    expect(await store.load(), isNull);
  });
}
