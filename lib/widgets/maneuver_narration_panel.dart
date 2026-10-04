import 'package:flutter/material.dart';
import 'package:localization_fallback/localization_fallback.dart'
    show LocalizationMode;

import '../l10n/app_localizations.dart';
import '../services/drive_hud_localizer.dart';
import '../services/maneuver_narration.dart';
import 'advisory_cards.dart' show kCautionTextOnAmber;
import 'keep_together.dart';
import 'kv_row.dart';

/// Where the icy-turn mark's truth comes from.
///
/// The mark and the spoken line are the same shape either way; what differs is
/// what her card is ENTITLED to say about the road, and whether the voice
/// carries the test-value prefix.
enum IcyTurnSource {
  /// No ice reaches the next turn.
  none,

  /// A MEASURED radiative-frost watch, from the live JMA observation.
  measured,

  /// The simulated road condition, which only the development page can set.
  testValue,
}

/// (e) The next maneuver, narrated ONLY when the honest position allows it.
///
/// The panel reflects the SAME gate the announcer uses, so what is shown
/// on-screen matches what would be spoken — including SUPPRESSION, because a
/// wrong "turn right" is confidently-wrong whether heard OR seen.
///
/// Its own widget since 2026-10-04. Until then it was the private
/// `_maneuverNarrationPanel` method in `lib/main.dart`, which no test could
/// pump, so the next-turn goldens drew a copy of it, and the copy drifted from
/// the app twice with nothing going red. It draws and decides nothing: the
/// app's state reads the drive brain and passes what it read. When there is no
/// next maneuver the app draws its placeholder instead of this panel.
class ManeuverNarrationPanel extends StatelessWidget {
  const ManeuverNarrationPanel({
    super.key,
    required this.preview,
    required this.mode,
    required this.isMockPosition,
    required this.icySource,
    required this.onNarrate,
    required this.lastNarration,
    required this.speechUnverified,
    required this.hapticUnverified,
  });

  /// The gate's decision for the next maneuver.
  final ManeuverNarration preview;

  /// The drive brain's position mode, or null when its estimate is not this
  /// drive's; then no position row is drawn.
  final LocalizationMode? mode;

  /// Whether the position is the test position, not a GPS fix.
  final bool isMockPosition;

  /// Where an icy mark on this turn comes from.
  final IcyTurnSource icySource;

  /// Narrates the next maneuver through the drive HUD's announcer.
  final VoidCallback onNarrate;

  /// The decision the last narration was dispatched with, or null before any.
  final ManeuverNarration? lastNarration;

  /// Whether the speech channel has not confirmed it can speak.
  final bool speechUnverified;

  /// Whether the haptic channel has not confirmed it can vibrate.
  final bool hapticUnverified;

  static const DriveHudLocalizer _driveHudText = DriveHudLocalizer();

  @override
  Widget build(BuildContext context) {
    final mode = this.mode;

    // The banner's state in the app's language (2026-09-15). Until then it was
    // the gate's internal name and an English reason in every language; the
    // reason is carried by the position row above and by her line.
    final l = AppL10n.of(context);
    // Each state carries a mark at the head of its line, and the state in
    // which she is not told the turn carries a form of its own (2026-10-04).
    // Until then the three were one rounded block told apart by fill alone,
    // 1.08 to 1.23:1 apart in luminance, so with colour lost (a colour-vision
    // deficiency, glare, a dim panel) only the words told them apart, and
    // words are read, not glanced. The marks: a speaker for read aloud, a
    // question mark for read aloud with a request to check, a crossed speaker
    // for not read aloud; not the warning sign or the snowflake, which on this
    // page already mean a raised caution and a frozen road. A speaker and a
    // crossed speaker are nearly one shape on their own (their silhouettes
    // overlap at 0.739), so not read aloud is also drawn as an empty frame on
    // the card's own colour. test/widgets/maneuver_banner_states_test.dart
    // holds all of this with the words masked and colour taken away.
    final (Color bg, Color fg, String tier, IconData mark, bool outlined) =
        switch (preview.confidence) {
      NarrationConfidence.speak => (
          Colors.green.shade100,
          Colors.green.shade900,
          l.maneuverTierSpeak,
          Icons.volume_up,
          false,
        ),
      // amber.shade900 here was 2.38:1 (2026-09-15). No position the app
      // gives the drive brain reaches this state today, so no rendered test
      // of the app reaches it; kCautionTextOnAmber on amber.shade100 is 7.16:1.
      NarrationConfidence.hedge => (
          Colors.amber.shade100,
          kCautionTextOnAmber,
          l.maneuverTierHedge,
          Icons.help_outline,
          false,
        ),
      NarrationConfidence.suppressed => (
          Theme.of(context).colorScheme.surfaceContainerLow,
          Colors.blueGrey.shade900,
          l.maneuverTierSuppressed,
          Icons.volume_off,
          true,
        ),
    };
    // The mark grows with her text size, as the words beside it do.
    final markSize = MediaQuery.textScalerOf(context).scale(18);

    // When suppressed there is NO maneuver phrase to show (the decision carries
    // empty text by construction) — show the honest "guidance paused" line, not
    // a turn.
    // In the app's resolved locale (2026-09-14; was a Japanese literal on every
    // device), like the narration text it stands in for.
    final herLine = preview.confidence == NarrationConfidence.suppressed
        ? l.maneuverGuidancePaused
        : preview.text;
    // Each Japanese line is DRAWN so that it breaks only between two phrases
    // (2026-10-04, keep_together.dart): at her width it broke inside 可能｜性,
    // ご判｜断 and （現｜在地, and where it broke moved with her text size. What
    // she hears and what a screen reader reads are the plain lines.
    final herPhrases = preview.confidence == NarrationConfidence.suppressed
        ? l.maneuverPanelPhrases(herLine)
        : _driveHudText.maneuverLinePhrases(
            preview.routeManeuver.type,
            l.locale.languageCode,
            hedged: preview.confidence == NarrationConfidence.hedge,
            icy: preview.icyCoupled,
          );
    Text drawn(String line, List<String>? phrases,
        {Key? key, TextStyle? style}) {
      final span = keepPhrasesTogether(line, phrases);
      return span == null
          ? Text(key: key, line, style: style)
          : Text.rich(key: key, span, semanticsLabel: line, style: style);
    }

    // Not drawn since 2026-09-15, because they are for the people who build
    // the app and not for her: a paragraph naming the routing class, its
    // request flag and the gate's state names; a count of parsed maneuvers;
    // and a note that turn timing and hearing are unverified in this
    // environment. That bound is recorded in KNOWN_LIMITATIONS.md.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode != null)
          // The THIRD modeLabel site, and the
          // one an earlier change missed. It carries the SAME 現在地の信頼度 label as the
          // drive card's trust row, and nothing about a route depends on the
          // position being real — `_fetchRoute` in lib/main.dart returns only
          // on a missing tapped origin or destination, then on her routing
          // consent; it never reads the position. Until this line took isMock,
          // a route set with the
          // mock in force put two honesty labels for one fabricated fix on one
          // screen: the card said テスト位置, this panel said GPS 良好.
          kvRow(
              l.driveHudPositionTrustLabel,
              _driveHudText.modeLabel(mode, l.locale.languageCode,
                  isMock: isMockPosition)),
        // NOTE: the raw ENGLISH engine instruction is deliberately NOT rendered
        // to the driver — it would both leak English to a JA driver and show a
        // confident "turn" string even when the position gate suppresses it.
        // The driver sees only the gated, JA-localized narration banner below.
        const SizedBox(height: 8),
        Container(
          key: const Key('maneuver-narration-banner'),
          width: double.infinity,
          // The outlined banner gives its 2 dp border back from its padding,
          // so the mark and the words sit in the same place in every state.
          padding: EdgeInsets.all(outlined ? 10 : 12),
          decoration: BoxDecoration(
            color: bg,
            border: outlined ? Border.all(color: fg, width: 2) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Icon(
                    key: const Key('maneuver-narration-state-mark'),
                    mark,
                    color: fg,
                    size: markSize,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: drawn(
                      tier,
                      l.maneuverPanelPhrases(tier),
                      key: const Key('maneuver-narration-tier'),
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              drawn(herLine, herPhrases,
                  style: TextStyle(color: fg, fontSize: 15)),
              if (preview.icyCoupled &&
                  preview.confidence != NarrationConfidence.suppressed) ...[
                const SizedBox(height: 4),
                drawn(
                  l.maneuverIcyMark,
                  l.maneuverPanelPhrases(l.maneuverIcyMark),
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // THE MARK'S PROVENANCE, in the same glance as the mark.
                // Until 2026-09-23 this line said "test value" unconditionally,
                // which was true while a test value was the only thing that
                // could reach the mark. A measured radiative-frost watch can
                // now, and telling her the road was not measured when it WAS
                // would be this same defect inverted. Exactly one of the two
                // renders, and which one is the answer to "why am I being told
                // this turn is icy?".
                if (icySource == IcyTurnSource.measured)
                  drawn(
                    l.maneuverMeasuredRoadIceInForce,
                    l.maneuverPanelPhrases(l.maneuverMeasuredRoadIceInForce),
                    key: const Key('maneuver-measured-road-ice'),
                    style: TextStyle(color: fg, fontSize: 12),
                  )
                else
                  drawn(
                    l.maneuverTestRoadConditionInForce,
                    l.maneuverPanelPhrases(l.maneuverTestRoadConditionInForce),
                    key: const Key('maneuver-test-road-condition'),
                    style: TextStyle(color: fg, fontSize: 12),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              key: const Key('maneuver-narrate-button'),
              onPressed: onNarrate,
              icon: const Icon(Icons.record_voice_over),
              label: Text(l.maneuverNarrateButton),
            ),
            const SizedBox(width: 8),
            if (lastNarration != null)
              Expanded(
                // `shouldAnnounce` is a PRE-DISPATCH gate verdict, not a
                // delivery report: the announce is fire-and-forget and this
                // widget is built before either channel has answered. So the
                // first line says SENT, and the second says what the channels
                // did or did not report. The drive-HUD chips hold the same two
                // facts two Cards above; a driver reading this card is not
                // reading those.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key: const Key('maneuver-narration-result'),
                      lastNarration!.shouldAnnounce
                          ? l.maneuverNarrationSent
                          : l.maneuverNarrationNotSpoken,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    if (lastNarration!.shouldAnnounce &&
                        (speechUnverified || hapticUnverified)) ...[
                      const SizedBox(height: 4),
                      Text(
                        key: const Key(
                            'maneuver-narration-delivery-unverified'),
                        l.maneuverNarrationDeliveryUnverified(
                          speech: speechUnverified,
                          haptic: hapticUnverified,
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: kCautionTextOnAmber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
