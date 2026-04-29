// Widget tests for the CorridorRow used by main.dart's corridor table.
//
// These exercise the row in isolation — no network, no full app pump —
// because that is the point of having extracted CorridorRow as its own
// public widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_app/corridor_row.dart';
import 'package:sngnav_app/jma_fetch.dart';

JmaObservation _obs({
  required String name,
  double? temp,
  double? snow,
  double? wind,
  String observed = '20260428215000',
}) {
  return JmaObservation(
    stationId: 'X',
    stationName: name,
    temperatureCelsius: temp,
    humidityPercent: 70,
    windMetersPerSecond: wind,
    snowDepthCm: snow,
    visibilityMeters: null,
    observedAtJstKey: observed,
    fetchedAt: DateTime(2026, 4, 28, 22, 0),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: child),
  ));
}

void main() {
  testWidgets('success row shows station name + descriptor + values', (
    tester,
  ) async {
    await _pump(
      tester,
      CorridorRow(
        result: JmaSuccess(_obs(name: '湯沢', temp: -3.2, snow: 12, wind: 1.4)),
        descriptor: '南・山間',
        tempMin: -8.0,
        tempMax: 0.0,
      ),
    );
    expect(find.text('湯沢'), findsOneWidget);
    expect(find.text('南・山間'), findsOneWidget);
    expect(find.text('-3.2 °C'), findsOneWidget);
    expect(find.text('12 cm'), findsOneWidget);
    expect(find.text('1.4 m/s'), findsOneWidget);
    expect(find.text('21:50 JST'), findsOneWidget);
  });

  testWidgets('descriptor is rendered in Japanese (V96 cohort fit)', (
    tester,
  ) async {
    // The named first customer reads kanji natively. The descriptor
    // beneath the station name must not switch script mid-row.
    await _pump(
      tester,
      CorridorRow(
        result: JmaSuccess(_obs(name: '男鹿', temp: 1.0)),
        descriptor: '北・海沿い',
        tempMin: -5.0,
        tempMax: 5.0,
      ),
    );
    expect(find.text('北・海沿い'), findsOneWidget);
    expect(find.textContaining('coast'), findsNothing);
    expect(find.textContaining('north'), findsNothing);
  });

  testWidgets('null measurements render em-dash, not hidden', (tester) async {
    await _pump(
      tester,
      CorridorRow(
        result: JmaSuccess(_obs(name: '秋田')),
        descriptor: '市街地',
        tempMin: null,
        tempMax: null,
      ),
    );
    // One em-dash per missing measurement (snow, temp, wind).
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets(
      'gradient short-circuits when only one station has a temperature', (
    tester,
  ) async {
    // tempMin == tempMax means N=1 resolved temp. The cell must not
    // paint a gradient color in that case (no false signal from one
    // data point).
    await _pump(
      tester,
      CorridorRow(
        result: JmaSuccess(_obs(name: '秋田', temp: -2.0)),
        descriptor: '市街地',
        tempMin: -2.0,
        tempMax: -2.0,
      ),
    );
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('-2.0 °C'), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });

  testWidgets('coldest station carries a screen-reader endpoint label', (
    tester,
  ) async {
    await _pump(
      tester,
      CorridorRow(
        result: JmaSuccess(_obs(name: '湯沢', temp: -8.0)),
        descriptor: '南・山間',
        tempMin: -8.0,
        tempMax: 0.0,
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp(r'coldest in corridor')),
      findsOneWidget,
    );
  });

  testWidgets('warmest station carries a screen-reader endpoint label', (
    tester,
  ) async {
    await _pump(
      tester,
      CorridorRow(
        result: JmaSuccess(_obs(name: '男鹿', temp: 0.0)),
        descriptor: '北・海沿い',
        tempMin: -8.0,
        tempMax: 0.0,
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp(r'warmest in corridor')),
      findsOneWidget,
    );
  });

  testWidgets('failure row preserves column structure (5 cells)', (
    tester,
  ) async {
    // The visual rhythm of the table must not collapse when one
    // station fails — data cells render em-dash, not blank.
    await _pump(
      tester,
      const CorridorRow(
        result: JmaFailure('exception: SocketException'),
        descriptor: '南・内陸',
        tempMin: null,
        tempMax: null,
      ),
    );
    expect(find.textContaining('南・内陸'), findsOneWidget);
    expect(find.textContaining('fetch failed'), findsOneWidget);
    // Snow + Temp + Wind + Observed cells all render an em-dash.
    expect(find.text('—'), findsNWidgets(4));
  });
}
