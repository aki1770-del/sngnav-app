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
/// Empty state: "No active advisories at this location." Honest
/// no-data render — does NOT fall back to a stale snapshot.
///
/// Loading state: spinner. Error state: Exception class + message
/// surfaced through the per-publisher `providerErrors` channel.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdvisoryCards extends StatelessWidget {
  const AdvisoryCards({
    super.key,
    required this.loading,
    required this.result,
    required this.errorMessage,
    required this.onRefresh,
  });

  final bool loading;
  final AdvisoryAggregateResult? result;
  final String? errorMessage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
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
              'Advisory fetch failed: $errorMessage',
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRefresh,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    final r = result;
    if (r == null) {
      return Row(children: [
        const Text('(no fetch yet)'),
        const Spacer(),
        TextButton(onPressed: onRefresh, child: const Text('Fetch')),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.advisories.isEmpty)
          Text(
            'No active advisories at this location.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          )
        else
          ...r.advisories.map((a) => _AdvisoryCard(advisory: a)),
        if (r.providerErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final err in r.providerErrors)
            Container(
              padding: const EdgeInsets.all(6),
              margin: const EdgeInsets.only(bottom: 4),
              color: Colors.amber.shade50,
              child: Text(
                'Publisher ${_sourceLabel(err.source)} errored: ${err.message}',
                style: TextStyle(color: Colors.amber.shade900, fontSize: 11),
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onRefresh,
            child: const Text('Re-fetch'),
          ),
        ),
      ],
    );
  }
}

class _AdvisoryCard extends StatelessWidget {
  const _AdvisoryCard({required this.advisory});

  final Advisory advisory;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: _severityColor(advisory.severity)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
