/// Destination B is not drawn in the Akita station pin's red.
///
/// Why this test exists. Read on 6a72b41: B's disc was `Colors.red.shade700`,
/// the exact colour of the station pin beside it on the same map, so a glance
/// at red could take her destination for the station or the station for her
/// destination. A and B also differ by their letters; this test holds the
/// colour, and keeps B's hue away from A's green too.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/akita_map.dart';
import 'package:sngnav_app/l10n/app_localizations.dart';

final _blankTile = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, //
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

class _BlankTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_blankTile);
}

/// The smaller angle between two hues, in degrees.
double _hueGap(Color a, Color b) {
  final d = (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs();
  return d > 180 ? 360 - d : d;
}

void main() {
  testWidgets('B\'s disc is not the station pin\'s red, nor A\'s green',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            child: AkitaMap(
              height: 340,
              baseTileProvider: _BlankTileProvider(),
              origin: const LatLng(39.715, 140.090),
              destination: const LatLng(39.722, 140.110),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final station = tester.widget<Icon>(find.byIcon(Icons.place)).color;
    expect(station, isNotNull, reason: 'precondition: the station pin');

    Color disc(String letter) {
      final container = find.ancestor(
        of: find.text(letter),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle),
      );
      expect(container, findsWidgets, reason: 'precondition: $letter is drawn');
      return (tester.widget<Container>(container.first).decoration
              as BoxDecoration)
          .color!;
    }

    final a = disc('A');
    final b = disc('B');
    expect(b, isNot(station), reason: 'B $b, station $station');
    expect(_hueGap(b, station!), greaterThanOrEqualTo(60),
        reason: 'B $b against the station $station');
    expect(_hueGap(b, a), greaterThanOrEqualTo(60),
        reason: 'B $b against A $a');
  });
}
