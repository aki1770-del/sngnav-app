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
/// ⚑ AAA RULED ON THIS CONSTANT, 2026-09-23, AND DECLINED TO MOVE IT. Its
/// sentence, recorded verbatim from its own record
/// (`outputs/automotive-adas-analyst/r119_consent_reorder_safety_ruling_2026_09_23.md` §6)
/// rather than paraphrased by the seat the ruling constrains:
///
/// > Ruled by AAA 2026-09-23 under the D-VGC177-3 driver-dignity delegation.
/// > `separated` STANDS — not because separation is right, but because adjacency
/// > was never what made her consent informed. Measured: the control sits at
/// > 552–600 dp and the words at 1020 dp (1306 dp under a measured whiteout),
/// > against the 721 dp her phone gives the page; `_shareLocation` has no
/// > affirmative in-app consent act, so no arrangement of this prose constitutes
/// > consent. This constant is not the loom. It moves only when the affirmative
/// > consent act exists, and then it stops mattering.
///
/// The affirmative consent act itself is AAE's, not this seat's.
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
/// ⛑ MEASURED MARGIN AT THIS BOUND, 2026-09-23: **11 dp**, not the 285 dp the
/// clear state suggests. In a measured whiteout with no share the gap is
/// **710 dp** of the 721 allowed. One more wrapped line on the caution card
/// carries it over — the card grows above the disclosure. The same sentence is
/// at the card itself in `lib/main.dart`, because that is where a hand adding
/// to it will be standing.
///
/// ⚑ DO NOT RAISE THIS TO MAKE SOMETHING FIT. It was tempting to raise it once
/// already, on a 726 dp reading that turned out to be this guard rendering
/// Japanese paragraphs with no Japanese face — an instrument defect, not a real
/// breach. Raising it would have permanently loosened a driver-facing limit to
/// accommodate a font bug.
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
  // Printed in parts, because a single figure I could not decompose would be a
  // number I cannot explain, and this seat has had one of those before.
  // ⚑ The first version of this print emitted its own source text -- literal
  // ${...} -- because my shell heredoc mangled the escaping. An instrument that
  // prints its own recipe instead of a measurement is the same family as one
  // that prints a success-shaped value.
  final controlBottom = control.bottom + scroll;
  final disclosureTop = disclosure.top + scroll;
  // ignore: avoid_print
  print('CONSENT-GAP PARTS: control bottom=${controlBottom.toStringAsFixed(0)}dp'
      ' disclosure top=${disclosureTop.toStringAsFixed(0)}dp'
      ' scroll=${scroll.toStringAsFixed(0)}dp');
  return (disclosure.top + scroll) - (control.bottom + scroll);
}
