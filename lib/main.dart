/// sngnav-app — alpha-stage navigation companion for snow-zone commuting.
///
/// Slice 0 of #67 from the SPA Actuator unit's HER-pivot 100-insights work.
/// The unit's first edge-developer use of the navigation_safety packages.
///
/// Default profile = ageingRural (per V21 substance — HER's mother in Akita
/// is the named first customer; the most-vulnerable cohort member shapes
/// the default).
///
/// **This is alpha software in active development.** Not for production
/// navigation. The driver remains responsible for all driving decisions.
/// The app surfaces information; it does not control the vehicle.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'package:latlong2/latlong.dart';

import 'akita_map.dart';
import 'jma_fetch.dart';
import 'route_fetch.dart';

void main() {
  runApp(const SngnavApp());
}

class SngnavApp extends StatelessWidget {
  const SngnavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sngnav-app (alpha)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // V21: ageingRural is the default — HER's mother is the named first customer.
  DriverProfile _profile = DriverProfile.ageingRural;

  // Mocked road-surface condition for Slice 0.
  RoadSurfaceCondition _condition = RoadSurfaceCondition.ice;

  // Throttle behavior trace.
  final List<_FireAttempt> _attempts = [];

  // JMA observation state.
  JmaResult? _jmaResult;
  bool _jmaLoading = false;

  // Routing state — Slice 2b. Tap A → tap B → fetch → polyline.
  LatLng? _origin;
  LatLng? _destination;
  RouteResult? _routeResult;
  bool _routeLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshJma();
  }

  Future<void> _refreshJma() async {
    setState(() => _jmaLoading = true);
    final result = await fetchLatestObservation();
    setState(() {
      _jmaResult = result;
      _jmaLoading = false;
    });
  }

  void _handleMapTap(LatLng point) {
    if (_origin == null) {
      setState(() {
        _origin = point;
        _destination = null;
        _routeResult = null;
      });
      return;
    }
    if (_destination == null) {
      setState(() => _destination = point);
      _fetchRoute();
      return;
    }
    // Both set — start over with this tap as new origin.
    setState(() {
      _origin = point;
      _destination = null;
      _routeResult = null;
    });
  }

  void _resetRoute() {
    setState(() {
      _origin = null;
      _destination = null;
      _routeResult = null;
    });
  }

  Future<void> _fetchRoute() async {
    final o = _origin;
    final d = _destination;
    if (o == null || d == null) return;
    setState(() => _routeLoading = true);
    final result = await fetchDrivingRoute(origin: o, destination: d);
    if (!mounted) return;
    setState(() {
      _routeResult = result;
      _routeLoading = false;
    });
  }

  void _fireAlertSequence() {
    final throttle = AlertDensityThrottle.forProfile(_profile);
    final now = DateTime.now();
    setState(() {
      _attempts.clear();
      // Fire 8 attempts in rapid sequence.
      for (var i = 0; i < 8; i++) {
        final t = now.add(Duration(seconds: i * 5));
        final fired = throttle.shouldFire(t, AlertSeverity.warning);
        _attempts.add(_FireAttempt(
          index: i + 1,
          relativeSeconds: i * 5,
          fired: fired,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cap = AlertDensityThrottle.defaultCapFor(_profile);
    final glossary = RoadSurfaceConditionGlossary.forConditionAndProfile(
      _condition,
      _profile,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('sngnav-app (alpha)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Banner(),
            const SizedBox(height: 16),
            _section(
              title: 'Driver profile',
              child: DropdownButton<DriverProfile>(
                value: _profile,
                isExpanded: true,
                onChanged: (v) {
                  if (v != null) setState(() => _profile = v);
                },
                items: DriverProfile.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.name),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Mocked road condition',
              child: DropdownButton<RoadSurfaceCondition>(
                value: _condition,
                isExpanded: true,
                onChanged: (v) {
                  if (v != null) setState(() => _condition = v);
                },
                items: RoadSurfaceCondition.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.name),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Glossary (per profile)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv('JA name', glossary.jaName),
                  _kv('EN name', glossary.enName),
                  _kv('JA speak', glossary.jaSpeakString),
                  _kv('EN speak', glossary.enSpeakString),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Alert density throttle',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv('Per-profile cap', '${cap.toStringAsFixed(1)} alerts/min'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _fireAlertSequence,
                    child: const Text('Fire 8 sequential warning alerts'),
                  ),
                  const SizedBox(height: 8),
                  if (_attempts.isEmpty)
                    const Text('(no attempts yet)')
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _attempts
                          .map((a) => Text(
                                'Attempt ${a.index} '
                                '(t+${a.relativeSeconds}s): '
                                '${a.fired ? "FIRED" : "throttled"}',
                                style: TextStyle(
                                  color: a.fired
                                      ? Colors.green.shade700
                                      : Colors.grey.shade600,
                                ),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Map — Akita-shi (station 32402)',
              child: AkitaMap(
                origin: _origin,
                destination: _destination,
                routePoints: switch (_routeResult) {
                  RouteSuccess(:final points) => points,
                  _ => const [],
                },
                onTap: _handleMapTap,
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Route — tap A then B (driving, no snow-aware yet)',
              child: _routePanel(),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'JMA AMeDAS — Akita-shi (station 32402)',
              child: _jmaPanel(),
            ),
            const SizedBox(height: 16),
            const _Footer(),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child:
                  Text('$k:', style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _jmaPanel() {
    if (_jmaLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final result = _jmaResult;
    if (result == null) {
      return Row(children: [
        const Text('(no fetch yet)'),
        const Spacer(),
        TextButton(onPressed: _refreshJma, child: const Text('Fetch')),
      ]);
    }
    switch (result) {
      case JmaSuccess(:final observation):
        final stale = observation.minutesStale(DateTime.now());
        final temp = observation.temperatureCelsius;
        final hum = observation.humidityPercent;
        final wind = observation.windMetersPerSecond;
        final snow = observation.snowDepthCm;
        final ts = observation.observedAtJstKey;
        // Format observed-at: yyyymmddHHMMSS → yyyy-mm-dd HH:MM JST
        String obsDisplay = ts;
        if (ts.length == 14) {
          obsDisplay =
              '${ts.substring(0, 4)}-${ts.substring(4, 6)}-${ts.substring(6, 8)} '
              '${ts.substring(8, 10)}:${ts.substring(10, 12)} JST';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv('Station', '${observation.stationName} (${observation.stationId})'),
            _kv('Observed at', obsDisplay),
            _kv('Temperature', temp == null ? '—' : '${temp.toStringAsFixed(1)} °C'),
            _kv('Humidity', hum == null ? '—' : '$hum %'),
            _kv('Wind', wind == null ? '—' : '${wind.toStringAsFixed(1)} m/s'),
            _kv('Snow depth', snow == null ? '—' : '${snow.toStringAsFixed(0)} cm'),
            _kv('Fetched', _formatFetched(observation.fetchedAt, stale)),
            const SizedBox(height: 8),
            Text(
              'Source: JMA AMeDAS — verbatim relay only, no derivation.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _refreshJma,
                child: const Text('Re-fetch'),
              ),
            ),
          ],
        );
      case JmaFailure(:final reason):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade50,
              child: Text(
                'JMA fetch failed: $reason',
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Cached data is NOT shown — staleness must be visible. Try again or '
              'check connectivity.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _refreshJma,
                child: const Text('Retry'),
              ),
            ),
          ],
        );
    }
  }

  Widget _routePanel() {
    final hint = switch ((_origin, _destination)) {
      (null, _) => 'Tap the map to set point A (origin).',
      (_, null) => 'Tap again to set point B (destination).',
      _ => 'A and B set. Tap anywhere to start over.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(hint, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        const SizedBox(height: 8),
        if (_routeLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          switch (_routeResult) {
            null => const SizedBox.shrink(),
            RouteSuccess(:final distanceMeters, :final durationSeconds) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _kv('Distance', '${(distanceMeters / 1000).toStringAsFixed(1)} km'),
                  _kv('Duration', _formatDuration(durationSeconds)),
                  const SizedBox(height: 4),
                  Text(
                    'Source: OSRM public demo (router.project-osrm.org). '
                    'NOT snow-aware. NOT for production navigation.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            RouteFailure(:final reason) => Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red.shade50,
                child: Text(
                  'Route fetch failed: $reason',
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
          },
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _origin == null ? null : _resetRoute,
            child: const Text('Reset'),
          ),
        ),
      ],
    );
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }

  String _formatFetched(DateTime fetchedAt, int minutesStale) {
    final fmt = DateFormat('HH:mm');
    return '${fmt.format(fetchedAt)} ($minutesStale min ago)';
  }
}

class _FireAttempt {
  final int index;
  final int relativeSeconds;
  final bool fired;
  const _FireAttempt({
    required this.index,
    required this.relativeSeconds,
    required this.fired,
  });
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.amber.shade100,
      child: const Text(
        'Alpha software. Not for production navigation. The driver remains '
        'responsible for all driving decisions. This app surfaces information; '
        'it does not control the vehicle.',
        style: TextStyle(fontSize: 12),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'sngnav-app 0.0.2 — Slice 2b try-first. '
        'Built on navigation_safety_core 0.4.1 (pub.dev). '
        'Akita station chosen because HER\'s mother lives there (V21). '
        'Routing via OSRM public demo (NOT snow-aware yet).',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }
}
