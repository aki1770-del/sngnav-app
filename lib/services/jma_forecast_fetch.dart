/// JMA FORECAST fetch — the forward validity grid we were never reading.
///
/// The app already talks to JMA, but ONLY to the AMeDAS OBSERVATION endpoint
/// (`lib/jma_fetch.dart` → `bosai/amedas/…`), which answers "what is the road
/// doing right now". That answer decays; it is the reading that expires at 60
/// minutes and leaves HER with silence at T+90.
///
/// JMA ALSO publishes a FORWARD FORECAST with its own explicit interval
/// boundaries, and we had never fetched it. MEASURED LIVE 2026-07-12 from
/// `https://www.jma.go.jp/bosai/forecast/data/forecast/050000.json` (Akita),
/// reportDatetime `2026-07-12T17:00:00+09:00`, verbatim:
///
///   timeSeries[0].timeDefines = [
///     "2026-07-12T17:00:00+09:00",
///     "2026-07-13T00:00:00+09:00",
///     "2026-07-14T00:00:00+09:00" ]
///   timeSeries[0].areas[0].weathers = [
///     "雨　所により　雷を伴い　激しく　降る",
///     "くもり　明け方　まで　雨",
///     "くもり　一時　雨" ]
///
/// `timeDefines[i]` are THE PUBLISHER'S OWN interval boundaries. So the forecast
/// text at index `i` is declared valid for `[timeDefines[i], timeDefines[i+1])`
/// — a window with a publisher-declared START and a publisher-declared END. That
/// is precisely the publisher-declared validity NDI's Andon requires, and it is
/// the memory that survives the dead zone.
///
/// ── TWO REFUSALS, BOTH DELIBERATE ────────────────────────────────────────────
///
/// (1) THE UNBOUNDED TAIL IS DROPPED. The LAST entry of every series has NO
///     successor, so its end is NOT publisher-declared. We could invent one
///     ("+24h" — exactly the `effective + 1h` fabrication that broke MET
///     Norway's `expires`). We do not. It is dropped. The Akita payload above
///     therefore yields TWO usable intervals, not three. We would rather carry
///     less than carry a guess she cannot distinguish from a promise.
///
/// (2) NO CODE-TABLE GUESSING. Snow is detected by 雪 appearing in the
///     publisher's OWN verbatim `weathers` text — not by a JMA telop-code table
///     reconstructed from memory. 吹雪 (blizzard) and 大雪 both contain 雪. A
///     code table I have not read at the source is a fabrication with a number
///     in it.
///
/// LIMITATION, RECORDED. We extract ONLY snow-class hazards, ONLY from the
/// `weathers` series. We do NOT derive black ice from the `tempsMin`/`tempsMax`
/// series: those are POINT forecasts at single instants (00:00, 09:00), not
/// interval-valid values, and turning them into a road-surface freezing
/// prediction is a SYNTHESIS — the very thing this layer exists to refuse. A
/// forecast-grounded black-ice window is real future work and is NOT claimed.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'forecast_validity.dart';

/// JMA forecast area code for Akita prefecture (秋田県).
const String akitaForecastAreaCode = '050000';

/// Result of a forecast fetch: hazards, or an explicit failure. Never a silent
/// empty — an empty hazard list from a SUCCESSFUL fetch means "the publisher
/// forecasts no snow", which is a fact; a failure means "we do not know", which
/// is not.
sealed class JmaForecastResult {
  const JmaForecastResult();
}

class JmaForecastSuccess extends JmaForecastResult {
  const JmaForecastSuccess({required this.hazards, required this.issuedAt});

  /// Publisher-declared, publisher-bounded hazards. May be empty (= no snow
  /// forecast), which is itself knowledge.
  final List<ForecastHazard> hazards;
  final DateTime issuedAt;
}

class JmaForecastFailure extends JmaForecastResult {
  const JmaForecastFailure(this.reason);
  final String reason;
}

/// Parse a JMA `bosai/forecast` payload into publisher-bounded snow hazards.
///
/// Pure: no I/O. This is the function the tests drive against the REAL captured
/// payload — a parser tested only against a fixture I wrote myself would be a
/// test authored by the bug.
JmaForecastResult parseJmaForecast(String body) {
  final Object? decoded;
  try {
    decoded = json.decode(body);
  } catch (e) {
    return JmaForecastFailure('parse: $e');
  }
  if (decoded is! List || decoded.isEmpty) {
    return const JmaForecastFailure('payload is not a non-empty JSON array');
  }

  final head = decoded.first;
  if (head is! Map<String, dynamic>) {
    return const JmaForecastFailure('payload[0] is not an object');
  }

  final issuedAt = DateTime.tryParse(head['reportDatetime']?.toString() ?? '');
  if (issuedAt == null) {
    return const JmaForecastFailure('no parseable reportDatetime');
  }
  final office = head['publishingOffice']?.toString() ?? 'JMA';

  final series = head['timeSeries'];
  if (series is! List) {
    return const JmaForecastFailure('no timeSeries');
  }

  final hazards = <ForecastHazard>[];

  for (final s in series) {
    if (s is! Map<String, dynamic>) continue;
    final defines = s['timeDefines'];
    final areas = s['areas'];
    if (defines is! List || areas is! List) continue;

    // Only the series that carries the publisher's forecast TEXT.
    final instants = <DateTime>[];
    var malformed = false;
    for (final d in defines) {
      final t = DateTime.tryParse(d.toString());
      if (t == null) {
        malformed = true;
        break;
      }
      instants.add(t.toUtc());
    }
    if (malformed || instants.length < 2) continue;

    for (final a in areas) {
      if (a is! Map<String, dynamic>) continue;
      final weathers = a['weathers'];
      if (weathers is! List) continue;
      final areaName =
          (a['area'] is Map ? (a['area'] as Map)['name'] : null)?.toString() ??
              '';

      // THE BOUNDED PREFIX ONLY. `instants.length - 1` — the final entry has no
      // publisher-declared end and is DROPPED, never extended by a guess.
      final bounded = instants.length - 1;
      for (var i = 0; i < bounded && i < weathers.length; i++) {
        final text = weathers[i]?.toString() ?? '';
        if (!text.contains('雪')) continue; // publisher's own word, verbatim.
        hazards.add(ForecastHazard(
          kind: ForecastHazardKind.snow,
          window: ValidityWindow(
            start: instants[i],
            end: instants[i + 1],
            // Both boundaries are JMA's own timeDefines. Nothing derived.
            provenance: ValidityProvenance.publisherDeclared,
          ),
          publisherText: text,
          source: 'JMA $office',
          issuedAt: issuedAt.toUtc(),
          areaName: areaName,
        ));
      }
    }
  }

  return JmaForecastSuccess(hazards: hazards, issuedAt: issuedAt.toUtc());
}

/// Fetch the JMA forward forecast for [areaCode]. Network — called at PLAN time
/// (when she still has a network), never in the dead zone.
Future<JmaForecastResult> fetchJmaForecast({
  String areaCode = akitaForecastAreaCode,
  http.Client? client,
  String? userAgent,
}) async {
  final c = client ?? http.Client();
  try {
    final resp = await c
        .get(
          Uri.parse(
            'https://www.jma.go.jp/bosai/forecast/data/forecast/$areaCode.json',
          ),
          headers: userAgent == null ? null : {'User-Agent': userAgent},
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      return JmaForecastFailure('forecast HTTP ${resp.statusCode}');
    }
    return parseJmaForecast(utf8.decode(resp.bodyBytes));
  } catch (e) {
    return JmaForecastFailure('exception: $e');
  } finally {
    if (client == null) c.close();
  }
}
