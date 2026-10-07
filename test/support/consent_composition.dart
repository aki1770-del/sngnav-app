/// The relationship between the share CONTROL and the DISCLOSURE, held by an
/// assertion instead of by two pictures and a comment.
///
/// ⚑ WHY THIS EXISTS, written before the act. Enumerated from both sides on
/// 2026-09-23: nine test sites named the disclosure, thirty-three named the
/// share control, and **none of the forty-two asserted any spatial, ordering or
/// same-screen relationship between them.** The composition was carried by two
/// golden captures and a comment, and on 2026-09-23 both pictures went red at
/// once when the disclosure was moved.
///
/// ⚑ WHAT THIS FILE DOES NOT DECIDE. Whether the control and the disclosure
/// SHOULD stand together is a ruling for the safety review, not for this file.
/// [kDeclaredConsentComposition] records what the page DOES, never that it is
/// right. The guard beside it fails in BOTH directions, so a move apart is
/// caught exactly as loudly as a move back together.
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

/// ⚑ DECLARED AND DATED — a record of the state, NOT a finding that the state
/// is acceptable.
///
/// 2026-09-23: the two disclosure paragraphs were moved out of the map card to
/// below the caution card, so that her page reached a road-state card sooner,
/// and this was declared [ConsentComposition.separated]. A safety review ruled
/// that day that `separated` stood, "not because separation is right, but
/// because adjacency was never what made her consent informed": the share
/// control then had no consent act of its own, so no arrangement of this prose
/// constituted consent. It said the constant would move only when such an act
/// existed, "and then it stops mattering".
///
/// The act was built the same day: 現在地を共有 opens a consent dialog that
/// carries where her coordinates go word for word and needs her tap before any
/// OS prompt. The dialog does not carry the other connections
/// ([AppL10n.egressDisclosure]); those are read on the page only.
///
/// 2026-10-07: the move was WITHDRAWN and this returns to
/// [ConsentComposition.together], the page as it stood before 2026-09-23. On the
/// page as it then was, the move put the words 780 dp below the control at a
/// clear launch and 1070 dp in a measured whiteout, past [kMaxDisclosureGapDp],
/// and it brought the rung onto her first screen in none of the states
/// measured. The rung reached her first screen by moving first inside its own
/// card, which did not need the move.
const ConsentComposition kDeclaredConsentComposition =
    ConsentComposition.together;

/// The furthest the disclosure may sit below the control, whichever way the
/// composition is declared.
///
/// 721 dp is what her phone gives the page, measured on a device frame. The
/// bound is stated as a PRINCIPLE rather than fitted to a number: **the words
/// may be one scroll on from the control, and may not come to mean three.** It
/// exists so that the next hand to take space from this page cannot push the
/// words out of reach without this failing.
///
/// ⚑ DO NOT RAISE THIS TO MAKE SOMETHING FIT. It was tempting twice: once on a
/// 726 dp reading that turned out to be this guard rendering Japanese
/// paragraphs with no Japanese face, and once (2026-10-07) when the disclosure
/// move failed it by 59 dp and 349 dp. The first was an instrument defect; the
/// second was the move, and the move was withdrawn instead.
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
  // An empty match is UNMEASURED, never absence. A missing
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
  // Printed in parts, because a single figure that cannot be decomposed is a
  // number nobody can explain.
  final controlBottom = control.bottom + scroll;
  final disclosureTop = disclosure.top + scroll;
  // ignore: avoid_print
  print('CONSENT-GAP PARTS: control bottom=${controlBottom.toStringAsFixed(0)}dp'
      ' disclosure top=${disclosureTop.toStringAsFixed(0)}dp'
      ' scroll=${scroll.toStringAsFixed(0)}dp');
  return (disclosure.top + scroll) - (control.bottom + scroll);
}
