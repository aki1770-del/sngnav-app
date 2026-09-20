/// Advisory cards — renders one `Advisory` per card in the home page.
///
/// The source LABEL is the publisher's name in the page's language (`NWS` for
/// NOAA records; `気象庁` on the Japanese page and `JMA` on the English one —
/// see [AppL10n.advisoryJmaPublisher]). Event class + headline +
/// description +
/// area + effective + expires are all rendered verbatim per the
/// verbatim-relay discipline — the publisher's wording is the
/// substrate the driver decides on, not our paraphrase. No
/// translation; foreign-tourist UX (future slice) glosses alongside,
/// never replaces.
///
/// The publisher content (event class, headline, area, ...) is verbatim and
/// NOT translated; the app-owned STATE strings (empty / loading / error /
/// fetch actions) are localized for the driver via [AppL10n].
///
/// Empty state: an honest localized no-data line — does NOT fall back to a
/// stale snapshot. Loading state: spinner. Error state: a localized failure
/// line with nothing after it (no exception text, URL or status code, as
/// decided for the route line), plus the per-publisher `providerErrors` channel, which names the
/// publisher and not its exception.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Accessibility contrast floor — caution text/icon color on the amber-tinted
/// caution surfaces (`Colors.amber.shade50`, #FFF8E1). The Material pair
/// `amber.shade900` (#FF6F00) on that tint is ~2.6:1 — far below the WCAG AA
/// 4.5:1 floor at the 11–13 px sizes these honesty labels use, functionally
/// invisible to a reduced-contrast-sensitivity elderly reader. This dark
/// amber-brown measures ~7.9:1 on #FFF8E1.
const Color kCautionTextOnAmber = Color(0xFF6B4600);

/// The feed-health banner's fill — amber at 12% alpha, so it sits a little
/// DARKER than the card surface it composites over (measured on the rendered
/// pixels 2026-09-20: #F2EADA, L 0.828, against the card's #F0F4F8, L 0.900).
///
/// Named because a second widget now shares it. When the feed-health banner
/// and the retained-age label are BOTH on screen, the label takes this fill
/// instead of its own opaque `amber.shade50` (#FFF8E1, L 0.938). Two amber
/// fills that differ by 1.126:1 do not read as two blocks — they read as one
/// slab, and the eye then takes the loudest line in it. Making them literally
/// the same fill stops pretending they are separate and turns the pair into
/// one block with a headline and a subline.
const Color kStaleFeedFill = Color(0x1FFFA000);

/// Same floor for the orange-tinted staleness surface
/// (`Colors.orange.shade50`, #FFF3E0): `orange.shade900` (#E65100) is ~3.5:1
/// there; this dark orange-brown measures ~7.1:1.
const Color kCautionTextOnOrange = Color(0xFF8A3B00);

/// Fill for the CHRONIC coverage note — the one honesty state that is not a
/// degradation at all.
///
/// "No supported publisher covers this point" is a PERMANENT boundary of what
/// this app can answer. Retrying does not help, nothing is broken, and nothing
/// will change when the network recovers. Rendering it on the same amber as
/// the transient "we could not look right now" states made one tint carry four
/// different meanings, and taught the driver to read amber as noise. Blue-grey reads
/// as a standing note rather than an active caution, and is still clearly not
/// the calm grey of a real all-clear.
///
/// #ECEFF1 (`blueGrey.shade50`) under [kNoteTextOnBlueGrey] measures ~13:1,
/// well clear of the 4.5:1 contrast floor.
const Color kNoteFillBlueGrey = Color(0xFFECEFF1);

/// Text/icon colour for [kNoteFillBlueGrey] (`blueGrey.shade900`).
const Color kNoteTextOnBlueGrey = Color(0xFF263238);

/// Leading glyph for a TRANSIENT unknown — we tried to look, or cannot prove
/// we looked, right now. Both live in the bundled `SnGNavSymbols` subset
/// (U+26A0), so neither can tofu on a device whose system fonts lack them.
const String kGlyphTransientUnknown = '⚠';

/// Leading glyph for the CHRONIC coverage note (U+203B ※ — the Japanese
/// footnote/reference mark, which is exactly what this state is: a standing
/// caveat, not an alarm).
const String kGlyphChronicNote = '※';

class AdvisoryCards extends StatelessWidget {
  const AdvisoryCards({
    super.key,
    required this.loading,
    required this.result,
    required this.errorMessage,
    required this.onRefresh,
    this.retainedAgeMinutes,
    this.pointCovered = true,
  });

  final bool loading;
  final AdvisoryAggregateResult? result;
  final String? errorMessage;
  final VoidCallback onRefresh;

  /// False when NO registered publisher covers the queried point
  /// ([AdvisoryService.coversPoint]): nobody was queried, so an empty result
  /// is not a publisher statement and the positive all-clear line must not
  /// render — the honest "cannot be checked here" line renders instead.
  /// Defaults true (the pre-existing behavior) for callers that always query
  /// covered points; main.dart passes the real per-fetch read.
  final bool pointCovered;

  /// Non-null when the advisories in [result] were RETAINED from a prior
  /// successful fetch because the latest fetch failed (value = minutes since
  /// that prior fetch). Renders a visible stale banner — retained hazard data
  /// must never masquerade as current. Null = the result is fresh.
  final int? retainedAgeMinutes;

  @override
  Widget build(BuildContext context) {
    // These app-owned STATE strings render on the driver's Japanese surface; route
    // them through the l10n (the publisher-verbatim advisory content below is
    // NOT translated — that is faithful relay, not app chrome).
    final l = AppL10n.of(context);
    if (loading && result == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⚑ THE SAME ⚠ AND THE SAME AMBER AS THE OTHER "we could not get a
          // trustworthy answer" STATES, AND THE SENTENCE IS WHAT SEPARATES
          // THEM — the rule this surface already applies to the degraded and
          // lookup-incomplete banners below.
          //
          // Until 2026-09-20 this one banner was red.shade50 (#FFEBEE) while
          // those were amber.shade50 (#FFF8E1). Measured: the two fills are
          // 1.076:1 apart, so to an eye that has lost colour — glare on the
          // windscreen, peripheral vision, colour-vision deficiency — they
          // were never two blocks at all, and a driver watching this slot flip
          // between two fetches could not see that anything had changed. The
          // hue was carrying a distinction it could not deliver.
          //
          // It is NOT darkened to separate it on luminance: a fetch failure is
          // OUR plumbing, not her hazard, and making it the loudest block on
          // the screen is the same emphasis inversion this card was corrected
          // for on 2026-09-20. Red is now left to mean one thing here — a
          // severity actually in force.
          //
          // The KEY stays on the sentence Text: another seat's test reads
          // `tester.widget<Text>` through it, and a guard belonging to someone
          // else is not moved to suit this change.
          _honestyBanner(
            key: const Key('advisory-fetch-failed-banner'),
            textKey: const Key('advisory-fetch-failed'),
            glyph: kGlyphTransientUnknown,
            text: l.advisoryFetchFailed,
            fill: Colors.amber.shade50,
            color: kCautionTextOnAmber,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRefresh,
              child: Text(l.retry),
            ),
          ),
        ],
      );
    }
    final r = result;
    if (r == null) {
      // The words take the width the button leaves and wrap there. As a
      // natural-width text beside a Spacer, the row overflowed by 82 px at
      // system text scale 2.0 (rendered 2026-09-14).
      return Row(children: [
        Expanded(child: Text(l.advisoryNoFetchYet)),
        TextButton(onPressed: onRefresh, child: Text(l.advisoryFetch)),
      ]);
    }
    // On the driver's Japanese surface, LEAD with the authoritative
    // Japanese publisher (JMA / 気象庁). The English NWS card is unreadable
    // noise for an Akita driver, so it is ordered AFTER JMA and de-emphasized
    // (never hidden — dropping a safety card would be dishonest; it is present,
    // dimmed, and captioned as English reference). English locale keeps the
    // publisher's returned order.
    final isJa = Localizations.localeOf(context).languageCode == 'ja';
    final ordered = isJa ? _jmaFirst(r.advisories) : r.advisories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ⚑ FEED-HEALTH, ABOVE EVERYTHING — including a warning in force.
        //
        // A publisher document that has stopped being rewritten fails in two
        // directions and only one of them is visible below. If it lists
        // warnings, they render as live (Akita served a 雷注意報 from May for 88
        // days). If it lists nothing, the empty list is the identical value a
        // clear sky produces (Niigata, 90 days, zero warnings).
        //
        // `staleSources` is the aggregator's harvest of every provider that
        // implements `AdvisoryFeedFreshnessReporting` and reported itself
        // stale. It is what makes `canAssertNoAdvisory` false, so the all-clear
        // branch below already cannot fire — but suppressing a false all-clear
        // is silent, and she is left reading a dead warning with nothing
        // marking it. This says the quiet part out loud.
        //
        // Rendered FIRST and unconditionally, because it qualifies every row
        // beneath it: those rows may be months old. It is `minor`-weight in
        // colour — a feed-health fact, never a hazard, and it must not shout
        // over a real advisory in force.
        if (r.hasStaleSource)
          _honestyBanner(
            key: const Key('advisory_stale_feed_banner'),
            glyph: '⚠',
            text: isJa
                ? '気象情報の更新が止まっています'
                  '（${_worstStaleAgeText(r, isJa)}）。'
                  '以下の内容は最新ではない可能性があり、'
                  '警報が出ていない場合でも安全とは限りません。'
                : 'The weather feed has stopped updating '
                  '(${_worstStaleAgeText(r, isJa)}). Anything below may be out '
                  'of date, and no warning shown does not mean it is safe.',
            fill: kStaleFeedFill,
            // Was #B26A00 at w400. RENDERED 2026-09-20 in the state the
            // retention fix newly makes reachable (banner AND retained label
            // on screen together): that pair measured 3.544:1 on this fill —
            // BELOW the 4.5:1 body-text floor — while the retained label below
            // it sat at 7.903:1 in w600. The publisher's 88-day clock was the
            // quiet line and our own 10-minute fetch clock was the loud one,
            // so the number she takes away in a glance was the wrong one.
            // #6B4600 is this file's existing caution ink and measures 7.019:1
            // here. It stays LIGHTER than the advisory headline's #171C1F
            // (L 0.0751 vs 0.0111) at one size smaller, so the comment above
            // still holds: this must not shout over a warning in force, and
            // it does not.
            color: kCautionTextOnAmber,
            weight: FontWeight.w600,
          ),
        // B04 / B04-2 — the all-clear line is a POSITIVE claim ("no
        // advisories are in force"), and it is a claim about COMPLETENESS:
        // it is true only when every source was asked and every source
        // answered. An empty `advisories` list alone cannot back it — a
        // total feed outage produces exactly the same empty list as a clear
        // sky.
        //
        // The gate is `AdvisoryAggregateResult.canAssertNoAdvisory`
        // (condition_aggregator 0.0.8), which is false on ALL THREE
        // incomplete shapes: a provider errored, zero sources were asked, or
        // the result carries no provenance. B04 checked only the first of
        // those, so the other two still rendered 「この地点に有効な警報・注意報は
        // ありません。」 when the truth was "we could not look."
        //
        // Branch order is deliberate: the two shapes whose CAUSE we can name
        // (a publisher errored / no publisher covers this point) render
        // their specific honest line first; the all-clear renders only on a
        // provably complete lookup; anything left over falls to the
        // named-no-cause backstop. Absence must never render as calm.
        if (r.advisories.isEmpty && r.providerErrors.isNotEmpty)
          // TRANSIENT — we asked, and the publisher failed. Stepped DOWN from
          // the red fill it used to carry: an OUTAGE IS NOT A HAZARD, and a
          // full red banner made a feed failure shout louder than a real
          // extreme-severity advisory in force (which renders as a thin
          // severity border plus a 15%-alpha chip). The strongest fill on this
          // surface belongs to a warning that is actually in force; an unknown
          // gets the caution tint and says what it does not know.
          _honestyBanner(
            key: const Key('advisory-unknown-degraded'),
            glyph: kGlyphTransientUnknown,
            text: l.advisoryFetchUnknown,
            fill: Colors.amber.shade50,
            color: kCautionTextOnAmber,
          )
        else if (r.advisories.isEmpty && !pointCovered)
          // B04 sibling — an UNCOVERED point: nobody was asked, so the
          // positive all-clear would be a publisher claim nobody made.
          //
          // CHRONIC, not transient. This is the only one of the four honesty
          // states that will not change when the network recovers: no
          // supported publisher covers this point, and none will next cycle.
          // It used to share the amber of the "we could not look right now"
          // states, which made one tint mean four things. Blue-grey + ※ reads
          // as the standing coverage note it is — still plainly not the calm
          // grey of a real all-clear.
          _honestyBanner(
            key: const Key('advisory-no-covering-publisher'),
            glyph: kGlyphChronicNote,
            text: l.advisoryNoCoveringPublisher,
            fill: kNoteFillBlueGrey,
            color: kNoteTextOnBlueGrey,
          )
        else if (r.advisories.isEmpty && r.canAssertNoAdvisory)
          // B04-2 — the ONLY shape in which the positive all-clear is true:
          // every source was asked and every source answered
          // (`canAssertNoAdvisory`, condition_aggregator 0.0.8). Calm grey,
          // because this one genuinely is calm.
          Text(
            l.advisoryNoneActive,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          )
        else if (r.advisories.isEmpty)
          // B04-2 backstop — empty, nothing errored, the point IS covered,
          // and still the lookup cannot prove it was complete (no sources
          // asked, or a result carrying no provenance at all). The two
          // branches above name a CAUSE; this one honestly reports that we
          // have none to name. It exists so that a completeness claim is
          // impossible to make by accident: any future result-construction
          // site that forgets `sourcesQueried` lands here, not on a
          // fabricated clear.
          // TRANSIENT, same class as the degraded banner above — we cannot
          // prove we looked. Same ⚠ + amber; the SENTENCE is what separates
          // them, because this one has no cause to name.
          _honestyBanner(
            key: const Key('advisory-lookup-incomplete'),
            glyph: kGlyphTransientUnknown,
            text: l.advisoryLookupIncomplete,
            fill: Colors.amber.shade50,
            color: kCautionTextOnAmber,
          )
        else ...[
          // Retained (stale) hazard data carries a visible age label;
          // trust the hazard, but never let it masquerade as current.
          //
          // ⚑ TWO CLOCKS, AND ONLY ONE OF THEM IS THE HAZARD.
          // This label reports OUR fetch clock ("fetched 10 minutes ago").
          // The banner above reports the PUBLISHER'S clock ("stopped updating
          // about 88 days ago"). When both are on screen the publisher's is
          // the one she must take away, and until 2026-09-20 this label was
          // the loud one: opaque brighter fill, w600, and its sentence opens
          // with 未更新 / "Stale —", so the fast reading composed
          // "not updated — 10 minutes" over a document three months old.
          // Rendered and seen at the phone's geometry; the frames are in this
          // seat's record.
          //
          // So when `hasStaleSource` is true this label becomes the SUBLINE of
          // the block above: same fill, regular weight, no separating margin.
          // It is not hidden — it is provenance and she is owed it — it simply
          // stops outranking the older fact. ALONE (a plain fetch failure,
          // publisher healthy) it is the only staleness line on the surface
          // and keeps its original opaque fill and w600.
          if (retainedAgeMinutes != null)
            Container(
              key: const Key('advisory-retained-stale'),
              // Subordinate: the banner's own horizontal padding, so the two
              // share one left edge. Alone: unchanged.
              padding: r.hasStaleSource
                  ? const EdgeInsets.fromLTRB(8, 6, 8, 8)
                  : const EdgeInsets.all(6),
              margin: EdgeInsets.only(bottom: r.hasStaleSource ? 0 : 4),
              color: r.hasStaleSource ? kStaleFeedFill : Colors.amber.shade50,
              // liveRegion — current→stale is a safety-relevant transition;
              // announce it. Contrast + size: this label's entire job is
              // stopping stale hazard data from masquerading as current, so
              // it must itself be readable (kCautionTextOnAmber ≥4.5:1;
              // 13 px, up from 11).
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subordinate only: an invisible copy of the banner's own
                    // ⚠, kept at full size so this line's text starts on the
                    // banner text's left edge at ANY text scale and in any
                    // face. Measured before this was added: the subline began
                    // 20 logical px LEFT of the headline's text — left of even
                    // the ⚠ itself — so its first word 未更新 jutted out and
                    // read as the start of a new block. A hard-coded indent
                    // would drift the moment the glyph, size or scale changes;
                    // reserving the real glyph's box cannot.
                    if (r.hasStaleSource) ...[
                      ExcludeSemantics(
                        child: Visibility(
                          visible: false,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(
                            kGlyphTransientUnknown,
                            style: TextStyle(
                                color: kCautionTextOnAmber, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        l.advisoryRetainedStale(retainedAgeMinutes!),
                        style: TextStyle(
                          color: kCautionTextOnAmber,
                          fontSize: 13,
                          fontWeight: r.hasStaleSource
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ...ordered.map((a) => _AdvisoryCard(
                advisory: a,
                deEmphasize:
                    isJa && a.source == AdvisorySource.nwsUnitedStates,
              )),
        ],
        if (r.providerErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final err in r.providerErrors)
            Container(
              padding: const EdgeInsets.all(6),
              margin: const EdgeInsets.only(bottom: 4),
              color: Colors.amber.shade50,
              child: Text(
                err.source == AdvisorySource.other
                    ? l.advisoryFetchFailedBeforeAnyPublisher
                    : l.advisoryPublisherErrored(_sourceLabel(err.source, l)),
                // Same amber surface — same contrast floor.
                style:
                    const TextStyle(color: kCautionTextOnAmber, fontSize: 11),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onRefresh,
            child: Text(l.advisoryReFetch),
          ),
        ),
      ],
    );
  }

  /// Stable partition: JMA (気象庁) advisories to the front, everything else
  /// after, each group keeping the publisher's returned order. Used only on
  /// the Japanese surface so the driver reads the authoritative Japanese source first.
  static List<Advisory> _jmaFirst(List<Advisory> list) {
    final jma = <Advisory>[];
    final rest = <Advisory>[];
    for (final a in list) {
      if (a.source == AdvisorySource.jmaJapan) {
        jma.add(a);
      } else {
        rest.add(a);
      }
    }
    return [...jma, ...rest];
  }
}

class _AdvisoryCard extends StatelessWidget {
  const _AdvisoryCard({required this.advisory, this.deEmphasize = false});

  final Advisory advisory;

  /// When true (Japanese surface, English NWS card), the card is dimmed and
  /// captioned as English reference material — present but not the primary
  /// read. Never hides the card (dropping safety data would be dishonest).
  final bool deEmphasize;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: _severityColor(advisory.severity)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (deEmphasize) ...[
            Text(
              AppL10n.of(context).englishReferenceNote,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 10),
            ),
            const SizedBox(height: 4),
          ],
          // ⚑ A Wrap, NOT A Row, AND THE ROW WAS CLIPPING HER WARNING'S START
          // TIME AT THE DEFAULT TEXT SCALE.
          //
          // As a Row with a Spacer this head overflowed on her phone's
          // measured width (1080x2340, DPR 2.75) at every text scale except
          // Japanese at 1.0 — the one case that had ever been measured:
          //   en  1.0  21-54 px   en  1.5  182-232 px   en  2.0  343-409 px
          //   ja  1.0  clean      ja  1.5   98-148 px   ja  2.0  231-298 px
          // (per severity word, measured 2026-09-20). Flutter's own words for
          // that condition are "there is content that cannot be seen", and
          // what could not be seen was the publisher's name and the START TIME
          // of the warning — the third age fact on this screen. This app's
          // default profile is ageingRural and she is an elderly driver; 2.0
          // is her setting, not a corner case.
          //
          // A Wrap cannot overflow: a run that does not fit takes the next
          // line. The cost, stated: at 1.0 the start time no longer sits
          // flush right, it follows the pill. Nothing is lost and nothing is
          // clipped, at any scale, in either language.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(
                _sourceLabel(advisory.source, AppL10n.of(context)),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                  fontSize: 12,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _severityColor(advisory.severity).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _severityLabel(advisory.severity, AppL10n.of(context)),
                  // ⚑ NOT _severityColor. The hue that paints the border and
                  // the 15%-alpha fill is too light to be READ on that fill:
                  // measured on the rendered pixels 2026-09-20, every severity
                  // sat below the 4.5:1 floor and the worst was `moderate` at
                  // 1.843:1 — the level a 大雪警報 carries. The severity word on
                  // a snow warning was the word she was least able to read.
                  style: TextStyle(
                    color: _severityInk(advisory.severity),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (advisory.effective != null)
                Text(
                  AppL10n.of(context)
                      .advisoryEffectiveAt(fmt.format(advisory.effective!.toLocal())),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // eventClass verbatim — the publisher's exact wording.
          Text(
            advisory.eventClass,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (advisory.areaDescription.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              advisory.areaDescription,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
          if (advisory.headline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              advisory.headline,
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (advisory.description.isNotEmpty &&
              advisory.description != advisory.headline) ...[
            const SizedBox(height: 4),
            Text(
              advisory.description,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            ),
          ],
          if (advisory.expires != null) ...[
            const SizedBox(height: 4),
            Text(
              AppL10n.of(context)
                  .advisoryExpiresAt(fmt.format(advisory.expires!.toLocal())),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            ),
          ],
          const SizedBox(height: 4),
          // The publisher's attribution is the QUIETEST line on the card and
          // stays so — by being the smallest, not by being unreadable. At
          // grey.shade500 it measured 2.424:1 on the card surface: an
          // attribution a reduced-contrast reader cannot read is an
          // attribution we are not really making.
          Text(
            advisory.source.attributionString,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 10),
          ),
        ],
      ),
    );
    // ⚑ THE DIMMING IS GONE, AND THE CAPTION DOES THE WORK IT WAS DOING.
    //
    // `Opacity(0.55)` washed EVERY run on this card toward the surface behind
    // it. Measured on the rendered pixels 2026-09-20: the event class fell to
    // 3.753:1, the area and description to 2.290:1, the attribution to
    // 1.567:1 — the whole card below the 4.5:1 floor, including the words
    // naming the hazard. No opacity below about 0.95 keeps the floor, and 0.95
    // is not a de-emphasis. The intent in the line this replaces was right —
    // "never hides the card (dropping safety data would be dishonest)" — and a
    // wash that puts every word under the readable floor is nearer to hiding
    // it than to showing it.
    //
    // Subordination is carried instead by the caption above ("English
    // (reference)" / 英語の情報（参考）) and by the card's place in the order:
    // a channel that says what it means in words rather than one that spends
    // her contrast budget. Same reasoning as this seat's founding incident,
    // where three states were separated by fill alone.
    return card;
  }
}

/// The publisher's name as her page shows it, in the page's language. A source
/// with no name of its own reads in the page's language too
/// ([AppL10n.advisoryOtherSource]).
///
/// Until 2026-09-18, JMA was the literal 気象庁 in every locale, so the
/// English page named one publisher two ways — 気象庁 in the card head and
/// "Could not fetch from 気象庁." on the error line, beside nine other English
/// strings that all say JMA. See [AppL10n.advisoryJmaPublisher]. This is the
/// publisher's NAME; the verbatim publisher CONTENT below is untouched.
String _sourceLabel(AdvisorySource source, AppL10n l) {
  switch (source) {
    case AdvisorySource.nwsUnitedStates:
      return 'NWS';
    case AdvisorySource.jmaJapan:
      return l.advisoryJmaPublisher;
    case AdvisorySource.metNorway:
      return 'MET Norway';
    case AdvisorySource.other:
      return l.advisoryOtherSource;
  }
}

/// One honesty state, rendered so it separates from its siblings AT A GLANCE.
///
/// [glyph] is the leading mark ([kGlyphTransientUnknown] ⚠ for "we could not
/// look right now", [kGlyphChronicNote] ※ for the standing coverage note).
/// Both are in the bundled `SnGNavSymbols` subset, so neither tofus on a
/// device whose system fonts lack them.
///
/// The glyph is rendered as its OWN [Text], never folded into the localized
/// sentence: the sentence must stay byte-identical to the one the in-drive
/// glance shows for the same state, so the card and the glance can never drift
/// into two different statements about one fact.
///
/// `liveRegion` — the all-clear→unknown flip is exactly the state change these
/// banners exist to make loud, so assistive tech must ANNOUNCE it rather than
/// merely hold it in the tree (accessibility floor). The glyph sits outside the
/// announced text and is marked [ExcludeSemantics] so a screen reader speaks
/// the sentence, not "warning sign".
Widget _honestyBanner({
  required Key key,
  required String glyph,
  required String text,
  required Color fill,
  required Color color,
  /// Optional key on the SENTENCE, for a caller whose existing guard finds the
  /// line as a `Text` rather than as the block around it.
  Key? textKey,
  // Default w400 so the three transient/chronic banners are untouched. Only
  // the feed-health banner passes w600, because it is the only one of the four
  // that can appear ABOVE another amber block carrying a second, smaller age.
  FontWeight weight = FontWeight.w400,
}) =>
    Container(
      key: key,
      padding: const EdgeInsets.all(8),
      color: fill,
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                glyph,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                key: textKey,
                style:
                    TextStyle(color: color, fontSize: 13, fontWeight: weight),
              ),
            ),
          ],
        ),
      ),
    );

/// The severity pill's text, in the page's language.
///
/// Changed 2026-09-19. Until then the pill drew
/// `advisory.severity.name` — the raw Dart enum token — so the Japanese card
/// read the English word `severe` beside 気象庁 and 大雪警報. Seen in a
/// rendered frame of the Japanese card head during review, and fixed here.
///
/// Exhaustive on the enum, deliberately: a `String` switch on
/// `severity.name` would fall through silently if the package added a level,
/// and a severity that falls through is a severity she is not told.
/// This mirrors [_severityColor] one-for-one so colour and word can never
/// describe different levels.
///
/// The words are OUR scale, not JMA's — see [AppL10n.advisorySeveritySevere].
String _severityLabel(AdvisorySeverity severity, AppL10n l) {
  switch (severity) {
    case AdvisorySeverity.extreme:
      return l.advisorySeverityExtreme;
    case AdvisorySeverity.severe:
      return l.advisorySeveritySevere;
    case AdvisorySeverity.moderate:
      return l.advisorySeverityModerate;
    case AdvisorySeverity.minor:
      return l.advisorySeverityMinor;
    case AdvisorySeverity.unknown:
      return l.advisorySeverityUnknown;
  }
}

/// The severity word's INK — dark enough to be read on the pill it sits in.
///
/// Mirrors [_severityColor] and [_severityLabel] one-for-one, exhaustively on
/// the enum, for the reason already recorded above: a severity that falls
/// through is a severity she is not told, and colour, word and ink must never
/// describe different levels.
///
/// WHY IT IS NOT [_severityColor]. That hue paints the border and the
/// 15%-alpha pill fill, where it works. As the ink ON that fill it does not:
/// measured from the rendered pixels at the phone's geometry on 2026-09-20,
/// every severity sat below the WCAG AA 4.5:1 floor for 11 px text, and the
/// two that matter most were the worst.
///
///   severity   fill       old ink   was        now       is
///   extreme    #ECD6DA    #D32F2F   3.604:1    #8E0000   7.068:1
///   severe     #F0E0D3    #EF6C00   2.393:1    #8A3B00   6.026:1
///   moderate   #F2E5D3    #FF8F00   1.843:1    #6B4600   6.766:1
///   minor      #D0E1F2    #1976D2   3.448:1    #0D47A1   6.467:1
///   unknown    #DEE1E4    #757575   3.510:1    #424242   7.655:1
///
/// `moderate` is the level a 大雪警報 carries. Hue is preserved — each ink is
/// the dark end of its own severity's colour, so the pill still reads amber,
/// orange, red, blue or grey at a glance; only the word got legible. The two
/// middle values are the same as [kCautionTextOnOrange] and
/// [kCautionTextOnAmber], arrived at by the same measurement rather than by
/// reference, and kept separate so a change to a banner cannot silently move a
/// severity word.
Color _severityInk(AdvisorySeverity severity) {
  switch (severity) {
    case AdvisorySeverity.extreme:
      return const Color(0xFF8E0000);
    case AdvisorySeverity.severe:
      return const Color(0xFF8A3B00);
    case AdvisorySeverity.moderate:
      return const Color(0xFF6B4600);
    case AdvisorySeverity.minor:
      return const Color(0xFF0D47A1);
    case AdvisorySeverity.unknown:
      return const Color(0xFF424242);
  }
}

Color _severityColor(AdvisorySeverity severity) {
  switch (severity) {
    case AdvisorySeverity.extreme:
      return Colors.red.shade700;
    case AdvisorySeverity.severe:
      return Colors.orange.shade800;
    case AdvisorySeverity.moderate:
      return Colors.amber.shade800;
    case AdvisorySeverity.minor:
      return Colors.blue.shade700;
    case AdvisorySeverity.unknown:
      return Colors.grey.shade600;
  }
}

/// Worst (largest) measured feed age across every stale source, rendered the
/// way the publisher's own notice renders it: days once past a day, hours
/// below. Reads the aggregator's harvest; never re-derives an age of its own.
String _worstStaleAgeText(AdvisoryAggregateResult r, bool isJa) {
  // `age` is NULLABLE, and a null is not a zero. A source can be known stale
  // (its document carries no readable timestamp) without its age being
  // measurable. Rendering that as "about 0 hours" would report an UNMEASURED
  // quantity as a measured one, and understate it maximally — the same defect
  // class as an absent accuracy read as 0.0.
  Duration? worst;
  for (final s in r.staleSources) {
    final a = s.age;
    if (a != null && (worst == null || a > worst)) worst = a;
  }
  if (worst == null) return isJa ? '期間不明' : 'duration unknown';
  final d = worst.inDays;
  if (d >= 1) return isJa ? '約$d日' : 'about $d day${d == 1 ? '' : 's'}';
  final h = worst.inHours;
  return isJa ? '約$h時間' : 'about $h hour${h == 1 ? '' : 's'}';
}
