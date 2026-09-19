/// Where the map's camera goes, decided in one place.
///
/// Why: the map is the surface the driver's eyes snap to. Measured 2026-09-13 in
/// the real app, driving 144 fixes along Route 13 out of Akita city: the
/// camera never left the station. Her point left the phone map at 7.6 km, and
/// from 8.2 km to 19.9 km the map held no mark of her in any mode.
///
/// The rules, set before this was built:
///
/// * The camera moves to her on TRUSTED fixes only ([followTargetAfter]). It
///   never moves on dead reckoning, lost, an unavailability, the dev mock or
///   an anchor from a previous session: it holds. Because it followed her
///   until GPS died, the ring stays in view. An unclear position never moves
///   the camera toward a place we do not trust.
/// * A hand on the map pauses follow: the moment a finger lands (the app's
///   pointer-down handler, before any gesture resolves; decided 2026-09-13), and
///   on any camera move a hand makes ([isHandMovingMap]), such as a wheel. The
///   machine yields to the person. Only her return-to-position control resumes
///   it. The words at the top of the map are what make the pause safe: a mark
///   the edge cuts says so.
/// * Zoom stays inside the bundled offline archive ([followZoom]).
/// * No look-ahead: the camera centres her (decided 2026-09-13). The fix carries
///   no heading, and on a north-up map an offset toward a guessed direction
///   would show more of north and call it ahead.
///
/// Named, not solved here: whether a route should be set by touch while
/// driving; repaint and touch on the in-vehicle display belong to the embedded
/// target.
///
/// Pure and synchronous, so the rules the app runs are the rules the tests
/// check (`test/her_map_follow_test.dart`).
library;

import 'package:flutter_map/flutter_map.dart' show MapEventSource;
import 'package:latlong2/latlong.dart';
import 'package:localization_fallback/localization_fallback.dart';

import 'her_map_inputs.dart' show anchorsThisSession;
import 'her_position.dart';

/// The lowest zoom the bundled archive holds (`assets/tiles/akita_offline
/// .mbtiles`, metadata `minzoom` 8).
const double followMinZoom = 8;

/// The highest zoom the bundled archive holds across the whole prefecture.
/// z13 exists only in the Akita-city window and along selected rural tiles, so
/// outside the city it is not there to follow into.
const double followMaxZoom = 12;

/// Where the camera goes after one position event, or `null`: it holds.
///
/// A target only when the event became the controller's anchor in this session
/// ([anchorsThisSession]) AND the controller trusts it as a confident fix. A
/// trusted fix too imprecise to be confident arrives `lost`: it is adopted as
/// the anchor, and the camera still does not move to it.
LatLng? followTargetAfter({
  required PositionFix fix,
  required LocalizationEstimate? estimate,
  required bool isMock,
}) {
  if (!anchorsThisSession(fix: fix, estimate: estimate, isMock: isMock)) {
    return null;
  }
  if (estimate!.mode != LocalizationMode.gpsTrusted) return null;
  final f = fix as PositionAvailable;
  return LatLng(f.latitude, f.longitude);
}

/// The zoom follow moves the camera at: her current zoom, kept inside the band
/// the offline archive holds everywhere. Follow never changes a zoom already
/// inside it.
double followZoom(double current) {
  if (!current.isFinite) return followMaxZoom;
  if (current < followMinZoom) return followMinZoom;
  if (current > followMaxZoom) return followMaxZoom;
  return current;
}

/// Whether a map event is a camera move a hand made: a drag, a fling, a pinch
/// or rotate, a double tap, a wheel or a keyboard. Those pause follow.
///
/// A tap event is not a camera move. A finger that taps has already paused
/// follow when it landed, through the pointer-down handler. The camera's own
/// moves, a size change, option changes and fits are not.
/// Exhaustive on purpose: a new event source in flutter_map must be decided
/// here before the app compiles.
bool isHandMovingMap(MapEventSource source) => switch (source) {
      MapEventSource.dragStart ||
      MapEventSource.onDrag ||
      MapEventSource.dragEnd ||
      MapEventSource.flingAnimationController ||
      MapEventSource.multiFingerGestureStart ||
      MapEventSource.onMultiFinger ||
      MapEventSource.multiFingerEnd ||
      MapEventSource.doubleTap ||
      MapEventSource.doubleTapHold ||
      MapEventSource.doubleTapZoomAnimationController ||
      MapEventSource.scrollWheel ||
      MapEventSource.cursorKeyboardRotation ||
      MapEventSource.keyboard =>
        true,
      MapEventSource.mapController ||
      MapEventSource.tap ||
      MapEventSource.secondaryTap ||
      MapEventSource.longPress ||
      MapEventSource.interactiveFlagsChanged ||
      MapEventSource.fitCamera ||
      MapEventSource.custom ||
      MapEventSource.nonRotatedSizeChange =>
        false,
    };
