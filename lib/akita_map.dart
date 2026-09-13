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

import 'l10n/app_localizations.dart';

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
    this.positionDegraded = false,
    this.positionLost = false,
    this.positionRefused = false,
    this.baseTileProvider,
    this.mapController,
    this.onMapEvent,
    this.onMapReady,
  });

  final double height;
  final LatLng? origin;
  final LatLng? destination;
  final List<LatLng> routePoints;
  final void Function(LatLng)? onTap;
  final LatLng? herPosition;
  final double? herAccuracyMeters;
  final bool isHerPositionMock;

  /// True when the honest position estimate is dead-reckoning or lost (from
  /// [DriveHudController.positionUnlocatable]). The map is the surface a
  /// driver's eyes snap to; on a silent GPS blackout the raw fix stream goes
  /// quiet and the last confident point must NOT keep painting a solid blue
  /// "you are here". When degraded the dot becomes a larger HOLLOW ring —
  /// "somewhere in here", not a point — and in dead-reckoning the accuracy
  /// circle (which the caller grows to the honest confidence radius) turns
  /// grey, so the map can never contradict the degraded HUD text on the same
  /// screen. The ring differs from the solid dot in fill, size and luminance,
  /// not in hue alone.
  ///
  /// Corrected 2026-09-13. This comment said the caller's radius in `lost` is
  /// `double.infinity`. That overstated it: the position controller emits an
  /// infinite radius only while no trusted fix has EVER been seen. After any
  /// trusted fix the lost radius is finite and keeps growing (375 m at 180 s
  /// for a 15 m fix at the default 2 m/s drift). In this app an infinite
  /// radius reached the map only through a live sample with a negative
  /// accuracy, which the finite-coordinate chokepoint passes and the
  /// controller refuses. flutter_map 8.3.2's circle painter fails a null check
  /// on it (`painter.dart:86`) and silently paints no circle, so a non-finite
  /// radius is never handed to the painter, and in `lost` no accuracy circle
  /// is drawn at all (see [positionLost]).
  final bool positionDegraded;

  /// True when the honest estimate is `lost` — past the position controller's
  /// honesty horizon, not merely dead-reckoning. There the controller no
  /// longer vouches for ANY radius, so the map draws no accuracy circle and
  /// SAYS, in words, that her current position is unknown. The ring, when
  /// drawn, marks the last trusted position only; with no trusted position
  /// ([herPosition] null) the words stand alone.
  final bool positionLost;

  /// Her last answer to location was "no" (`isLocationRefusal`). Read in one
  /// place, `_PositionWords`, and today it changes nothing: see there.
  final bool positionRefused;

  /// Optional offline-first basemap provider (offline_tiles'
  /// OfflineTileProvider). When supplied, the base TileLayer serves tiles from
  /// the bundled MBTiles archive first and falls back to the network for
  /// uncovered tiles. When null, the basemap is plain network (prior
  /// behaviour). See KNOWN_LIMITATION on the TileLayer below.
  final TileProvider? baseTileProvider;

  /// The camera's controller, when the caller moves the camera (the app's
  /// follow, `her_map_follow.dart`). Null: the map keeps its own and the
  /// camera moves only by hand.
  final MapController? mapController;

  /// Every map event, including the hand gestures that pause follow.
  final void Function(MapEvent event)? onMapEvent;

  /// The map has rendered once and [mapController] can move the camera.
  final VoidCallback? onMapReady;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: akitaStation,
            initialZoom: 12,
            minZoom: 5,
            maxZoom: 18,
            onTap: onTap == null ? null : (_, latlng) => onTap!(latlng),
            onMapEvent: onMapEvent,
            onMapReady: onMapReady,
          ),
          children: [
            // KNOWN_LIMITATION (WS5 / BOD-17 ruling 2 → offline PoC 2026-07-01):
            // the basemap is a NETWORK tile layer. In HER worst-case —
            // unexpected snow with Maps AND GPS down and no cell signal —
            // network tiles will not load, so the basemap goes blank. The
            // OFFLINE basemap fix (bundled MBTiles via the offline_tiles
            // OfflineTileProvider) is WIRED and DEFAULT: when
            // [baseTileProvider] is supplied, Akita renders from the bundled
            // archive OFFLINE-FIRST, network only for uncovered tiles.
            // HONEST BOUND: the bundled tiles are REAL OpenStreetMap
            // cartography in a minimal style (roads/rail/rivers/water/
            // coastline/place labels; Akita pref z8-z12 + city z13; no
            // buildings/POIs/sea-fill) — see services/offline_basemap.dart.
            // The WS5 alert channels (audio + haptic)
            // remain chosen precisely because they do NOT depend on the basemap
            // rendering — the hazard still reaches her even when the map is
            // blank.
            TileLayer(
              // Remount when the offline provider arrives: the provider loads
              // async after first build, and flutter_map never reloads tiles
              // already created (and failed on the network path) on a provider
              // swap — on a cold offline start the initial viewport stayed
              // grey until the user panned far beyond the keep-buffer. Caught
              // by the 2026-07-10 emulator airplane-mode pass.
              key: ValueKey(identityHashCode(baseTileProvider)),
              tileProvider: baseTileProvider,
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dev.aki1770del.sngnav_app',
              maxZoom: 19,
            ),
            // A non-finite radius is never handed to the painter: drawing
            // nothing must be a decision, not a swallowed paint exception.
            if (herPosition != null &&
                herAccuracyMeters != null &&
                herAccuracyMeters!.isFinite &&
                !positionLost)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: herPosition!,
                    radius: herAccuracyMeters!,
                    useRadiusInMeter: true,
                    color: (positionDegraded
                            ? Colors.blueGrey
                            : (isHerPositionMock ? Colors.amber : Colors.blue))
                        .withValues(alpha: 0.12),
                    borderColor: (positionDegraded
                            ? Colors.blueGrey
                            : (isHerPositionMock ? Colors.amber : Colors.blue))
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
                    width: _HerDot.extent,
                    height: _HerDot.extent,
                    child: _HerDot(
                      isMock: isHerPositionMock,
                      degraded: positionDegraded || positionLost,
                    ),
                  ),
              ],
            ),
            // The words are anchored to the map, not to her last position, so
            // the camera can never cull them (2026-09-13: they were a marker at
            // her last position, and left the screen with her).
            _PositionWords(
              herPosition: herPosition,
              positionLost: positionLost,
              positionRefused: positionRefused,
              // Half the drawn mark: ring 34 px, mock square 20 px, dot 22 px.
              markHalfExtent: (positionDegraded || positionLost)
                  ? 17
                  : (isHerPositionMock ? 10 : 11),
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

/// HER position dot. Its three states must stay distinct when colour is gone:
/// colour is the first channel glare, peripheral vision and colour-vision
/// deficiency take away.
///
/// Until 2026-09-13 the states were one 22px circle in three fills. The
/// weakest pair, real fix `#1E88E5` against degraded `#78909C`, measured
/// 1.098:1 in luminance, and rendered desaturated all three were one grey
/// disc. The state now rides FILL, SHAPE and SIZE first, and colour last:
///
/// * real fix: SOLID round dot, white rim, 22px. The only solid state, so the
///   only one that reads as a confident "you are here". Unchanged.
/// * mock: SQUARE, 20px, pale fill, dark outline. A simulated position is
///   never round, so it cannot pass for a measured one, even in monochrome.
/// * degraded (dead-reckoning or lost): HOLLOW ring, 34px. The map shows
///   through the middle because no single point inside it is known.
///
/// Luminance contrast of the state colours, from the Material shades in the
/// SDK: real fix against degraded 4.377:1, real fix against mock 3.463:1,
/// degraded against mock 15.156:1 (WCAG non-text floor 3.0:1).
///
/// Where both flags are set, degraded wins: the dot resolves toward "we do
/// not know", never toward a simulated or a confident point.
class _HerDot extends StatelessWidget {
  const _HerDot({required this.isMock, this.degraded = false});

  /// Side of the square Marker box that hosts the dot: the degraded ring's
  /// diameter. flutter_map lays a marker child out under TIGHT constraints,
  /// so a box smaller than the largest state would squeeze every state to
  /// one size on the map while each still looks right on its own.
  static const double extent = 34;

  final bool isMock;
  final bool degraded;

  @override
  Widget build(BuildContext context) {
    if (degraded) {
      // No fill and no shadow: a shadow would paint the hole in.
      return Center(
        child: Container(
          key: const ValueKey('her-dot-degraded'),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade900, width: 4),
          ),
        ),
      );
    }
    if (isMock) {
      return Center(
        child: Container(
          key: const ValueKey('her-dot-mock'),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            shape: BoxShape.rectangle,
            border: Border.all(color: Colors.grey.shade900, width: 3),
          ),
        ),
      );
    }
    final fill = Colors.blue.shade600;
    return Center(
      child: Container(
        key: const ValueKey('her-dot-real-fix'),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: fill.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the map says about her position, in words, at the top of the map.
/// Lost → 現在地不明, whatever the camera shows. A position mark that exists
/// but that the map edge cuts, in part or whole → 現在地は地図の外. Nothing
/// otherwise. At the edge an unclear case resolves toward the words: a mark
/// counts as shown only when the edge cuts none of it.
///
/// No position claim may be silent on the map. Measured 2026-09-13: 8.2 km
/// out along Route 13 the map held no mark of her in any mode, under a status
/// line that still gave her position.
class _PositionWords extends StatelessWidget {
  const _PositionWords({
    required this.herPosition,
    required this.positionLost,
    required this.positionRefused,
    required this.markHalfExtent,
  });

  final LatLng? herPosition;
  final bool positionLost;
  final bool positionRefused;
  final double markHalfExtent;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    String? words;
    Key? key;
    if (positionLost && positionRefused) {
      // Her refusal of location: THE ONE PLACE the map's words for it are
      // chosen. For now they are the words and the pill of a GPS that never
      // found her, unchanged: what the map should say after her "no" is under
      // review (2026-09-13), and a ruling changes this branch alone.
      words = l.positionUnknownLabel;
      key = const ValueKey('her-position-unknown-label');
    } else if (positionLost) {
      words = l.positionUnknownLabel;
      key = const ValueKey('her-position-unknown-label');
    } else if (herPosition != null) {
      final camera = MapCamera.of(context);
      final p = camera.latLngToScreenOffset(herPosition!);
      final s = camera.nonRotatedSize;
      // The mark counts as shown only when the map edge cuts none of it.
      // The attribution bar is translucent and does not hide a mark (rendered:
      // a dot under it stays readable), so it is not treated as an edge.
      final h = markHalfExtent;
      final inView = p.dx >= h &&
          p.dy >= h &&
          p.dx <= s.width - h &&
          p.dy <= s.height - h;
      if (!inView) {
        words = l.positionOffMapLabel;
        key = const ValueKey('her-position-off-map-label');
      }
    }
    if (words == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _PositionUnknownLabel(labelKey: key!, text: words),
      ),
    );
  }
}

/// The pill that carries the words. Dark pill, white text — the only
/// dark-ground label on the map, so it cannot pass for a place name, which the
/// basemap and the station marker draw dark-on-light.
class _PositionUnknownLabel extends StatelessWidget {
  const _PositionUnknownLabel({required this.labelKey, required this.text});

  final Key labelKey;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: labelKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
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
          '© OpenStreetMap contributors | Routing © OSRM',
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
