/// S8 — the AMeDAS QC flag is honoured: JMA publishes each measurement as
/// `[value, qualityFlag]`, and only flag 0 (normal) is a measurement. A
/// non-zero / missing / malformed flag means JMA's own quality control
/// rejected the reading — relaying it verbatim would present a rejected
/// value as fact. Rejected → the field is ABSENT (null = unknown), and the
/// downstream watches abstain honestly (they already treat null as unknown).
/// Mirrors pretrip_source_jma's flag-0-only discipline.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sngnav_app/jma_fetch.dart';

/// A mock JMA endpoint: latest_time.txt + one point bucket file whose single
/// record is [record].
MockClient _jmaMock(Map<String, dynamic> record) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('latest_time.txt')) {
      return http.Response('2026-07-15T10:30:00+09:00', 200);
    }
    if (path.contains('/point/')) {
      // Bucket for 10:30 JST is 09; one record at 10:30.
      return http.Response(json.encode({'20260715103000': record}), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  test('QC flag 0 (normal) readings are relayed as measurements', () async {
    final result = await fetchLatestObservation(
      client: _jmaMock({
        'temp': [1.5, 0],
        'humidity': [63, 0],
        'wind': [3.4, 0],
        'snow': [12, 0],
        'precipitation10m': [0.0, 0],
        'visibility': [20000, 0],
      }),
    );
    expect(result, isA<JmaSuccess>());
    final obs = (result as JmaSuccess).observation;
    expect(obs.temperatureCelsius, 1.5);
    expect(obs.humidityPercent, 63);
    expect(obs.windMetersPerSecond, 3.4);
    expect(obs.snowDepthCm, 12);
    expect(obs.precipitation10mMm, 0.0);
    expect(obs.visibilityMeters, 20000);
  });

  test('non-zero QC flag → the field is absent (unknown), never a value',
      () async {
    final result = await fetchLatestObservation(
      client: _jmaMock({
        'temp': [1.5, 1], // QC-rejected
        'humidity': [63, 2], // QC-rejected
        'wind': [3.4, 0], // normal
        'snow': [12, 4], // QC-rejected
        'precipitation10m': [0.0, 0], // normal — measured dry stays measured
        'visibility': [20000, 3], // QC-rejected
      }),
    );
    expect(result, isA<JmaSuccess>());
    final obs = (result as JmaSuccess).observation;
    expect(obs.temperatureCelsius, isNull);
    expect(obs.humidityPercent, isNull);
    expect(obs.windMetersPerSecond, 3.4);
    expect(obs.snowDepthCm, isNull);
    expect(obs.precipitation10mMm, 0.0);
    expect(obs.visibilityMeters, isNull);
  });

  test('missing / malformed flag or value → absent, never a guess', () async {
    final result = await fetchLatestObservation(
      client: _jmaMock({
        'temp': [1.5], // no flag at all
        'humidity': [null, 0], // null value
        'wind': [3.4, null], // null flag — cannot verify QC passed
        'snow': 'garbage', // not a list
        // precipitation10m absent entirely
        'visibility': [20000, 0],
      }),
    );
    expect(result, isA<JmaSuccess>());
    final obs = (result as JmaSuccess).observation;
    expect(obs.temperatureCelsius, isNull);
    expect(obs.humidityPercent, isNull);
    expect(obs.windMetersPerSecond, isNull);
    expect(obs.snowDepthCm, isNull);
    expect(obs.precipitation10mMm, isNull);
    expect(obs.visibilityMeters, 20000);
  });
}
