// The ANNOUNCING half of the update route, and -- load-bearing -- its NEGATIVE
// CONTROLS. A guard without a negative control proves nothing: a checker that
// announced unconditionally would pass every "it announced" test here.
//
// Schema under test is the one `scripts/pds_app_route_guard.py` EMITS
// (`sngnav-update-manifest/1`). The manifest is generated from the artifact,
// never hand-typed; this only parses it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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
  Object? manifestUrlField,
  Map<String, dynamic> extraLatest = const {},
  Map<String, dynamic> extraTop = const {},
}) =>
    jsonEncode({
      'schema': schema,
      // Top level and snake_case, where the emitter writes it.
      'manifest_url': ?manifestUrlField,
      'latest': {
        'versionName': versionName,
        'versionCode': versionCode,
        'artifact_url': ?artifactUrl,
        'sha256': sha,
        'size_bytes': size,
        'package': pkg,
        'signer_sha256': ?signer,
        ...extraLatest,
      },
      'history': ?history,
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

// ----- the stored address, on a real file in a per-test directory -----
//
// path_provider is pointed at a fresh temp directory by mocking its channel,
// the same channel test/render_see/* mock. The file name below is the one
// UpdateChecker reads; if the two ever drift apart, the "a stored https
// address is used" positive control fails, so the refusal tests beside it
// cannot pass by never reading the file.
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _storedName = 'update_manifest_url.txt';

/// Call inside a group: every test in that group gets its own support
/// directory. Returns a getter for the stored-address file in it.
File Function() useFreshSupportDir() {
  late Directory dir;
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('update_addr_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, (call) async => dir.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathChannel, null);
    if (dir.existsSync()) await dir.delete(recursive: true);
  });
  return () => File('${dir.path}/$_storedName');
}

/// What resolveManifestUrl must return when nothing usable is stored: the
/// compiled default when it is an https URL, and nothing when a build was made
/// with a non-https `--dart-define=SNGNAV_UPDATE_MANIFEST_URL=...`. The second
/// branch runs only under such a define; that is the one way to prove the gate
/// on the compiled default, since in a normal build the default is an https
/// literal and a missing gate looks identical.
final Uri? gatedDefault = () {
  final d = Uri.tryParse(UpdateChecker.defaultManifestUrl);
  return d != null && d.scheme == 'https' && d.host.isNotEmpty ? d : null;
}();

const oldAddr = 'https://example.test/update_manifest.json';
const newAddr = 'https://new.example.test/sngnav/update_manifest.json';
const otherAddr = 'https://other.example.test/update_manifest.json';

/// Serves exact URLs and throws for anything else. Every request is recorded
/// in [asked] as "METHOD url", in order.
MockClient hosts(
  Map<String, FutureOr<http.Response> Function()> byUrl,
  List<String> asked,
) =>
    MockClient((req) async {
      asked.add('${req.method} ${req.url}');
      final serve = byUrl['${req.url}'];
      if (serve == null) throw const Unroutable();
      return serve();
    });

http.Response ok(String body) => http.Response(body, 200);

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
      // entry is the artifact URL, and it is scheme-restricted. (This read
      // `anyOf('http', 'https')` until 2026-09-25, from when http was
      // accepted; the parser has refused http since, and an assertion that
      // admits what the code refuses would pass the regression it exists for.)
      expect(e.display, '0.0.2+11');
      expect(e.artifactUrl.scheme, 'https');
    });

    test('the ONE location fact, manifest_url, is held on the manifest and '
        'never on the version entry a surface reads', () {
      final m = UpdateManifest.tryParse(
        manifestJson(versionCode: 11, manifestUrlField: newAddr),
      )!;
      expect(m.manifestUrl, Uri.parse(newAddr));
      // The entry is unchanged by it: nothing a pixel reads carries it.
      expect(m.latest.display, '0.0.2+11');
      expect(m.latest.artifactUrl.toString(), artifact);
    });
  });

  group('manifest_url is read as the emitter writes it, and https only', () {
    test('snake_case at the top level is read', () {
      final m = UpdateManifest.tryParse(
        manifestJson(versionCode: 11, manifestUrlField: newAddr),
      )!;
      expect(m.manifestUrl, Uri.parse(newAddr));
      expect(m.manifestUrlRefused, isFalse);
    });

    test('camelCase `manifestUrl` is NOT read (the old comment cited it; the '
        'emitter never wrote it)', () {
      final m = UpdateManifest.tryParse(manifestJson(
        versionCode: 11,
        extraTop: const {'manifestUrl': newAddr},
      ))!;
      expect(m.manifestUrl, isNull);
      expect(m.manifestUrlRefused, isFalse);
    });

    test('absent -> null, and not a refusal', () {
      final m = UpdateManifest.tryParse(manifestJson(versionCode: 11))!;
      expect(m.manifestUrl, isNull);
      expect(m.manifestUrlRefused, isFalse);
    });

    for (final bad in <Object>[
      'http://new.example.test/update_manifest.json',
      'ftp://new.example.test/update_manifest.json',
      '/relative/update_manifest.json',
      'https:///no-host.json',
      42,
    ]) {
      test('$bad -> refused, and the version facts STILL answer (a wrong '
          'address must not silence news of a fix)', () {
        final m = UpdateManifest.tryParse(
          manifestJson(versionCode: 11, manifestUrlField: bad),
        );
        expect(m, isNotNull);
        expect(m!.manifestUrl, isNull);
        expect(m.manifestUrlRefused, isTrue);
        expect(m.latest.versionCode, 11);
      });
    }
  });

  group('manifest parse is strict', () {
    test('rejects a non-http artifact scheme', () {
      expect(
        UpdateManifest.tryParse(
            manifestJson(versionCode: 11, artifactUrl: 'file:///tmp/app.apk')),
        isNull,
      );
    });
    // file: and javascript: (above and below) carry NO HOST, so the host check
    // refuses them and they would pass with the scheme check gone or turned
    // into a blacklist of `http` (FBR, 2026-09-25: its mutant A1 survived).
    // ftp: has a host, so the scheme check is the ONLY thing that can refuse
    // it. This case is what proves that check.
    test('rejects an ftp:// artifact url, which has a host', () {
      expect(
        UpdateManifest.tryParse(manifestJson(
            versionCode: 11, artifactUrl: 'ftp://files.example.test/app.apk')),
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

  // ===== THE HOST THAT HAS NO LITERAL =====
  //
  // Every other egress in this app is an https literal in lib/, which is what
  // `tool/assert_disclosure_parity.sh` scans and what the data-safety
  // declaration's `grep -rn "http://" lib/` looked at. The artifact host is
  // neither: it arrives inside the fetched manifest. Both instruments are
  // structurally blind to it, so the https property is held by refusal in the
  // parser, and these tests are what prove the refusal actually refuses.
  group('a manifest may not send the app to a plaintext host', () {
    test('an http:// artifact URL is refused, and refused as noAnswer', () async {
      final res = await checkerWith(
        serving(manifestJson(
          versionCode: 99,
          artifactUrl: 'http://example.invalid/app-release.apk',
        )),
      ).check(manifestUrl: Uri.parse('https://h.invalid/m.json'));
      // The whole manifest fails to parse, so this is "we did not understand
      // the answer" -- never upToDate, and never an announcement.
      expect(res.status, UpdateCheckStatus.noAnswer);
      expect(res.shouldAnnounce, isFalse);
    });

    test('the SAME manifest over https announces — so the test above is '
        'measuring the scheme and nothing else', () async {
      final res = await checkerWith(
        serving(manifestJson(
          versionCode: 99,
          artifactUrl: 'https://example.invalid/app-release.apk',
        )),
      ).check(manifestUrl: Uri.parse('https://h.invalid/m.json'));
      expect(res.status, UpdateCheckStatus.updateAvailable);
      expect(res.shouldAnnounce, isTrue);
    });
  });

  // ===== THE PATH PRODUCTION TAKES: resolveManifestUrl() =====
  //
  // Every test above passes an explicit manifestUrl, which skips this. The app
  // does not: main.dart's _runUpdateCheck calls check() with no override, so
  // the address comes from resolveManifestUrl(). Until 2026-09-25 no test
  // called it (FBR: mutant A3, its https check deleted, survived).
  group('resolveManifestUrl -- the path production takes', () {
    final stored = useFreshSupportDir();

    test('a stored https address is used (positive control: the stored file '
        'is really read, so the refusals below are refusals)', () async {
      stored().writeAsStringSync('https://moved.example.test/m.json');
      expect(await UpdateChecker.resolveManifestUrl(),
          Uri.parse('https://moved.example.test/m.json'));
    });

    test('a stored http:// address is refused, and the compiled default is '
        'used instead', () async {
      stored().writeAsStringSync('http://plain.example.test/m.json');
      final r = await UpdateChecker.resolveManifestUrl();
      expect(r, isNot(Uri.parse('http://plain.example.test/m.json')));
      expect(r, gatedDefault);
    });

    test('with nothing stored, the compiled default passes the same https '
        'gate', () async {
      expect(stored().existsSync(), isFalse);
      expect(await UpdateChecker.resolveManifestUrl(), gatedDefault);
    });

    test('persistManifestUrl refuses an http:// address and writes nothing',
        () async {
      expect(
        await UpdateChecker.persistManifestUrl(
            Uri.parse('http://plain.example.test/m.json')),
        isFalse,
      );
      expect(stored().existsSync(), isFalse);
    });

    test('persistManifestUrl writes an https address, and resolveManifestUrl '
        'returns it', () async {
      expect(
          await UpdateChecker.persistManifestUrl(Uri.parse(newAddr)), isTrue);
      expect(await UpdateChecker.resolveManifestUrl(), Uri.parse(newAddr));
    });
  });

  // ===== THE ADDRESS READER =====
  //
  // A build that cannot learn a new manifest address can never be told where
  // its successor went (PDS, 2026-09-25). The reader stores a new address ONLY
  // after fetching it and finding that the manifest there names itself and
  // describes this app. Every test reads the REAL stored file afterwards.
  group('the address reader stores a new address only after going to see it',
      () {
    final stored = useFreshSupportDir();

    String atOld({Object? named, int code = 11, String pkg = kPkg}) =>
        manifestJson(versionCode: code, manifestUrlField: named, pkg: pkg);

    test('a new address whose manifest NAMES ITSELF: fetched, and only then '
        'stored; this check\'s answer is the old manifest\'s', () async {
      final asked = <String>[];
      bool? storedWhenNewWasFetched;
      final c = hosts({
        oldAddr: () => ok(atOld(named: newAddr)),
        newAddr: () {
          storedWhenNewWasFetched = stored().existsSync();
          return ok(atOld(named: newAddr));
        },
        artifact: () => ok(''),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.address, ManifestAddress.learned);
      expect(storedWhenNewWasFetched, isFalse,
          reason: 'nothing may be stored before the new address was seen');
      expect(stored().readAsStringSync(), newAddr);
      expect(await UpdateChecker.resolveManifestUrl(), Uri.parse(newAddr));
      expect(r.status, UpdateCheckStatus.updateAvailable);
      // The answer (manifest, then artifact probe) is fixed BEFORE the reader
      // goes anywhere.
      expect(asked, ['GET $oldAddr', 'HEAD $artifact', 'GET $newAddr']);
    });

    test('learned even when nothing newer exists: a holder who is up to date '
        'must still learn where the NEXT build will be announced', () async {
      final asked = <String>[];
      final c = hosts({
        oldAddr: () => ok(atOld(named: newAddr, code: 10)),
        newAddr: () => ok(atOld(named: newAddr, code: 10)),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(r.address, ManifestAddress.learned);
      expect(stored().readAsStringSync(), newAddr);
    });

    test('the NEXT check, on the production path, fetches the learned address '
        'and not the compiled default', () async {
      final asked = <String>[];
      const def = UpdateChecker.defaultManifestUrl;
      final checker = checkerWith(hosts({
        def: () => ok(atOld(named: newAddr)),
        newAddr: () => ok(atOld(named: newAddr)),
        artifact: () => ok(''),
      }, asked));
      final first = await checker.check();
      expect(first.address, ManifestAddress.learned);
      asked.clear();
      final second = await checker.check();
      expect(asked.first, 'GET $newAddr');
      expect(asked, isNot(contains('GET $def')));
      expect(second.address, ManifestAddress.unchanged,
          reason: 'the manifest there names the address it came from');
    }, skip: gatedDefault == null ? 'needs an https compiled default' : false);

    for (final (why, serveNew) in <(String, http.Response Function())>[
      ('answers 404', () => http.Response('', 404)),
      ('answers 200 with a body that is not a manifest',
          () => ok('<html>moved</html>')),
      ('serves a manifest that names ANOTHER address',
          () => ok(atOld(named: otherAddr))),
      ('serves a manifest that names no address', () => ok(atOld())),
      ('serves a manifest, naming itself, for a DIFFERENT app',
          () => ok(atOld(named: newAddr, pkg: 'com.someone.else'))),
    ]) {
      test('the new address $why: NOTHING is stored, the old address stays, '
          'and the news of a fix is not lost', () async {
        final asked = <String>[];
        final c = hosts({
          oldAddr: () => ok(atOld(named: newAddr)),
          newAddr: serveNew,
          artifact: () => ok(''),
        }, asked);
        final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
        expect(asked, contains('GET $newAddr'), reason: 'it went and looked');
        expect(r.address, ManifestAddress.unverified);
        expect(stored().existsSync(), isFalse);
        expect(r.status, UpdateCheckStatus.updateAvailable);
      });
    }

    test('an http:// new address is refused and NEVER FETCHED, not even to '
        'look', () async {
      final asked = <String>[];
      const plain = 'http://new.example.test/sngnav/update_manifest.json';
      final c = hosts({
        oldAddr: () => ok(atOld(named: plain)),
        plain: () => ok(atOld(named: plain)),
        artifact: () => ok(''),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.address, ManifestAddress.refused);
      expect(asked.where((a) => a.contains('http://')), isEmpty);
      expect(stored().existsSync(), isFalse);
      expect(r.status, UpdateCheckStatus.updateAvailable);
    });

    test('a manifest naming the address it came from: unchanged, one manifest '
        'fetch, nothing written', () async {
      final asked = <String>[];
      final c = hosts({
        oldAddr: () => ok(atOld(named: oldAddr)),
        artifact: () => ok(''),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.address, ManifestAddress.unchanged);
      expect(asked.where((a) => a.startsWith('GET ')), ['GET $oldAddr']);
      expect(stored().existsSync(), isFalse);
    });

    test('a manifest naming no address: unchanged, nothing written', () async {
      final asked = <String>[];
      final c = hosts({
        oldAddr: () => ok(atOld()),
        artifact: () => ok(''),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.address, ManifestAddress.unchanged);
      expect(stored().existsSync(), isFalse);
    });

    test('no answer from the old address: notAsked, never "unchanged", '
        'because nothing was read', () async {
      final asked = <String>[];
      final c = hosts({oldAddr: () => http.Response('', 503)}, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.status, UpdateCheckStatus.noAnswer);
      expect(r.address, ManifestAddress.notAsked);
    });

    test('a manifest for ANOTHER app that names a new address is never '
        'followed', () async {
      final asked = <String>[];
      final c = hosts({
        oldAddr: () => ok(atOld(named: newAddr, pkg: 'com.someone.else')),
        newAddr: () => ok(atOld(named: newAddr, pkg: 'com.someone.else')),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(r.status, UpdateCheckStatus.packageMismatch);
      expect(r.address, ManifestAddress.notAsked);
      expect(asked, isNot(contains('GET $newAddr')));
      expect(stored().existsSync(), isFalse);
    });

    test('a new address that HANGS costs the move, never the answer; and it '
        'writes nothing when it finally answers, after the check reported',
        () async {
      final asked = <String>[];
      final c = hosts({
        oldAddr: () => ok(atOld(named: newAddr)),
        newAddr: () async {
          await Future<void>.delayed(const Duration(seconds: 3));
          return ok(atOld(named: newAddr));
        },
        artifact: () => ok(''),
      }, asked);
      final checker = UpdateChecker(
        client: c,
        readIdentity: () async => running,
        timeout: const Duration(milliseconds: 300),
      );
      final sw = Stopwatch()..start();
      final r = await checker.check(manifestUrl: Uri.parse(oldAddr));
      sw.stop();
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(r.address, ManifestAddress.unverified);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'the check waited for the hanging address');
      // The slow address now answers, validly. The check has already said
      // "unverified", so nothing may be written behind it.
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(stored().existsSync(), isFalse,
          reason: 'a write landed after the check had reported');
    });

    test('verified, but the write fails: unsaved, never reported as learned',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathChannel, (call) async {
        throw PlatformException(code: 'no-support-dir');
      });
      final asked = <String>[];
      final c = hosts({
        oldAddr: () => ok(atOld(named: newAddr)),
        newAddr: () => ok(atOld(named: newAddr)),
        artifact: () => ok(''),
      }, asked);
      final r = await checkerWith(c).check(manifestUrl: Uri.parse(oldAddr));
      expect(asked, contains('GET $newAddr'));
      expect(r.address, ManifestAddress.unsaved);
      expect(r.status, UpdateCheckStatus.updateAvailable);
    });
  });

  // ===== "NEVER A DOWNLOAD" MUST HOLD ON THE HOST THAT IGNORES RANGE =====
  //
  // The privacy policy (flow 5) tells her the artifact step is an existence
  // check and never a download. The fallback for a host that refuses HEAD was
  // a one-byte ranged GET made with `get`, which reads the WHOLE body before
  // returning -- so a host that ignores Range made the app download the
  // artifact. These tests count what the checker pulls from such a host.
  group('the existence check never downloads the artifact', () {
    // COUNTED AFTER THE EVENT LOOP SETTLES (FBR, 2026-09-25). This test used to
    // count at the instant check() returned. A checker that listens to the
    // body and never cancels has pulled ONE chunk by then and pulls the other
    // 63 afterwards; FBR's mutant B2 did exactly that, and this test passed
    // it. It now waits for the host to stop producing, and also asserts the
    // body was cancelled: a checker that never touches the body pulls nothing
    // from this fake, but leaves a real socket open with its buffer filling
    // (mutant B3).
    test('HEAD refused (405) + Range ignored (200, whole body): reachable, '
        'the body is NOT drained, even after the event loop settles, and it '
        'was cancelled', () async {
      final host = _RangeIgnoringHost(manifestJson(versionCode: 11));
      final res = await checkerWith(host).check(manifestUrl: manifestUrl);
      final atReturn = host.chunksServedToAListener;
      await host.settled();
      expect(res.status, UpdateCheckStatus.updateAvailable,
          reason: 'a 200 to the ranged GET means the artifact is there');
      expect(host.headSeen, isTrue,
          reason: 'HEAD is still asked first; this test must reach the '
              'fallback, or it measures nothing');
      expect(host.rangedGetSeen, isTrue);
      expect(host.chunksServedToAListener, lessThan(_RangeIgnoringHost.chunks),
          reason: 'the checker read the whole artifact: that is a download, '
              'and the policy says there is none');
      expect(host.chunksServedToAListener, lessThanOrEqualTo(1),
          reason: 'counted after the host stopped; $atReturn at return');
      expect(host.bodyCancelled, isTrue,
          reason: 'an uncancelled body keeps the transfer open after check() '
              'has returned');
    });

    test('the same host, answering 404 to the ranged GET: unreachable, and '
        'nothing announced -- so the test above is measuring the body and '
        'not a checker that says yes to everything', () async {
      final host = _RangeIgnoringHost(manifestJson(versionCode: 11),
          rangedStatus: 404);
      final res = await checkerWith(host).check(manifestUrl: manifestUrl);
      expect(res.status, UpdateCheckStatus.newerButUnreachable);
      expect(res.shouldAnnounce, isFalse);
    });

    // Mutant B4 (FBR): with the predicate loosened to "!= 404", a ranged
    // answer of 403, 410 or 5xx was announced, and every test passed, because
    // 404 was the only refusal tested. Each is tested now.
    for (final s in [403, 410, 500, 503]) {
      test('the same host, answering $s to the ranged GET: unreachable, not '
          'announced, and its body not drained either', () async {
        final host = _RangeIgnoringHost(manifestJson(versionCode: 11),
            rangedStatus: s);
        final res = await checkerWith(host).check(manifestUrl: manifestUrl);
        await host.settled();
        expect(host.rangedGetSeen, isTrue,
            reason: 'the refusal must come from the ranged GET');
        expect(res.status, UpdateCheckStatus.newerButUnreachable);
        expect(res.shouldAnnounce, isFalse);
        expect(host.chunksServedToAListener, lessThanOrEqualTo(1));
      });
    }

    test('a host that honours Range answers 206: reachable (the positive the '
        'refusals above are measured against)', () async {
      final host = _RangeIgnoringHost(manifestJson(versionCode: 11),
          rangedStatus: 206);
      final res = await checkerWith(host).check(manifestUrl: manifestUrl);
      expect(res.status, UpdateCheckStatus.updateAvailable);
    });

    // Mutant B5 (FBR) dropped the 403 leg of the fallback and survived. FBR
    // rightly called it the safe direction for a false announcement; it is
    // not safe for reach. On a host that answers HEAD with 403, a real fix
    // would never be announced, and nothing would say so.
    test('HEAD refused with 403 also falls back to the ranged GET, so a fix '
        'on such a host is still announced', () async {
      final host = _RangeIgnoringHost(manifestJson(versionCode: 11),
          headStatus: 403);
      final res = await checkerWith(host).check(manifestUrl: manifestUrl);
      expect(host.headSeen, isTrue);
      expect(host.rangedGetSeen, isTrue);
      expect(res.status, UpdateCheckStatus.updateAvailable);
    });
  });
}

/// A host that refuses HEAD and IGNORES Range: HEAD is answered [headStatus],
/// the ranged GET [rangedStatus] with the entire artifact body, streamed in
/// [chunks] pieces produced only while someone is listening.
/// [chunksServedToAListener] is how much of the artifact the client actually
/// pulled; read it after [settled], never at the instant check() returns.
class _RangeIgnoringHost extends http.BaseClient {
  _RangeIgnoringHost(
    this.manifestBody, {
    this.rangedStatus = 200,
    this.headStatus = 405,
  });

  static const int chunks = 64;
  static const int chunkBytes = 1024;

  final String manifestBody;
  final int rangedStatus;
  final int headStatus;
  bool headSeen = false;
  bool rangedGetSeen = false;
  int chunksServedToAListener = 0;

  /// True once the client cancelled its subscription to the artifact body.
  bool bodyCancelled = false;

  final Completer<void> _producerStopped = Completer<void>();

  /// Resolves when this host has stopped producing the body (the client
  /// cancelled, or every chunk was served), or after 500 ms when nobody ever
  /// listened. The instant check() returns is before the next timer tick, so
  /// a checker still listening in the background would look like one that
  /// had stopped.
  Future<void> settled() => Future.any([
        _producerStopped.future,
        Future<void>.delayed(const Duration(milliseconds: 500)),
      ]);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('.json')) {
      final bytes = utf8.encode(manifestBody);
      return http.StreamedResponse(Stream.value(bytes), 200,
          contentLength: bytes.length);
    }
    if (request.method == 'HEAD') {
      headSeen = true;
      return http.StreamedResponse(const Stream.empty(), headStatus);
    }
    rangedGetSeen = request.headers['Range'] == 'bytes=0-0';
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onCancel: () => bodyCancelled = true,
      onListen: () async {
        for (var i = 0; i < chunks; i++) {
          if (!body.hasListener) break;
          body.add(List<int>.filled(chunkBytes, 0));
          chunksServedToAListener++;
          await Future<void>.delayed(Duration.zero);
        }
        if (!_producerStopped.isCompleted) _producerStopped.complete();
        await body.close();
      },
    );
    return http.StreamedResponse(body.stream, rangedStatus,
        contentLength: chunks * chunkBytes);
  }
}
