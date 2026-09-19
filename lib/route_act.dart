/// Setting a route, as decided 2026-09-14: a route may not be set by touch while
/// the car moves, and a touch on her map sets nothing and clears nothing.
///
/// Why: the tap the driver uses to look around her map pauses follow and does
/// nothing else, so her route cannot be thrown away by it. A route is set only
/// through a deliberate act she starts from a control, beside words saying it
/// is for when the car is stopped.
///
/// This file holds:
/// * where route setting is open, from the host and the motion measured in
///   the current sharing session;
/// * which points a tap on the route act's own map chooses;
/// * a view of her map's tile provider that the act's map cannot close;
/// * the route act, which closes itself when motion is measured.
library;

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        defaultTargetPlatform,
        immutable,
        kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'akita_map.dart';
import 'her_position.dart' show GroundMotion;
import 'l10n/app_localizations.dart';

/// How long a position event may be absent before the app treats the feed as
/// in a drought: the blackout watchdog polls the drive brain after this long
/// without an event, checking on a 15 s tick. A stop reading is current for
/// no longer than this (decided 2026-09-14), so the bound is the app's own
/// cadence and no new number. Provisional: no device reading of a platform's
/// fix cadence at a stop exists.
const Duration kPositionDrought = Duration(seconds: 30);

/// Where the app runs, for the question of when a route may be set.
enum RouteSettingHost {
  /// A phone, or any host that is not in a car by definition. Its only motion
  /// signal is the platform's speed while she shares her location, read from
  /// each fix ([GroundMotion]). With no reading, route setting is open, and
  /// only through the route act, so that declining location does not cost
  /// the route panel.
  phone,

  /// The IVI: in a car by definition, and this app reads no vehicle signal
  /// that could say the car is stopped. Route setting is closed.
  iviWithoutVehicleSignal,
}

/// The host as this build can tell it. A native Linux build is taken as the
/// IVI: the app's in-car target is embedded Linux, and a Linux desktop cannot
/// be told apart from it here, so the ambiguity routes to closed.
RouteSettingHost routeSettingHost() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux
        ? RouteSettingHost.iviWithoutVehicleSignal
        : RouteSettingHost.phone;

/// What one sharing session has measured about the car's motion, for route
/// setting on a phone (decided 2026-09-14). A new session starts with [none].
///
/// * With no motion reading in the session, route setting stays open, only
///   through the route act: a phone with no motion evidence is not known to
///   be in a car.
/// * Once a reading counts (moving from any sample; stopped only on a fix the
///   drive brain took as trusted), route setting is open only while a stop is
///   current. A tunnel, a GPS drought, a straddling reading, a sample with no
///   measured accuracy or an aged stop all keep it closed: losing the signal
///   never opens it.
/// * A stop is current only while the session's latest trusted reading says
///   stopped, and for no longer than [kPositionDrought] after either the stop
///   fix's own time or its arrival, whichever is older. Other events, measured
///   or not, never extend it.
@immutable
class ShareMotion {
  const ShareMotion._({
    required this.measured,
    this.stopFixAt,
    this.stopReceivedAt,
  });

  /// No motion reading in this session.
  static const ShareMotion none = ShareMotion._(measured: false);

  /// Whether any motion reading has counted in this session.
  final bool measured;

  /// The fix time of the stop that is the session's latest trusted reading.
  final DateTime? stopFixAt;

  /// When that stop's fix was received.
  final DateTime? stopReceivedAt;

  /// The session's motion after one sample's [reading]. [onTrustedFix] says
  /// whether the drive brain took the sample as a trusted fix; [fixAt] is the
  /// sample's own time and [receivedAt] the app's clock when it arrived.
  ///
  /// Moving counts from any sample: closing needs less evidence than opening.
  /// A trusted reading that is not a stop ends any stop. An untrusted sample
  /// that is not moving changes nothing; the time bound ends its stop.
  ShareMotion after({
    required GroundMotion reading,
    required bool onTrustedFix,
    required DateTime fixAt,
    required DateTime receivedAt,
  }) =>
      switch (reading) {
        GroundMotion.moving => const ShareMotion._(measured: true),
        GroundMotion.stopped when onTrustedFix => ShareMotion._(
            measured: true, stopFixAt: fixAt, stopReceivedAt: receivedAt),
        _ when onTrustedFix => ShareMotion._(measured: measured),
        _ => this,
      };

  /// Whether a stop is current at [now].
  bool stopIsCurrent(DateTime now) {
    final fixAt = stopFixAt, receivedAt = stopReceivedAt;
    if (fixAt == null || receivedAt == null) return false;
    return now.difference(fixAt) <= kPositionDrought &&
        now.difference(receivedAt) <= kPositionDrought;
  }

  @override
  bool operator ==(Object other) =>
      other is ShareMotion &&
      other.measured == measured &&
      other.stopFixAt == stopFixAt &&
      other.stopReceivedAt == stopReceivedAt;

  @override
  int get hashCode => Object.hash(measured, stopFixAt, stopReceivedAt);

  @override
  String toString() =>
      'ShareMotion(measured: $measured, stop at $stopFixAt, received $stopReceivedAt)';
}

/// Whether a route may be set at [now], and then only through the route act.
/// [motion] is the current sharing session's, or `null` when she is not
/// sharing: with no session there is no motion evidence at all.
bool routeSettingOpen(
  RouteSettingHost host, {
  ShareMotion? motion,
  DateTime? now,
}) {
  if (host != RouteSettingHost.phone) return false;
  if (motion == null || !motion.measured) return true;
  return now != null && motion.stopIsCurrent(now);
}

/// The points after a tap on the route act's map: start A first, then
/// destination B. With both chosen a tap chooses nothing, so a stray touch
/// cannot replace a point she chose; choosing again is its own control.
(LatLng?, LatLng?) routeActPointsAfterTap({
  LatLng? origin,
  LatLng? destination,
  required LatLng tap,
}) {
  if (origin == null) return (tap, destination);
  if (destination == null) return (origin, tap);
  return (origin, destination);
}

/// A view of a tile provider that the map it is given to cannot close.
///
/// flutter_map 8.3.2 disposes a tile layer's provider when the layer is
/// disposed (`tile_layer.dart:517`). Her map's offline provider disposes its
/// network fallback when disposed (offline_tiles 0.5.7,
/// `offline_tile_provider.dart:73-75`), which closes that fallback's HTTP
/// client (`network/tile_provider.dart:129-131`). The route act's map borrows
/// her map's provider through this view, so closing the act leaves her map
/// able to fetch a tile the bundled archive does not hold.
class BorrowedTileProvider extends TileProvider {
  BorrowedTileProvider(this.owner) : super(headers: owner.headers);

  /// The provider that owns the tiles and their lifetime: her map's.
  final TileProvider owner;

  @override
  bool get supportsCancelLoading => owner.supportsCancelLoading;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      owner.getImage(coordinates, options);

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) =>
      owner.getImageWithCancelLoadingSupport(
          coordinates, options, cancelLoading);

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) =>
      owner.getTileUrl(coordinates, options);

  @override
  String? getTileFallbackUrl(TileCoordinates coordinates, TileLayer options) =>
      owner.getTileFallbackUrl(coordinates, options);

  /// Nothing: the owner outlives this view.
  @override
  void dispose() {}
}

/// The route act: a surface she opens from a control, with the agreed words at
/// its head, where a map that is not hers chooses start A and destination B.
/// Her own map is not touched by it.
///
/// Points go to [onPointsChanged] as they are chosen, so closing the act, for
/// any reason, keeps them, and she resumes where she left off. It pops `true`
/// for its get-route control; nothing else asks for a route.
///
/// When motion is measured while the act is open (decided 2026-09-14), the act
/// closes itself and asks for no route. Only measured motion closes it: a stop
/// that ages out closes route setting on the page, not an act she is in.
class RouteActDialog extends StatefulWidget {
  const RouteActDialog({
    super.key,
    this.origin,
    this.destination,
    this.baseTileProvider,
    required this.onPointsChanged,
    this.movingReadings,
    this.movingReadingsAtOpen = 0,
  });

  final LatLng? origin;
  final LatLng? destination;

  /// Her map's basemap provider, borrowed (see [BorrowedTileProvider]).
  final TileProvider? baseTileProvider;

  final void Function(LatLng? origin, LatLng? destination) onPointsChanged;

  /// How many moving readings the page has received. Any change closes the act.
  final ValueListenable<int>? movingReadings;

  /// [movingReadings]' value when the page opened the act, so a reading that
  /// arrives before this act's first frame still closes it.
  final int movingReadingsAtOpen;

  @override
  State<RouteActDialog> createState() => _RouteActDialogState();
}

class _RouteActDialogState extends State<RouteActDialog> {
  late LatLng? _origin = widget.origin;
  late LatLng? _destination = widget.destination;

  /// Made once: a new view on every build would give the tile layer a new
  /// provider, and the map remounts its tiles on every tap.
  late final TileProvider? _tiles = widget.baseTileProvider == null
      ? null
      : BorrowedTileProvider(widget.baseTileProvider!);

  @override
  void initState() {
    super.initState();
    final moving = widget.movingReadings;
    moving?.addListener(_closeSelf);
    // A moving reading can arrive between the page's tap and this first frame.
    if (moving != null && moving.value != widget.movingReadingsAtOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeSelf());
    }
  }

  @override
  void dispose() {
    widget.movingReadings?.removeListener(_closeSelf);
    super.dispose();
  }

  /// Removes this act's own route, and only it, even if something were above
  /// it. Its points already reached the page as she chose them.
  void _closeSelf() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(false);
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _choose(LatLng? origin, LatLng? destination) {
    if (origin == _origin && destination == _destination) return;
    setState(() {
      _origin = origin;
      _destination = destination;
    });
    widget.onPointsChanged(origin, destination);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final bothChosen = _origin != null && _destination != null;
    final hint = _origin == null
        ? l.routeActChooseStart
        : _destination == null
            ? l.routeActChooseDestination
            : l.routeActBothChosen;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('route-act-close'),
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          title: Text(l.routeActOpen),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.routeSettingWhenStopped,
                key: const Key('route-act-when-stopped'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(hint, key: const Key('route-act-hint')),
              const SizedBox(height: 8),
              AkitaMap(
                key: const Key('route-act-map'),
                baseTileProvider: _tiles,
                origin: _origin,
                destination: _destination,
                onTap: (tap) {
                  final (origin, destination) = routeActPointsAfterTap(
                    origin: _origin,
                    destination: _destination,
                    tap: tap,
                  );
                  _choose(origin, destination);
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const Key('route-act-choose-again'),
                    onPressed: _origin == null && _destination == null
                        ? null
                        : () => _choose(null, null),
                    child: Text(l.routeActChooseAgain),
                  ),
                  FilledButton(
                    key: const Key('route-act-get-route'),
                    onPressed: bothChosen
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(l.routeActGetRoute),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
