/// Slice 4 — driver-state chip rail.
///
/// Renders the four current state options as a horizontal chip rail.
/// The currently active state is selected; if the upstream service
/// has surfaced a proposal for a different state, that proposal chip
/// is highlighted with a distinct outline and a small "tap to confirm"
/// hint. Tapping a chip calls onAffirm with that state.
///
/// Passive-propose / active-affirm pattern: this widget never silently
/// commits a state change. The proposed-state highlight is a hint to
/// the driver, not a state change. The active state changes only when
/// the driver taps a chip.
///
/// Architectural invariant: this widget reads ONLY a list of
/// (DriverState, isActive, isProposed) tuples plus a callback. It does
/// NOT branch on DriverProfile. The visual treatment of the chips is
/// identical for every profile.
library;

import 'package:flutter/material.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Render a chip rail for the four driver states. The active state
/// is selected; if proposedState is non-null and different from
/// activeState, that chip wears an outlined "proposed" decoration.
class DriverStateChipRail extends StatelessWidget {
  final DriverState activeState;
  final DriverState? proposedState;
  final ValueChanged<DriverState> onAffirm;

  const DriverStateChipRail({
    super.key,
    required this.activeState,
    required this.proposedState,
    required this.onAffirm,
  });

  @override
  Widget build(BuildContext context) {
    final hint = proposedState != null && proposedState != activeState
        ? 'Suggested: ${stateLabel(proposedState!)} — tap to confirm.'
        : 'Tap a state to update how alerts are tuned.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final state in DriverState.values)
              _StateChip(
                state: state,
                isActive: state == activeState,
                isProposed:
                    proposedState != null && state == proposedState && state != activeState,
                onTap: () => onAffirm(state),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

/// Plain-English label for a state. Mapped here rather than via
/// enum.name so the user-facing copy is reviewable without touching
/// the core package.
String stateLabel(DriverState state) {
  switch (state) {
    case DriverState.alert:
      return 'Alert';
    case DriverState.fatigued:
      return 'Fatigued';
    case DriverState.distracted:
      return 'Distracted';
    case DriverState.impairedVisibility:
      return 'Impaired visibility';
  }
}

class _StateChip extends StatelessWidget {
  final DriverState state;
  final bool isActive;
  final bool isProposed;
  final VoidCallback onTap;
  const _StateChip({
    required this.state,
    required this.isActive,
    required this.isProposed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = isProposed
        ? RoundedRectangleBorder(
            side: BorderSide(color: Colors.amber.shade700, width: 2),
            borderRadius: BorderRadius.circular(16),
          )
        : null;
    return ChoiceChip(
      key: ValueKey('driver-state-chip-${state.name}'),
      selected: isActive,
      label: Text(stateLabel(state)),
      onSelected: (_) => onTap(),
      shape: shape,
    );
  }
}
