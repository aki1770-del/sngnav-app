/// Slice 4 — first-launch driver profile picker.
///
/// Full-screen picker shown the first time the driver opens the app.
/// Six profile options, each with a short plain-English label and a
/// short context line. The picker auto-dismisses if the host detects
/// motion (a `Stream<bool>` the host owns; geolocator is one source but
/// the picker does not import geolocator so the same widget can be
/// driven by a synthetic stream in tests).
///
/// Auto-dismiss-on-motion is a deliberate dignity choice: a driver who
/// has already pulled out of the driveway should never be asked to
/// classify themselves while moving. The host stops the stream after
/// the first true event and dismisses the picker; downstream the
/// driver still has the dropdown in the main UI to change profile
/// later.
///
/// Architectural invariant: this widget renders a list of six
/// profile choices. It does not branch its own UI on which choice
/// is currently active in the upstream service; it only exposes the
/// list and a callback. Differential alert tuning downstream lives in
/// the thresholds the picker's choice produces, not in the picker UI.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Plain-English profile label. One line per profile. Reviewable in
/// the picker file so a copy edit does not require touching the core
/// package.
String profileLabel(DriverProfile profile) {
  switch (profile) {
    case DriverProfile.ageingRural:
      return 'Older driver in a rural area';
    case DriverProfile.snowZoneExperienced:
      return 'Experienced snow-zone commuter';
    case DriverProfile.noviceUrban:
      return 'Newly licensed urban driver';
    case DriverProfile.professional:
      return 'Professional driver (taxi, freight, delivery)';
    case DriverProfile.agriculturalForestry:
      return 'Agricultural or forestry driver';
    case DriverProfile.foreignTouristSnowZone:
      return 'Visiting from abroad, driving in snow';
  }
}

/// A short context sentence per profile. The picker shows this below
/// the label so the driver can recognise themselves at a glance.
String profileBlurb(DriverProfile profile) {
  switch (profile) {
    case DriverProfile.ageingRural:
      return 'Alerts arrive earlier on cold and visibility.';
    case DriverProfile.snowZoneExperienced:
      return 'Standard alert thresholds.';
    case DriverProfile.noviceUrban:
      return 'Alerts arrive earlier on visibility for first-three-year drivers.';
    case DriverProfile.professional:
      return 'Standard thresholds; brief alert framing.';
    case DriverProfile.agriculturalForestry:
      return 'Standard thresholds; off-route forgiveness will follow.';
    case DriverProfile.foreignTouristSnowZone:
      return 'Most-conservative thresholds across every dimension.';
  }
}

/// Full-screen picker. The host pushes this on top of the main route
/// at first launch and pops it (or relies on auto-dismiss) when the
/// driver picks a profile or motion is detected.
class DriverProfilePicker extends StatefulWidget {
  final DriverProfile? currentProfile;
  final ValueChanged<DriverProfile> onPicked;

  /// Optional motion stream. The first true event causes the picker
  /// to call onAutoDismiss; the host is responsible for popping the
  /// route. The picker itself only invokes the callback.
  final Stream<bool>? motionStream;
  final VoidCallback? onAutoDismiss;

  const DriverProfilePicker({
    super.key,
    this.currentProfile,
    required this.onPicked,
    this.motionStream,
    this.onAutoDismiss,
  });

  @override
  State<DriverProfilePicker> createState() => _DriverProfilePickerState();
}

class _DriverProfilePickerState extends State<DriverProfilePicker> {
  StreamSubscription<bool>? _motionSub;

  @override
  void initState() {
    super.initState();
    final stream = widget.motionStream;
    final cb = widget.onAutoDismiss;
    if (stream != null && cb != null) {
      _motionSub = stream.listen((moving) {
        if (moving) {
          _motionSub?.cancel();
          _motionSub = null;
          cb();
        }
      });
    }
  }

  @override
  void dispose() {
    _motionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Who is driving today?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'The choice tunes when alerts arrive. You can change it any '
            'time from the main screen.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final profile in DriverProfile.values)
            Card(
              key: ValueKey('driver-profile-card-${profile.name}'),
              child: ListTile(
                title: Text(profileLabel(profile)),
                subtitle: Text(profileBlurb(profile)),
                selected: profile == widget.currentProfile,
                onTap: () => widget.onPicked(profile),
              ),
            ),
        ],
      ),
    );
  }
}
