/// Setting a route, as ruled 2026-09-14: a route may not be set by touch while
/// the car moves, and a touch on her map sets nothing and clears nothing.
///
/// HER-trace: the tap she uses to look around her map pauses follow and does
/// nothing else, so her route cannot be thrown away by it. A route is set only
/// through a deliberate act she starts from a control, beside words saying it
/// is for when the car is stopped.
///
/// This file holds:
/// * where route setting is open, from what this app can measure today;
/// * which points a tap on the route act's own map chooses;
/// * a view of her map's tile provider that the act's map cannot close;
/// * the route act.
///
/// Not built, and named: closing an open act when motion is measured, keeping
/// its points. This app has no motion signal to measure motion with. The
/// phone's platform speed is discarded today (whether to feed it is not yet
/// decided), and the app reads no vehicle signal on the IVI.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'akita_map.dart';
import 'l10n/app_localizations.dart';

/// Where the app runs, for the question of when a route may be set.
enum RouteSettingHost {
  /// A phone, or any host that is not in a car by definition, with no motion
  /// signal. Every phone state has none today: the platform's speed is
  /// discarded. Route setting is open, and only through the route act, so
  /// that declining location does not cost the route panel.
  noMotionSignal,

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
        : RouteSettingHost.noMotionSignal;

/// Whether a route may be set, and then only through the route act.
bool routeSettingOpen(RouteSettingHost host) =>
    host == RouteSettingHost.noMotionSignal;

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

/// The route act: a surface she opens from a control, with the ruled words at
/// its head, where a map that is not hers chooses start A and destination B.
/// Her own map is not touched by it.
///
/// Points go to [onPointsChanged] as they are chosen, so closing the act, for
/// any reason, keeps them, and she resumes where she left off. It pops `true`
/// for its get-route control; nothing else asks for a route.
class RouteActDialog extends StatefulWidget {
  const RouteActDialog({
    super.key,
    this.origin,
    this.destination,
    this.baseTileProvider,
    required this.onPointsChanged,
  });

  final LatLng? origin;
  final LatLng? destination;

  /// Her map's basemap provider, borrowed (see [BorrowedTileProvider]).
  final TileProvider? baseTileProvider;

  final void Function(LatLng? origin, LatLng? destination) onPointsChanged;

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
