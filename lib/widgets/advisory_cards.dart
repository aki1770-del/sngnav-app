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

class AdvisoryCards extends StatelessWidget {
  const AdvisoryCards({
    super.key,
    required this.loading,
    required this.result,
    required this.errorMessage,
    required this.onRefresh,
    this.retainedAgeMinutes,
  });

  final bool loading;
  final AdvisoryAggregateResult? result;
  final String? errorMessage;
  final VoidCallback onRefresh;

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
        // B04 — the all-clear line is a POSITIVE claim ("no advisories are in
        // force"). When every advisory is absent AND a covering publisher
        // errored, that claim is unverified: the absence is a fetch failure,
        // not a publisher statement. Render honest-unknown instead — absence
        // must never render as calm. All-clear renders only when no covering
        // publisher errored (with region-gating, that means the regional
        // publisher answered).
        if (r.advisories.isEmpty && r.providerErrors.isNotEmpty)
          Container(
            key: const Key('advisory-unknown-degraded'),
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade50,
            child: Text(
              l.advisoryFetchUnknown,
              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
            ),
          )
        else if (r.advisories.isEmpty)
          Text(
            l.advisoryNoneActive,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
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
              child: Text(
                l.advisoryRetainedStale(retainedAgeMinutes!),
                style: TextStyle(color: Colors.amber.shade900, fontSize: 11),
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
                style: TextStyle(color: Colors.amber.shade900, fontSize: 11),
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
