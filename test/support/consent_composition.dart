/// The relationship between the share CONTROL and the DISCLOSURE, held by an
/// assertion instead of by two pictures and a comment.
///
/// ⚑ WHY THIS EXISTS, written before the act (OPS-070(B)). Enumerated from both
/// sides on 2026-09-23: nine test sites name the disclosure, thirty-three name
/// the share control, and **zero of the forty-two assert any spatial, ordering
/// or same-screen relationship between them.** The one near-miss,
/// `location_consent_semantics_test.dart:90`, uses the disclosure only as a
/// WIDTH reference — and since the disclosure moved to a card of its own that
/// comparison spans a card boundary, so it holds by coincidence rather than by
/// design. The composition was carried by two golden captures and a comment,
/// and on 2026-09-23 both pictures went red at once. The gap was not created by
/// that change; the change walked through it.
///
/// ⚑ WHAT THIS FILE DOES NOT DECIDE, and must never be read as deciding.
/// Whether the control and the disclosure SHOULD stand together is a ruling for
/// AAA, and this seat does not hold it. [kDeclaredConsentComposition] records
/// what the page DOES, never that it is right. When AAA rules, the ruling moves
/// this one constant and its reason — the guard beside it does not change, and
/// it fails in BOTH directions, so a move back together is caught exactly as
/// loudly as a move further apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the disclosure stands relative to the control that sends her position.
enum ConsentComposition {
  /// One object: the control and the words share a card.
  together,

  /// Two objects: she meets the words by scrolling on from the control.
  separated,
}

/// ⚑ DECLARED, DATED, AND PENDING AAA'S RULING — this is a record of the state,
/// NOT a finding that the state is acceptable.
///
/// 2026-09-23, HIE R119. Until this date the control and both disclosure
/// paragraphs shared the map card. They were separated so that her page reaches
/// a road-state card sooner: 352 dp of this prose, with the alpha banner, put
/// 714 characters above her first road-state word, which is five characters
/// long, and the caution card began at 1008 dp of a 3203 dp page. After the
/// move the caution card's title is at 648 dp, above the 721 dp her phone gives
/// the page.
///
/// The cost that rides with it: `_shareLocation` carries NO in-app consent
/// dialog, so the next thing after her tap is the OS permission prompt, and the
/// app's own account of where her coordinates go is now a card further on.
const ConsentComposition kDeclaredConsentComposition =
    ConsentComposition.separated;

/// The furthest the disclosure may sit below the control while the declaration
/// is [ConsentComposition.separated].
///
/// 721 dp is what her phone gives the page, measured on a device frame and
/// carried in HIE bylaws HIE-14. The bound is stated as a PRINCIPLE rather than
/// fitted to today's number: **separated may mean one scroll on from the
/// control, and may not come to mean three.** Measured 2026-09-23, the real gap
/// is well inside it; the band exists so that the next hand to take space from
/// this page cannot push the words out of reach without this failing.
const double kMaxDisclosureGapDp = 721;

const Key kShareControlKey = Key('share-location-button');
const Key kDisclosureKey = Key('location-disclosure');

/// What the RENDERED page does, read from the tree rather than from source.
///
/// [ConsentComposition.together] iff the control and the disclosure share a
/// `Card` ancestor. Structural on purpose: it does not depend on a dp figure,
/// so it cannot drift with a padding change.
ConsentComposition renderedConsentComposition(WidgetTester tester) {
  final control = find.byKey(kShareControlKey);
  final disclosure = find.byKey(kDisclosureKey);
  // C3 discipline: an empty match is UNMEASURED, never absence. A missing
  // element is a failure of this reader, not an answer about the page.
  if (control.evaluate().isEmpty) {
    throw TestFailure('consent composition UNMEASURED: no $kShareControlKey on '
        'this page. An empty match is not an answer.');
  }
  if (disclosure.evaluate().isEmpty) {
    throw TestFailure('consent composition UNMEASURED: no $kDisclosureKey on '
        'this page. An empty match is not an answer.');
  }
  final shared = find
      .ancestor(of: control, matching: find.byType(Card))
      .evaluate()
      .toSet()
      .intersection(find
          .ancestor(of: disclosure, matching: find.byType(Card))
          .evaluate()
          .toSet());
  return shared.isEmpty
      ? ConsentComposition.separated
      : ConsentComposition.together;
}

/// The gap in dp from the bottom of the control to the top of the disclosure,
/// in PAGE coordinates — so it is not an artefact of where the viewport sits.
///
/// Negative when the disclosure is ABOVE the control, which is itself a state
/// worth failing on: she would read where her coordinates go before she is
/// offered the control that sends them, and nothing in this app has ever drawn
/// it that way.
double disclosureGapBelowControlDp(WidgetTester tester) {
  final scroll = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;
  final control = tester.getRect(find.byKey(kShareControlKey));
  final disclosure = tester.getRect(find.byKey(kDisclosureKey));
  return (disclosure.top + scroll) - (control.bottom + scroll);
}
