/// Slice 1+2b map widget — Akita-shi centered, JMA station marker,
/// tap-to-set origin+destination, route polyline render.
///
/// Slice 1: render the map + station marker.
/// Slice 2b: accept origin/destination/route from parent; emit taps so
/// parent can drive an OSRM call. The widget itself stays presentational —
/// no routing state lives here.
///
/// Why: a driver in Akita needs to SEE WHERE SHE IS, then SEE
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
    this.positionNoneYet = false,
    this.baseTileProvider,
    this.mapController,
    this.onMapEvent,
    this.onMapReady,
    this.onTouchDown,
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

  /// Location is off for this app: permission denied (`isLocationRefusal`).
  /// The map then says 位置情報オフ, whether or not [positionLost] is set.
  final bool positionRefused;

  /// She is sharing and no position event has arrived within 60 s of the
  /// position stream's subscription (with [positionLost] set). The words are
  /// the lost words, 現在地不明, and a screen reader hears their arrival once,
  /// as a live region, never through the alert announcer (decided 2026-09-14).
  final bool positionNoneYet;

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

  /// A finger (or any pointer) landed on the map, before any gesture resolves.
  /// The app pauses follow here, so nothing moves under her finger.
  final VoidCallback? onTouchDown;

  @override
  Widget build(BuildContext context) {
    // Half the drawn mark: ring 34 px, mock square 20 px, dot 22 px.
    final double markHalfExtent = (positionDegraded || positionLost)
        ? 17
        : (isHerPositionMock ? 10 : 11);
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
            onPointerDown:
                onTouchDown == null ? null : (_, _) => onTouchDown!(),
          ),
          children: [
            // KNOWN_LIMITATION (offline proof of concept, 2026-07-01):
            // the basemap is a NETWORK tile layer. In the worst case —
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
            // Her mark is the LAST marker, so it is drawn above the station's
            // pin and name and above A and B. Nothing on the map covers it.
            MarkerLayer(
              markers: [
                Marker(
                  point: akitaStation,
                  width: 60,
                  height: 60,
                  child: _StationMarker(
                    herPosition: herPosition,
                    herHalfExtent: markHalfExtent,
                  ),
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
                    // Not red (2026-09-14): the station pin beside it is
                    // Colors.red.shade700, the same colour B's disc had.
                    child:
                        const _EndpointMarker(label: 'B', color: Colors.purple),
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
              positionNoneYet: positionNoneYet,
              markHalfExtent: markHalfExtent,
            ),
            const _AttributionBar(),
          ],
        ),
      ),
    );
  }
}

/// The JMA station's pin and its name, 秋田, kept off her position mark.
///
/// Why. Seen 2026-10-02 in release builds on two emulators, the camera
/// following her at zoom 12 with her fix 390 m from the station: her blue dot
/// was drawn over the name and hid half of 田. A marker is drawn in pixels at
/// every zoom, so the zone where the two meet is about 58 x 44 px: 1.7 x 1.3 km
/// at zoom 12, and most of central Akita at zoom 8, the lowest zoom follow
/// uses. The degraded ring was worse. It held the red pin in its hole, a
/// target on a named place, which reads as a confident position in the state
/// that exists to say the position is not known.
///
/// What she sees first is her mark, and this marker yields to it:
///
/// * Her mark is the last marker on the map, so nothing is drawn over it.
/// * The pin is not drawn where its red would come within [_pinGap] of her
///   mark. Partly under her dot, the pin read as the dot's own tail. Inside
///   the ring, it answered "where in here?" with a point the position does
///   not have. Where she covers the pin, her mark marks that place.
/// * The name is never under her mark. It takes the first place, in order,
///   that keeps [_nameGap] from her mark and from the pin. Above the pin,
///   where it has always been, comes first. While the pin is drawn, the name
///   stays with it: below, right and left of the pin, then above or below her
///   mark. Where her mark has taken the pin's place, the name goes beside her
///   mark: above, below, right, left. A place inside the map wins over one
///   the edge cuts.
///
/// With no position near, the marker draws as it always has at default text.
///
/// Bounds. Her mark's size is the drawn size of each state, not its shadow:
/// the dot's soft glow can tint the name's edge. Which places are inside the
/// map is known only while the map is not rotated; rotated, the first clear
/// place wins. The marker is culled with its 60 px box, as before, so a name
/// placed outside that box leaves with it.
class _StationMarker extends StatelessWidget {
  const _StationMarker({this.herPosition, this.herHalfExtent = 0});

  /// Where her mark is drawn, or null when there is none.
  final LatLng? herPosition;

  /// Half the side of her drawn mark: dot 11, mock square 10, ring 17.
  final double herHalfExtent;

  /// The pin's box, relative to the station point.
  ///
  /// It is where the pin has sat at default text since the marker was first
  /// drawn, under a 22 px name. Until 2026-10-02 the pin was stacked under the
  /// name, so large text pushed it down: at text scale 2.0 its tip sat 32 px
  /// south of the station, 15 km at zoom 8, and the name covered the station
  /// point. Now the pin stays here and a larger name grows upward.
  ///
  /// Named, not changed here: the pin's tip points 17 px south of the station
  /// point at every text size, because the station point sits in the pin's
  /// head, not at its tip.
  static const Rect _pinBox = Rect.fromLTWH(-14, -8, 28, 28);

  /// The red of [Icons.place] at size 28 inside [_pinBox], relative to the
  /// station point: measured from pixels on 2026-10-02 as (-8, -5)..(8, 17),
  /// and widened by 1 px.
  static const Rect _pinInk = Rect.fromLTRB(-9, -6, 9, 18);

  /// How close the pin's red may come to her mark.
  static const double _pinGap = 3;

  /// How close the name may come to her mark. Beside the pin, the name is
  /// placed this far from the pin's ink, except above it, where it has always
  /// sat 2 px clear.
  static const double _nameGap = 4;

  @override
  Widget build(BuildContext context) {
    final name = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blueGrey.shade700, width: 1),
      ),
      child: Text(
        AppL10n.of(context).akitaStationMapLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey.shade900,
        ),
      ),
    );

    // Her mark and the map's edges, in this marker's own frame: pixels from
    // the station point, north up before any map rotation. Markers are laid
    // out in the projected frame, so the offset is a projected one.
    Rect? her;
    Rect? view;
    final position = herPosition;
    if (position != null && herHalfExtent > 0) {
      final camera = MapCamera.of(context);
      final offset = camera.projectAtZoom(position) -
          camera.projectAtZoom(akitaStation);
      her = Rect.fromCenter(
          center: offset,
          width: 2 * herHalfExtent,
          height: 2 * herHalfExtent);
      if (camera.rotation == 0) {
        final s = camera.latLngToScreenOffset(akitaStation);
        view = Rect.fromLTWH(-s.dx, -s.dy, camera.nonRotatedSize.width,
            camera.nonRotatedSize.height);
      }
    }
    final pinShown = her == null || !_pinInk.overlaps(her.inflate(_pinGap));

    // flutter_map lays a marker child out under TIGHT constraints (the 60 px
    // box). The name takes the size its word needs and may be placed outside
    // that box: at text scale 2.0 the old column overflowed by 5 px
    // (2026-09-14), and in English the box broke "Akita" into "Akit" and "a"
    // (2026-09-19). Nothing here is constrained by the box.
    return CustomMultiChildLayout(
      delegate: _StationLayout(her: her, view: view, pinShown: pinShown),
      children: [
        LayoutId(id: _StationPart.name, child: name),
        if (pinShown)
          LayoutId(
            id: _StationPart.pin,
            child: Icon(Icons.place, color: Colors.red.shade700, size: 28),
          ),
      ],
    );
  }
}

enum _StationPart { name, pin }

/// Places the station's name and pin around the station point, which is the
/// centre of the marker's box. See [_StationMarker].
class _StationLayout extends MultiChildLayoutDelegate {
  _StationLayout({required this.her, required this.view, required this.pinShown});

  /// Her drawn mark, relative to the station point, or null.
  final Rect? her;

  /// The map's visible area, relative to the station point, or null when it
  /// is not known.
  final Rect? view;

  final bool pinShown;

  @override
  void performLayout(Size size) {
    final station = size.center(Offset.zero);
    if (hasChild(_StationPart.pin)) {
      layoutChild(_StationPart.pin, const BoxConstraints());
      positionChild(_StationPart.pin, station + _StationMarker._pinBox.topLeft);
    }
    final n = layoutChild(_StationPart.name, const BoxConstraints());
    positionChild(_StationPart.name, station + _namePlace(n).topLeft);
  }

  /// The first place for a name of size [n] that keeps clear of her mark and
  /// of the pin, preferring places inside the map.
  Rect _namePlace(Size n) {
    const pin = _StationMarker._pinBox;
    const ink = _StationMarker._pinInk;
    const gap = _StationMarker._nameGap;
    final above = Rect.fromLTWH(-n.width / 2, pin.top - n.height, n.width, n.height);
    final mark = her;
    if (mark == null) return above;

    final clearOfHer = mark.inflate(gap);
    final aboveHer = Rect.fromLTWH(mark.center.dx - n.width / 2,
        clearOfHer.top - n.height, n.width, n.height);
    final belowHer = Rect.fromLTWH(
        mark.center.dx - n.width / 2, clearOfHer.bottom, n.width, n.height);
    final places = pinShown
        // The name stays with its pin.
        ? <Rect>[
            above,
            Rect.fromLTWH(-n.width / 2, pin.bottom, n.width, n.height),
            Rect.fromLTWH(ink.right + gap, -n.height / 2, n.width, n.height),
            Rect.fromLTWH(
                ink.left - gap - n.width, -n.height / 2, n.width, n.height),
            aboveHer,
            belowHer,
          ]
        // Her mark has taken the pin's place, so the name labels the place
        // she is at, beside her mark. Rendered 2026-10-02: placed below the
        // hidden pin instead, it floated 30 px south of her with nothing
        // under it, naming a place 900 m from the station at zoom 12.
        : <Rect>[
            above,
            aboveHer,
            belowHer,
            Rect.fromLTWH(clearOfHer.right, mark.center.dy - n.height / 2,
                n.width, n.height),
            Rect.fromLTWH(clearOfHer.left - n.width,
                mark.center.dy - n.height / 2, n.width, n.height),
          ];
    // Against the pin, the test is its ink, not ink plus the gap: the usual
    // place sits 2 px above the ink, as it always has. Tested with the gap
    // (2026-10-02), it refused the usual place everywhere, and a position
    // anywhere on the map moved the name off its pin.
    bool clear(Rect r) =>
        !r.overlaps(clearOfHer) && !(pinShown && r.overlaps(ink));
    bool inside(Rect r) =>
        view == null ||
        (view!.contains(r.topLeft) && view!.contains(r.bottomRight));
    for (final r in places) {
      if (clear(r) && inside(r)) return r;
    }
    for (final r in places) {
      if (clear(r)) return r;
    }
    // Not reached for either language at text scale 1.0 or 2.0: checked on
    // 2026-10-02 at every half pixel within 100 px of the station, for every
    // mark size (beyond that the first place is clear). Should a larger name
    // ever get here, it goes above her mark, which is clear of her mark by
    // construction; it may then sit on the pin, never on her.
    return aboveHer;
  }

  @override
  bool shouldRelayout(_StationLayout old) =>
      old.her != her || old.view != view || old.pinShown != pinShown;
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

/// The driver's position dot. Its three states must stay distinct when colour is gone:
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
    this.positionNoneYet = false,
    required this.markHalfExtent,
  });

  final LatLng? herPosition;
  final bool positionLost;
  final bool positionRefused;
  final bool positionNoneYet;
  final double markHalfExtent;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    String? words;
    Key? key;
    var liveRegion = false;
    if (positionRefused) {
      // Location is off for this app: its own words, not 現在地不明 (decided
      // 2026-09-13). A permission result is the platform's exact answer, and
      // her decision is shown as a setting, not as a machine fault. Not gated
      // on positionLost: a refusal does not reach the drive brain, so lost is
      // never set. No icon, no button; a screen reader hears it once, as a
      // live region, and never through the alert announcer.
      words = l.locationOffLabel;
      key = const ValueKey('her-location-off-label');
      liveRegion = true;
    } else if (positionLost) {
      words = l.positionUnknownLabel;
      key = const ValueKey('her-position-unknown-label');
      // A share where no position arrived within 60 s of the subscription:
      // the same words, heard once by a screen reader as they appear.
      liveRegion = positionNoneYet;
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
    final pill = _PositionUnknownLabel(labelKey: key!, text: words);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        // A node of its own (decided 2026-09-14): without `container`, the flag
        // merged into the map card's node, and a screen reader was read the
        // whole card instead of these words.
        child: liveRegion
            ? Semantics(container: true, liveRegion: true, child: pill)
            : pill,
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
