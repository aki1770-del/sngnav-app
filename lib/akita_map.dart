/// Slice 1+2b map widget — Akita-shi centered, JMA station marker,
/// tap-to-set origin+destination, route polyline render.
///
/// Slice 1: render the map + station marker.
/// Slice 2b: accept origin/destination/route from parent; emit taps so
/// parent can drive an OSRM call. The widget itself stays presentational —
/// no routing state lives here.
///
/// HER-trace: HER's mother in Akita needs to SEE WHERE SHE IS, then SEE
/// WHETHER A ROAD EXISTS to where she wants to go. Slice 1 answered the
/// first; Slice 2b answers the second. Snow-aware routing is a later slice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const LatLng akitaStation = LatLng(39.7167, 140.0983);

class AkitaMap extends StatelessWidget {
  const AkitaMap({
    super.key,
    this.height = 320,
    this.origin,
    this.destination,
    this.routePoints = const [],
    this.onTap,
    this.herPosition,
    this.herAccuracyMeters,
    this.isHerPositionMock = false,
  });

  final double height;
  final LatLng? origin;
  final LatLng? destination;
  final List<LatLng> routePoints;
  final void Function(LatLng)? onTap;
  final LatLng? herPosition;
  final double? herAccuracyMeters;
  final bool isHerPositionMock;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: akitaStation,
            initialZoom: 12,
            minZoom: 5,
            maxZoom: 18,
            onTap: onTap == null ? null : (_, latlng) => onTap!(latlng),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dev.aki1770del.sngnav_app',
              maxZoom: 19,
            ),
            if (herPosition != null && herAccuracyMeters != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: herPosition!,
                    radius: herAccuracyMeters!,
                    useRadiusInMeter: true,
                    color: (isHerPositionMock ? Colors.amber : Colors.blue)
                        .withValues(alpha: 0.12),
                    borderColor: (isHerPositionMock ? Colors.amber : Colors.blue)
                        .withValues(alpha: 0.45),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            if (routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 5,
                    color: Colors.blue.shade700,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                const Marker(
                  point: akitaStation,
                  width: 60,
                  height: 60,
                  child: _StationMarker(),
                ),
                if (origin != null)
                  Marker(
                    point: origin!,
                    width: 50,
                    height: 50,
                    child: const _EndpointMarker(label: 'A', color: Colors.green),
                  ),
                if (destination != null)
                  Marker(
                    point: destination!,
                    width: 50,
                    height: 50,
                    child: const _EndpointMarker(label: 'B', color: Colors.red),
                  ),
                if (herPosition != null)
                  Marker(
                    point: herPosition!,
                    width: 22,
                    height: 22,
                    child: _HerDot(isMock: isHerPositionMock),
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

class _EndpointMarker extends StatelessWidget {
  const _EndpointMarker({required this.label, required this.color});

  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color.shade700,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _HerDot extends StatelessWidget {
  const _HerDot({required this.isMock});

  final bool isMock;

  @override
  Widget build(BuildContext context) {
    final color = isMock ? Colors.amber.shade700 : Colors.blue.shade600;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _AttributionBar extends StatelessWidget {
  const _AttributionBar();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: Colors.white.withValues(alpha: 0.7),
        child: const Text(
          '© OpenStreetMap | Routing © OSRM',
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
