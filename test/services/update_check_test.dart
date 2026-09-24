// The ANNOUNCING half of the update route, and -- load-bearing -- its NEGATIVE
// CONTROLS. A guard without a negative control proves nothing: a checker that
// announced unconditionally would pass every "it announced" test here.
//
// Schema under test is the one `scripts/pds_app_route_guard.py` EMITS
// (`sngnav-update-manifest/1`). The manifest is generated from the artifact,
// never hand-typed; this only parses it.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/services/build_identity.dart';
import 'package:sngnav_app/services/update_check.dart';
import 'package:sngnav_app/services/update_manifest.dart';

const kPkg = 'dev.aki1770del.sngnav_app';
const shaRunning =
    '7129d4a4bb1b03e3badcb20b37a26f22c1b4e1e86946d5b4df4598898a90b845';
const shaLatest =
    'fd2cdf4b615b275bdfbe1902ee8249473e603f83b8325def2552020f85038937';
const shaSigner =
    '6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14';

const running = BuildIdentity(
  versionName: '0.0.2',
  versionCode: 10,
  packageName: kPkg,
  selfSha256: shaRunning,
  gitSha: '5794d0c',
  artifactCount: 1,
);

final manifestUrl = Uri.parse('https://example.test/update_manifest.json');
const artifact = 'https://example.test/app.apk';

String manifestJson({
  required int versionCode,
  String versionName = '0.0.2',
  String? artifactUrl = artifact,
  String schema = kUpdateManifestSchema,
  String pkg = kPkg,
  String sha = shaLatest,
  int size = 94671699,
  String? signer = shaSigner,
  List<Map<String, dynamic>>? history,
  Map<String, dynamic> extraLatest = const {},
  Map<String, dynamic> extraTop = const {},
}) =>
    jsonEncode({
      'schema': schema,
      'latest': {
        'versionName': versionName,
        'versionCode': versionCode,
        if (artifactUrl != null) 'artifact_url': artifactUrl,
        'sha256': sha,
        'size_bytes': size,
        'package': pkg,
        if (signer != null) 'signer_sha256': signer,
        ...extraLatest,
      },
      if (history != null) 'history': history,
      ...extraTop,
    });

class Unroutable implements Exception {
  const Unroutable();
}

MockClient serving(String body, {int? artifactStatus = 200, int manifestStatus = 200}) =>
    MockClient((req) async {
      if (req.url.path.endsWith('.json')) return http.Response(body, manifestStatus);
      if (artifactStatus == null) throw const Unroutable();
      return http.Response('', artifactStatus);
    });

UpdateChecker checkerWith(http.Client c, {BuildIdentity id = running}) =>
    UpdateChecker(client: c, readIdentity: () async => id);

void main() {
  group('the announcement fires', () {
    test('newer versionCode + reachable artifact -> updateAvailable', () async {
      final r = await checkerWith(serving(manifestJson(versionCode: 11)))
          .check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(r.shouldAnnounce, isTrue);
      expect(r.available!.versionCode, 11);
      expect(r.available!.display, '0.0.2+11');
    });
  });

  group('NEGATIVE CONTROLS -- the half that proves anything', () {
    test('SAME versionCode -> says nothing', () async {
      final r = await checkerWith(serving(manifestJson(versionCode: 10)))
          .check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(r.shouldAnnounce, isFalse);
    });

    test('OLDER versionCode -> says nothing', () async {
      final r = await checkerWith(serving(manifestJson(versionCode: 3)))
          .check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(r.shouldAnnounce, isFalse);
    });

    test('our BYTES are the latest -> upToDate even when the code is higher '
        '(BIS: the sha is the only value that names one build)', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 99, sha: shaRunning)),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(r.runningIsPublished, isTrue);
      expect(r.shouldAnnounce, isFalse);
    });

    test('newer but artifact 404 -> NOT announced (PDS-3 retraction defect)',
        () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 11), artifactStatus: 404),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.newerButUnreachable);
      expect(r.shouldAnnounce, isFalse);
    });

    test('newer but artifact host unroutable -> NOT announced', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 11), artifactStatus: null),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.newerButUnreachable);
      expect(r.shouldAnnounce, isFalse);
    });

    test('manifest naming NO artifact -> noAnswer, never announced', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 11, artifactUrl: null)),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.noAnswer);
      expect(r.shouldAnnounce, isFalse);
    });

    test('DIFFERENT applicationId -> refused, never announced (it would '
        'install beside his app)', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 11, pkg: 'com.someone.else')),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.packageMismatch);
      expect(r.shouldAnnounce, isFalse);
    });

    test('missing signer_sha256 -> refused', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 11, signer: null)),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.noAnswer);
    });
  });

  group('offline is SILENT and HARMLESS -- constraint 1', () {
    test('a throwing client never throws out of check()', () async {
      final r = await checkerWith(MockClient((_) async => throw const Unroutable()))
          .check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.noAnswer);
      expect(r.shouldAnnounce, isFalse);
    });

    test('noAnswer is NOT upToDate -- the abstention survives (AAE-6)', () async {
      final r = await checkerWith(MockClient((_) async => throw const Unroutable()))
          .check(manifestUrl: manifestUrl);
      expect(r.status, isNot(UpdateCheckStatus.upToDate));
    });

    test('a hanging network resolves within the timeout', () async {
      final c = UpdateChecker(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return http.Response('', 200);
        }),
        readIdentity: () async => running,
        timeout: const Duration(milliseconds: 150),
      );
      final sw = Stopwatch()..start();
      final r = await c.check(manifestUrl: manifestUrl);
      sw.stop();
      expect(r.status, UpdateCheckStatus.noAnswer);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('non-200 manifest -> noAnswer', () async {
      final r = await checkerWith(serving('{}', manifestStatus: 503))
          .check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.noAnswer);
    });

    test('malformed body -> noAnswer', () async {
      final r = await checkerWith(serving('<html>not json</html>'))
          .check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.noAnswer);
    });

    test('UNKNOWN SCHEMA -> noAnswer, refuses forward', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 11, schema: 'sngnav-update-manifest/2')),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.noAnswer);
    });
  });

  group('the running build must know itself first', () {
    test('unknown identity -> unknownSelf, no comparison invented', () async {
      final r = await checkerWith(
        serving(manifestJson(versionCode: 99)),
        id: const BuildIdentity.unknown(),
      ).check(manifestUrl: manifestUrl);
      expect(r.status, UpdateCheckStatus.unknownSelf);
      expect(r.shouldAnnounce, isFalse);
    });

    test('BIS 3.2 -- the version pair alone is NOT an identity', () {
      const pairOnly = BuildIdentity(
        versionName: '0.0.2',
        versionCode: 10,
        packageName: kPkg,
      );
      expect(pairOnly.isKnown, isTrue);
      expect(pairOnly.isFullyIdentified, isFalse,
          reason: 'versionCode 2 named seven artifacts on 2026-09-24');
      expect(running.isFullyIdentified, isTrue);
      expect(running.display, contains('7129d4a4bb1b'));
      expect(running.display, contains('5794d0c'));
    });

    test('unknown display is honest', () {
      expect(const BuildIdentity.unknown().display, 'unknown');
      expect(const BuildIdentity.unknown().isFullyIdentified, isFalse);
      expect(const BuildIdentity.unknown().agreesWithCompiledVersionName, isNull);
    });
  });

  group('WDA ITEM 6 -- the channel carries VERSION FACTS AND NOTHING ELSE', () {
    test('a manifest stuffed with prose fields parses, and NOT ONE of them '
        'survives into anything a pixel can reach', () {
      final m = UpdateManifest.tryParse(manifestJson(
        versionCode: 11,
        extraLatest: const {
          'message': 'Tap here to claim your prize',
          'title': 'URGENT SECURITY UPDATE',
          'html': '<b>install now</b>',
          'notes': 'free text',
          'notes_url': 'https://evil.test/notes.md',
        },
        extraTop: const {
          'bounds': ['a sentence the guard writes for humans, not for the app'],
          'banner': 'another sentence',
        },
      ));
      expect(m, isNotNull);
      // The entry exposes exactly these, and there is nowhere to put a
      // sentence: a channel that CANNOT carry one cannot later carry one by
      // accident.
      final e = m!.latest;
      expect(e.versionCode, 11);
      expect(e.versionName, '0.0.2');
      expect(e.package, kPkg);
      expect(e.sha256, shaLatest);
      expect(e.signerSha256, shaSigner);
      expect(e.sizeBytes, 94671699);
      expect(e.artifactUrl.toString(), artifact);
      // Structural proof: the only free-form string reachable from the parsed
      // entry is the artifact URL, and it is scheme-restricted.
      expect(e.display, '0.0.2+11');
      expect(e.artifactUrl.scheme, anyOf('http', 'https'));
    });
  });

  group('manifest parse is strict', () {
    test('rejects a non-http artifact scheme', () {
      expect(
        UpdateManifest.tryParse(
            manifestJson(versionCode: 11, artifactUrl: 'file:///tmp/app.apk')),
        isNull,
      );
    });
    test('rejects a javascript: url', () {
      expect(
        UpdateManifest.tryParse(
            manifestJson(versionCode: 11, artifactUrl: 'javascript:alert(1)')),
        isNull,
      );
    });
    test('rejects a relative artifact url', () {
      expect(
        UpdateManifest.tryParse(
            manifestJson(versionCode: 11, artifactUrl: '/app.apk')),
        isNull,
      );
    });
    test('rejects a non-hex sha256', () {
      expect(
        UpdateManifest.tryParse(manifestJson(versionCode: 11, sha: 'not-a-hash')),
        isNull,
      );
    });
    test('parses the ledger rows', () {
      final m = UpdateManifest.tryParse(manifestJson(
        versionCode: 11,
        history: [
          {'versionCode': 11, 'sha256': shaLatest, 'versionName': '0.0.2'},
          {'versionCode': 10, 'sha256': shaRunning, 'versionName': '0.0.2'},
        ],
      ));
      expect(m!.history.length, 2);
      expect(m.history.map((r) => r.versionCode), containsAll(<int>[10, 11]));
    });
  });
}
