/// Slice 1 map widget — Akita-shi centered, JMA station 32402 marker.
///
/// Uses `flutter_map` directly (OSM tiles, no API key). Future slices may
/// add `map_viewport_bloc` from the SNGNav package family when:
/// - GPS following is wired (CameraMode.follow / freeLook auto-return)
/// - Multiple layers compose (hazard / weather / safety / route overlays)
///
/// Slice 1 doesn't need that ceremony. V65 sekishō-idai.
///
/// HER-trace: HER's mother in Akita needs to SEE WHERE SHE IS before any
/// other navigation feature. This map renders that. The JMA station marker
/// shows where the temperature reading on the JMA panel comes from in
/// physical space — closing the loop between data and place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Akita-shi JMA AMeDAS station (32402) location, per
/// `https://www.jma.go.jp/bosai/amedas/const/amedastable.json`.
const LatLng akitaStation = LatLng(39.7167, 140.0983);

class AkitaMap extends StatelessWidget {
  const AkitaMap({super.key, this.height = 280});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: const MapOptions(
            initialCenter: akitaStation,
            initialZoom: 12,
            minZoom: 5,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dev.aki1770del.sngnav_app',
              maxZoom: 19,
              // OSM tile-usage policy requires a meaningful user-agent.
            ),
            const MarkerLayer(
              markers: [
                Marker(
                  point: akitaStation,
                  width: 60,
                  height: 60,
                  child: _StationMarker(),
                ),
              ],
            ),
            const _AttributionBar(),
          ],
        ),
      ),
    );
  }
}

class _StationMarker extends StatelessWidget {
  const _StationMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blueGrey.shade700, width: 1),
          ),
          child: Text(
            '秋田',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey.shade900,
            ),
          ),
        ),
        Icon(Icons.place, color: Colors.red.shade700, size: 28),
      ],
    );
  }
}

class _AttributionBar extends StatelessWidget {
  const _AttributionBar();

  @override
  Widget build(BuildContext context) {
    // OSM tile-usage policy + attribution requirement.
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: Colors.white.withValues(alpha: 0.7),
        child: const Text(
          '© OpenStreetMap contributors',
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
