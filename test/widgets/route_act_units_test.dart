/// The parts of the route act that do not need the whole app: where route
/// setting is open, which points a tap on the act's map chooses, and a tile
/// provider the act's map cannot close.
///
/// Why the last one exists. flutter_map 8.3.2 disposes a tile layer's provider
/// when the layer is disposed (`tile_layer.dart:517`). Her map's offline
/// provider disposes its network fallback when it is disposed (offline_tiles
/// 0.5.7, `offline_tile_provider.dart:73-75`), which closes that fallback's
/// HTTP client (`network/tile_provider.dart:129-131`). Handed straight to the
/// act's map, her provider would be disposed when the act closed, and her map
/// could no longer fetch a tile the bundled archive does not hold.
library;

import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_app/route_act.dart';

/// A 1x1 PNG.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

class _RecordingProvider extends TileProvider {
  var disposed = false;
  var images = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    images++;
    return MemoryImage(_png);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Widget _mapWith(TileProvider provider) => MaterialApp(
      home: SizedBox(
        width: 200,
        height: 200,
        child: FlutterMap(
          options: const MapOptions(
              initialCenter: LatLng(39.7167, 140.0983), initialZoom: 12),
          children: [
            TileLayer(urlTemplate: 'unused/{z}/{x}/{y}', tileProvider: provider),
          ],
        ),
      ),
    );

void main() {
  group('where route setting is open', () {
    testWidgets('a native Linux build is the IVI: closed; anything else has no '
        'motion signal: open through the act', (tester) async {
      final host = routeSettingHost();
      if (defaultTargetPlatform == TargetPlatform.linux) {
        expect(host, RouteSettingHost.iviWithoutVehicleSignal);
        expect(routeSettingOpen(host), isFalse);
      } else {
        expect(host, RouteSettingHost.noMotionSignal);
        expect(routeSettingOpen(host), isTrue);
      }
    }, variant: TargetPlatformVariant.all());
  });

  group('a tap on the act\'s map', () {
    const a = LatLng(39.70, 140.09);
    const b = LatLng(39.72, 140.12);
    const c = LatLng(39.75, 140.15);

    test('chooses A first, then B', () {
      expect(routeActPointsAfterTap(tap: a), (a, null));
      expect(routeActPointsAfterTap(origin: a, tap: b), (a, b));
    });

    test('with A and B chosen, chooses nothing', () {
      expect(routeActPointsAfterTap(origin: a, destination: b, tap: c), (a, b));
    });
  });

  group('a borrowed tile provider', () {
    testWidgets('CONTROL: a tile layer disposes the provider it is given',
        (tester) async {
      final owner = _RecordingProvider();
      await tester.pumpWidget(_mapWith(owner));
      await tester.pump();
      expect(owner.images, greaterThan(0), reason: 'precondition: tiles asked');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owner.disposed, isTrue,
          reason: 'flutter_map disposes the provider with the layer');
    });

    testWidgets('a layer given the borrowed view asks the owner for tiles, and '
        'closes nothing of the owner\'s', (tester) async {
      final owner = _RecordingProvider();
      await tester.pumpWidget(_mapWith(BorrowedTileProvider(owner)));
      await tester.pump();
      expect(owner.images, greaterThan(0), reason: 'tiles come from the owner');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(owner.disposed, isFalse);
    });
  });
}
