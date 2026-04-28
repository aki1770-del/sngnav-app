# Known limitations

This document lists what `sngnav-app` does NOT do at Slice 0 (this commit), so
that anyone running it can do so with eyes open.

## Alpha state

The whole app is alpha. The `Alert density throttle` panel demonstrates a
real loom from `navigation_safety_core`; everything else (map, routing,
GPS, real alert delivery) is not implemented. The driver remains
responsible for all driving decisions.

## Single station

Only Akita-shi (JMA AMeDAS station 32402) is fetched. That choice is
deliberate — HER's mother lives there, and the first customer for invention
is the named person in the household. Multi-station aggregation is a
future-slice scope after legal + safety review (see the `condition_aggregator`
research substrate in the parent unit's `outputs/research/`).

## Verbatim relay only

The JMA panel surfaces only what JMA has published. No derivation. No
"may freeze in 2 hours." No fused predictions. This is operation-class (a)
of the AAA Article 17 boundary check; (c) time-shifted derivation and (d)
cross-source-fused prediction would require a forecasting permit (予報業務
許可) under 気象業務法 第十七条 and are not in scope until that path is
opened.

## JMA fetch failure surfaces explicitly

If the JMA endpoint is unreachable, the app shows the explicit failure
reason. It does NOT silently fall back to cached or stale data displayed
as fresh. Staleness must be visible to the driver — silent stale data is
the V14 anti-Jidoka failure mode.

## Routing is NOT snow-aware (Slice 2b boundary)

The route panel calls the OSRM public demo server
(`router.project-osrm.org`) and draws the polyline OSRM returns. That
polyline reflects **road network connectivity only** — it does NOT know:

- whether a pass is closed for the season
- whether plows have run today
- whether snow depth exceeds the vehicle's clearance
- whether the route crosses a chain-required zone

The driver remains responsible for assessing all of the above before
following any drawn route. Snow-aware routing — the eventual reason
this app exists — depends on the `condition_aggregator` data-fusion
component class within Direction B (currently in Aspiration-Gate
explore-phase under Loom L12); it is not implemented at Slice 2b.

The OSRM demo server is rate-limited and has no SLA. It is suitable
for personal demos, NOT for production navigation.

## GPS is wired, but minimum (Slice 2c boundary)

Slice 2c shows HER's position as a blue dot with a translucent accuracy
circle. The circle is rendered at the radius the platform reports — small
circle = sure, large circle = unsure. When the platform reports no fix
(permission denied, services off, stream error), the dot disappears and
a one-line status surfaces under the map ("GPS unavailable — <reason>").
No popups. No banners. No voice. The passenger sits down quietly.

What is NOT yet wired:

- **Cohort-respectful permission rationale.** The first GPS request uses
  the platform's default permission dialog. For the `ageingRural` cohort
  the default dialog is a V96 dignity gap — "Allow location?" without
  context will be confusing. A pre-permission rationale screen tailored
  per `DriverProfile` is a future slice.
- **Dead-reckoning fallback.** When GPS drops mid-trip (tunnel, cedar
  canopy, snow on antenna), the dot disappears. There is no fallback to
  IMU + odometer integration yet. The `kalman_dr` package in the SNGNav
  family (`packages/kalman_dr/`) is the substrate; wiring it requires
  vehicle-bus access (CAN/OBD) which sngnav-app does not yet have.
- **Cross-trip memory of GPS-weak zones.** No carry-forward yet of "this
  tunnel costs you 90s of fade." Anti-cortisol is a future slice.
- **Recovery confirmation.** When GPS comes back, the dot just reappears.
  No "GPS restored — last 1.4km dead reckoning ±38m, route consistent"
  message yet (because there is no dead reckoning yet to summarize).

The honesty discipline (V14): the dot reflects what the platform reports.
WE do not invent confidence. WE do not freeze the dot on its last fix
and pretend it is current. When WE do not know, the dot is gone.

## No turn-by-turn

The route is drawn as a single polyline with distance + duration. There
is no step-by-step instruction list, no voice guidance, no rerouting on
deviation. The `AlertDensityThrottle` demo fires alerts on a synthetic
time sequence — it is not yet connected to real driving conditions.

## No telemetry, no consent flow, no beta protocol

The app does not collect telemetry. There is no consent flow because
there is nothing to consent to yet. When a future slice begins
real-user beta testing, a consent + privacy + opt-out protocol
must ship first — that loom does not exist yet, and shipping
real-user beta without it would violate V96 (maintainers-as-edge-developers)
applied to the cohort beta-tester class.

## No accessibility audit

Screen reader compatibility, color contrast, font scaling — all
unaudited at Slice 0. To be addressed before any beta-tester touches
the app.

## What this means for someone running it

You can run it, click around, watch the throttle behavior, and see a
real Akita weather observation. You cannot use it to navigate. If the
JMA fetch fails on your network, you'll see the failure honestly. If
you spot something that seems wrong, please open an issue.
