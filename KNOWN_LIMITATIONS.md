# Known limitations

This document lists what `sngnav-app` does NOT do at Slice 0 (this commit), so
that anyone running it can do so with eyes open.

## Alpha state

The whole app is alpha. The `Alert density throttle` panel demonstrates a
real loom from `navigation_safety_core`; everything else (map, routing,
GPS, real alert delivery) is not implemented. The driver remains
responsible for all driving decisions.

## Curated 5-station corridor (Slice 3 boundary)

Slice 3 adds a "Corridor weather" panel showing 5 hardcoded JMA AMeDAS
stations along Akita prefecture's main inhabited spine: 秋田 (Akita-shi)
+ 大曲 (Omagari) + 横手 (Yokote) + 湯沢 (Yuzawa) + 男鹿 (Oga peninsula).

What this slice IS:
- Pure op-(e) geographic aggregation per AAA Article 17 (β): N stations
  presented side-by-side, each verbatim from JMA. No combining, no
  averaging, no fused metric.
- Honest staleness per row: each station's observation timestamp shown.
- Per-station failure isolated: one station's network error does not
  invalidate the others.

What this slice is NOT:
- **Not route-aware.** The 5 stations are hardcoded; they do not
  dynamically filter based on the route HER drew on the map. Route-aware
  corridor selection is a future slice.
- **Not predictive.** WE do not infer "snow is likely on the road" from
  the meteorological observations. JMA measures the air; the road is the
  driver's judgment. Crossing into per-route-segment surface inference
  would cross from op-(e) into op-(c) time-shifted derivation territory
  (forecasting permit required under 気象業務法 第十七条).
- **Not all of Tohoku.** Adjacent prefectures (Iwate, Yamagata, Aomori)
  not yet covered. Multi-prefecture aggregation will pair with the
  `condition_aggregator` data-fusion package when that explore-phase
  substrate matures.
- **Not rate-limit-aware.** 5 parallel JMA fetches per refresh. JMA's
  AMeDAS endpoints have no published rate limit but courteous use is
  expected; if the app gains many concurrent users, request batching /
  caching at a proxy layer becomes necessary.

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

## Dev-only mock GPS (Slice 2d)

A "Use Akita mock (dev)" button next to "Share my location" injects a
fixed `PositionAvailable` at Akita station with ±35m accuracy. This
exists so the position-dot UX can be validated on developer hardware
without a GPS receiver (most laptops, including the HP ZBook this app
was first try-first tested on, have no GNSS chip).

V14 discipline: the mock dot is **amber**, not blue. The accuracy
circle is amber-translucent, not blue-translucent. The status line
prefixes "Mock position · " and ends with " (DEV — not real GPS)" in
amber bold. There is no path by which a viewer can mistake mock for
real position. If you ever see an amber dot in production, the loom
has failed.

The mock button stays in the build for now because it costs ~30 lines
and lets edge developers smoke-test the position UX from any browser.
If/when sngnav-app gains a release configuration, the button should
be compiled out via `kReleaseMode` or `kDebugMode` gating — not yet.

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
