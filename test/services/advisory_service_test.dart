import 'package:condition_aggregator/condition_aggregator.dart'
    show
        Advisory,
        AdvisoryCertainty,
        AdvisoryProvider,
        AdvisorySeverity,
        AdvisorySource,
        AdvisoryUrgency;
import 'package:flutter_test/flutter_test.dart';
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart'
    show
        AlertCertainty,
        AlertMessageType,
        AlertSeverity,
        AlertStatus,
        AlertUrgency,
        WinterAlert;
import 'package:sngnav_app/services/advisory_service.dart';
import 'package:sngnav_app/services/noaa_advisory_provider.dart';

class _FakeProvider implements AdvisoryProvider {
  _FakeProvider({required this.advisories, required this.src});

  final List<Advisory> advisories;
  final AdvisorySource src;
  bool initCalled = false;
  bool initShouldFail = false;
  bool fetchShouldThrow = false;

  @override
  AdvisorySource get source => src;

  @override
  Future<void> init() async {
    if (initShouldFail) {
      throw Exception('init failed');
    }
    initCalled = true;
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (fetchShouldThrow) {
      throw Exception('transport failed');
    }
    return advisories;
  }
}

void main() {
  final ts = DateTime.utc(2026, 1, 1, 6, 0, 0);

  Advisory adv(String evt, AdvisorySeverity sev) => Advisory(
        source: AdvisorySource.nwsUnitedStates,
        eventClass: evt,
        severity: sev,
        certainty: AdvisoryCertainty.likely,
        urgency: AdvisoryUrgency.expected,
        areaDescription: 'Grand Forks ND',
        effective: ts,
        expires: ts.add(const Duration(hours: 12)),
        headline: '$evt issued by NWS Grand Forks ND',
        description: 'Multi-paragraph description',
      );

  group('AdvisoryService', () {
    test('fan-out merges advisories from multiple providers', () async {
      final fake1 = _FakeProvider(
        src: AdvisorySource.nwsUnitedStates,
        advisories: [adv('Winter Storm Warning', AdvisorySeverity.severe)],
      );
      final fake2 = _FakeProvider(
        src: AdvisorySource.metNorway,
        advisories: [adv('Blizzard Warning', AdvisorySeverity.extreme)],
      );
      final svc = AdvisoryService(providers: [fake1, fake2]);
      await svc.init();
      final result = await svc.fetchAtPoint(latitude: 47.9, longitude: -97.0);
      expect(result.advisories, hasLength(2));
      expect(result.providerErrors, isEmpty);
      expect(fake1.initCalled, isTrue);
      expect(fake2.initCalled, isTrue);
    });

    test('per-provider transport failure is surfaced via providerErrors',
        () async {
      final ok = _FakeProvider(
        src: AdvisorySource.nwsUnitedStates,
        advisories: [adv('Winter Storm Warning', AdvisorySeverity.severe)],
      );
      final bad = _FakeProvider(
        src: AdvisorySource.metNorway,
        advisories: const [],
      )..fetchShouldThrow = true;
      final svc = AdvisoryService(providers: [ok, bad]);
      await svc.init();
      final result = await svc.fetchAtPoint(latitude: 47.9, longitude: -97.0);
      expect(result.advisories, hasLength(1));
      expect(result.providerErrors, hasLength(1));
      expect(
        result.providerErrors.single.source,
        AdvisorySource.metNorway,
      );
    });

    test('fetchAtPoint before init throws StateError', () async {
      final svc = AdvisoryService(providers: [
        _FakeProvider(
          src: AdvisorySource.nwsUnitedStates,
          advisories: const [],
        ),
      ]);
      expect(
        () => svc.fetchAtPoint(latitude: 0.0, longitude: 0.0),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('NoaaAdvisoryProvider.toAdvisory', () {
    test('maps WinterAlert fields into Advisory verbatim', () {
      final alert = WinterAlert(
        event: 'Winter Storm Warning',
        severity: AlertSeverity.severe,
        certainty: AlertCertainty.likely,
        urgency: AlertUrgency.expected,
        areaDesc: 'Towner; Cavalier; Benson; Ramsey',
        effective: ts,
        expires: ts.add(const Duration(hours: 12)),
        headline: 'Winter Storm Warning issued by NWS Grand Forks ND',
        description: 'Heavy snow expected.',
        instruction: 'Avoid travel.',
        status: AlertStatus.actual,
        messageType: AlertMessageType.alert,
        senderName: 'NWS Grand Forks ND',
      );
      final advisory = NoaaAdvisoryProvider.toAdvisory(alert);
      expect(advisory.source, AdvisorySource.nwsUnitedStates);
      expect(advisory.eventClass, 'Winter Storm Warning');
      expect(advisory.severity, AdvisorySeverity.severe);
      expect(advisory.certainty, AdvisoryCertainty.likely);
      expect(advisory.urgency, AdvisoryUrgency.expected);
      expect(advisory.areaDescription, 'Towner; Cavalier; Benson; Ramsey');
      expect(advisory.headline, contains('NWS Grand Forks ND'));
      expect(advisory.description, 'Heavy snow expected.');
      expect(advisory.isHighImpact, isTrue);
    });
  });
}
