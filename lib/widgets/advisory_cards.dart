/// Advisory cards — renders one `Advisory` per card in the home page.
///
/// Source label is publisher-verbatim (`NWS` for NOAA records;
/// `気象庁` for JMA records). Event class + headline + description +
/// area + effective + expires are all rendered verbatim per the
/// verbatim-relay discipline — the publisher's wording is the
/// substrate the driver decides on, not our paraphrase. No
/// translation; foreign-tourist UX (future slice) glosses alongside,
/// never replaces.
///
/// The publisher content (event class, headline, area, ...) is verbatim and
/// NOT translated; the app-owned STATE strings (empty / loading / error /
/// fetch actions) are localized for HER via [AppL10n] (D4).
///
/// Empty state: an honest localized no-data line — does NOT fall back to a
/// stale snapshot. Loading state: spinner. Error state: the exception message
/// surfaced (verbatim) behind a localized prefix, plus the per-publisher
/// `providerErrors` channel.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// OPS-059 contrast floor — caution text/icon color on the amber-tinted
/// caution surfaces (`Colors.amber.shade50`, #FFF8E1). The Material pair
/// `amber.shade900` (#FF6F00) on that tint is ~2.6:1 — far below the WCAG AA
/// 4.5:1 floor at the 11–13 px sizes these honesty labels use, functionally
/// invisible to a reduced-contrast-sensitivity elderly reader. This dark
/// amber-brown measures ~7.9:1 on #FFF8E1.
const Color kCautionTextOnAmber = Color(0xFF6B4600);

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
/// different meanings, and taught HER to read amber as noise. Blue-grey reads
/// as a standing note rather than an active caution, and is still clearly not
/// the calm grey of a real all-clear.
///
/// #ECEFF1 (`blueGrey.shade50`) under [kNoteTextOnBlueGrey] measures ~13:1,
/// well clear of the OPS-059 4.5:1 floor.
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
    // D4 — these app-owned STATE strings render on HER Japanese surface; route
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
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade50,
            child: Text(
              l.advisoryFetchFailed(errorMessage!),
              style: TextStyle(color: Colors.red.shade900),
            ),
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
      return Row(children: [
        Text(l.advisoryNoFetchYet),
        const Spacer(),
        TextButton(onPressed: onRefresh, child: Text(l.advisoryFetch)),
      ]);
    }
    // WS7 (task 4) — for HER Japanese surface, LEAD with the authoritative
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
            fill: const Color(0x1FFFA000),
            color: const Color(0xFFB26A00),
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
          // N10 — retained (stale) hazard data carries a visible age label;
          // trust the hazard, but never let it masquerade as current.
          if (retainedAgeMinutes != null)
            Container(
              key: const Key('advisory-retained-stale'),
              padding: const EdgeInsets.all(6),
              margin: const EdgeInsets.only(bottom: 4),
              color: Colors.amber.shade50,
              // liveRegion — current→stale is a safety-relevant transition;
              // announce it. Contrast + size: this label's entire job is
              // stopping stale hazard data from masquerading as current, so
              // it must itself be readable (kCautionTextOnAmber ≥4.5:1;
              // 13 px, up from 11).
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l.advisoryRetainedStale(retainedAgeMinutes!),
                  style: const TextStyle(
                    color: kCautionTextOnAmber,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
                l.advisoryPublisherErrored(
                    _sourceLabel(err.source), err.message),
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
  /// the Japanese surface so HER reads the authoritative Japanese source first.
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

  /// When true (HER ja surface, English NWS card), the card is dimmed and
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
              style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Text(
                _sourceLabel(advisory.source),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _severityColor(advisory.severity).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  advisory.severity.name,
                  style: TextStyle(
                    color: _severityColor(advisory.severity),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (advisory.effective != null)
                Text(
                  'eff. ${fmt.format(advisory.effective!.toLocal())}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
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
              'expires ${fmt.format(advisory.expires!.toLocal())}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            advisory.source.attributionString,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
          ),
        ],
      ),
    );
    // De-emphasized (English NWS on HER ja surface): dim but keep present.
    return deEmphasize ? Opacity(opacity: 0.55, child: card) : card;
  }
}

String _sourceLabel(AdvisorySource source) {
  switch (source) {
    case AdvisorySource.nwsUnitedStates:
      return 'NWS';
    case AdvisorySource.jmaJapan:
      return '気象庁';
    case AdvisorySource.metNorway:
      return 'MET Norway';
    case AdvisorySource.other:
      return 'Source';
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
/// merely hold it in the tree (OPS-059 floor). The glyph sits outside the
/// announced text and is marked [ExcludeSemantics] so a screen reader speaks
/// the sentence, not "warning sign".
Widget _honestyBanner({
  required Key key,
  required String glyph,
  required String text,
  required Color fill,
  required Color color,
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
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );

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
