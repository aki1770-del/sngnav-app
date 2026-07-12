/// THE HONEST GUARD — does the MOUTH cover what the APP ACTUALLY SAYS?
///
/// The first guard (offline_safety_voice_test.dart) asked only: "is every
/// phrase in the catalog a real string somewhere in the source?" That is a test
/// of the AUTHOR'S HONESTY. It passes GREEN on a catalog of ten phrases the app
/// can never emit, while every hazard warning HER actually hears goes to a
/// layer with no mouth. c2_offline_survival_test RED-2 was worse: it asserted a
/// file exists ON OUR DISK. Neither test is about HER HEARING ANYTHING.
///
/// This guard enumerates what the app can ACTUALLY pass to
/// `AlertActuators.speak()` at runtime — by CALLING the real builders at the
/// real call sites — and asserts the bundled mouth covers the SAFETY-CLASS
/// ones. It is derived from the announce() call graph, measured 2026-07-12:
///
///   main.dart:1161  invisibleBlackIceAnnouncement.jaSpokenText      STATIC
///   main.dart:1172  turmoilSpokenText(state, ja: true)              STATIC ×3
///   main.dart:1218  kConditionsUnknownJaSpokenText                  STATIC
///   main.dart:1240  staleInvisibleBlackIceSpokenText(hourJst:)      SLOTTED
///   main.dart:1419  AlertExplainer.forConditionAndProfile(c,p).action STATIC ×N
///   drive_hud_controller.dart:189  DriveHudLocalizer.spokenGuidance() STATIC ×2
///   drive_hud_controller.dart:233  ManeuverNarrator.decide().text   STATIC ×N (nav-class)
///
/// SLOTTED strings cannot be pre-rendered — recorded, never claimed.
/// NAV-class strings exist only when a LIVE OSRM route was fetched over the
/// network (lib/route_fetch.dart:50 — `https://router.project-osrm.org`), so
/// they cannot arise in the dead zone this mouth exists for. They are the
/// recorded, measured remainder — see `kNavClassRemainder` below.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:routing_engine/routing_engine.dart' show RouteManeuver;
import 'package:snow_rendering/snow_rendering.dart' as snow_rendering;
import 'package:sngnav_app/main.dart' show severityForCondition;
import 'package:sngnav_app/services/drive_hud_localizer.dart';
import 'package:sngnav_app/services/maneuver_narration.dart';
import 'package:sngnav_app/services/staleness_policy.dart';
import 'package:sngnav_app/services/turmoil_watch.dart';
import 'package:compound_failure_advisor/compound_failure_advisor.dart'
    show DriveAction;
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;

/// Every SAFETY-CLASS static ja string the app can pass to `speak()`.
///
/// Built by CALLING the production builders — not by grepping source.
Set<String> emittableSafetyStaticJa() {
  final out = <String>{};

  // (1) main.dart:1419 — the road-surface alert, spoken VERBATIM from the
  // catalog explainer, for every (condition, profile) the driver can select in
  // the app's own dropdowns (main.dart:1504 / :1530), gated on >= warning
  // (AlertAnnouncer.announce) and on the explainer's own ja locale.
  for (final c in RoadSurfaceCondition.values) {
    if (severityForCondition(c).index < AlertSeverity.warning.index) continue;
    for (final p in DriverProfile.values) {
      final e = AlertExplainer.forConditionAndProfile(c, p);
      if (!e.localeTag.toLowerCase().startsWith('ja')) continue;
      out.add(e.action);
    }
  }

  // (2) drive_hud_controller.dart:189 — the caution-rung guidance line.
  const localizer = DriveHudLocalizer();
  for (final a in DriveAction.values) {
    if (a.index < DriveAction.heightenedCaution.index) continue;
    final s = localizer.spokenGuidance(a, 'ja');
    if (s.isNotEmpty) out.add(s);
  }

  // (3) main.dart:1161 — the live invisible-black-ice announcement.
  out.add(snow_rendering.invisibleBlackIceAnnouncement.jaSpokenText);

  // (4) main.dart:1172 — the measured-turmoil caution lines (rain / wind /
  // both are the only announcing states; anything else returns null).
  for (final rain in TurmoilChannel.values) {
    for (final wind in TurmoilChannel.values) {
      final s = turmoilSpokenText(
        TurmoilWatchState(
          rain: rain,
          wind: wind,
          precipitation10mMm: null,
          windMetersPerSecond: null,
        ),
        ja: true,
      );
      if (s != null) out.add(s);
    }
  }

  // (5) main.dart:1218 — the honest-absence line.
  out.add(kConditionsUnknownJaSpokenText);

  return out;
}

/// NAV-class static ja strings — emittable ONLY with a live network route.
Set<String> emittableNavStaticJa() {
  const narrator = ManeuverNarrator();
  final out = <String>{};
  const types = <String>[
    'depart', 'arrive', 'straight', 'left', 'slight_left', 'sharp_left',
    'right', 'slight_right', 'sharp_right', 'u_turn_left', 'u_turn_right',
    'uturn', 'roundabout_enter', 'roundabout', 'rotary', 'merge', 'ramp_left',
    'ramp_right', 'unknown_type_fallback',
  ];
  for (final t in types) {
    for (final mode in [LocalizationMode.gpsTrusted, LocalizationMode.gpsSuspect]) {
      for (final icy in [false, true]) {
        final d = narrator.decide(
          maneuver: RouteManeuver(
            index: 0,
            instruction: '',
            type: t,
            lengthKm: 0,
            timeSeconds: 0,
            position: const LatLng(39.72, 140.10),
          ),
          mode: mode,
          icyTurn: icy,
          localeTag: 'ja',
        );
        if (d.shouldAnnounce && d.text.isNotEmpty) out.add(d.text);
      }
    }
  }
  return out;
}

