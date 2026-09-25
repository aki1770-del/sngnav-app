/// Every JMA request carries the app's User-Agent (2026-09-25).
///
/// WHY: the privacy policy says JMA requests carry a User-Agent naming this
/// app's public repository, so JMA can do rate-limit accounting and reach a
/// security contact. An audit on 2026-09-25 measured that false for five of
/// the six AMeDAS requests made at launch: `fetchCorridorObservations` passed
/// no User-Agent, so dart:io's default went out. The fetch function honoured
/// the header; the CALL SITE dropped it. So this file checks both: the
/// function passes it to every request, and every JMA call site in lib/ hands
/// it the app's.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/jma_fetch.dart';

void main() {
  test('every corridor station request carries the User-Agent it is given',
      () async {
    final seen = <String, String?>{};
    final mock = MockClient((request) async {
      seen[request.url.toString()] = request.headers['user-agent'];
      if (request.url.path.endsWith('latest_time.txt')) {
        return http.Response('2026-07-15T10:30:00+09:00', 200);
      }
      return http.Response('{}', 200);
    });

    await fetchCorridorObservations(client: mock, userAgent: 'sngnav-test/1');

    // Five stations, two requests each: latest_time.txt (one URL, asked five
    // times) and one point file per station.
    expect(seen.length, 6);
    expect(seen.values.toSet(), {'sngnav-test/1'},
        reason: 'every request must carry the User-Agent the caller passed');
  });

  test('NEGATIVE CONTROL: without one, no User-Agent of ours is sent', () async {
    final uas = <String?>[];
    final mock = MockClient((request) async {
      uas.add(request.headers['user-agent']);
      return http.Response('not found', 404);
    });
    await fetchCorridorObservations(client: mock);
    expect(uas, isNotEmpty);
    expect(uas.every((ua) => ua == null), isTrue,
        reason: 'this is the shape the audit measured; the call-site test '
            'below is what keeps the app from sending it');
  });

  test('every JMA call site in lib/ hands over the app User-Agent', () {
    // The three JMA fetchers, and the only argument forms that satisfy the
    // policy's sentence. fetchLatestObservation is also called INSIDE
    // fetchCorridorObservations, where it forwards the caller's value.
    final calls = RegExp(
        r'(fetchLatestObservation|fetchCorridorObservations|fetchJmaForecast)'
        r'\(([^;]*?)\)',
        dotAll: true);
    final offenders = <String>[];
    var checked = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in calls.allMatches(src)) {
        final before = src.substring(0, m.start);
        // Skip declarations (`Future<List<X>> fetchX({`): only calls count.
        // The test is on the whole line, because a call can follow `=>`,
        // which also ends in `>`.
        if (RegExp(r'^\s*Future<.*>\s*$').hasMatch(before.split('\n').last)) {
          continue;
        }
        final args = m.group(2)!;
        final forwards = f.path.endsWith('jma_fetch.dart') &&
            args.contains('userAgent: userAgent');
        final app = args.contains('userAgent: kSngnavAppUserAgent');
        checked++;
        if (!forwards && !app) {
          final line = '\n'.allMatches(before).length + 1;
          offenders.add('${f.path}:$line ${m.group(1)}(${args.trim()})');
        }
      }
    }
    expect(checked, greaterThanOrEqualTo(4),
        reason: 'the scan must actually find the call sites it guards '
            '(_refreshJma, _refreshCorridor, _captureTripHazardMemory, and the '
            'forward inside fetchCorridorObservations)');
    expect(offenders, isEmpty,
        reason: 'a JMA request without the app User-Agent makes the privacy '
            "policy's first flow false");
  });
}
