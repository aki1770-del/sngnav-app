# sngnav-app

Alpha-stage navigation companion for snow-zone commuting in Hokkaido / Tohoku, Japan.

## What this is

The first edge-developer use of the [navigation_safety_core](https://pub.dev/packages/navigation_safety_core) package family from pub.dev. Built by the same team that ships those packages — eating our own dog food while learning what fails.

Slice 0 (this commit) demonstrates:

- A `DriverProfile` selector wired to `AlertDensityThrottle` from `navigation_safety_core 0.4.1`
- The throttle's per-profile cap visualized — fire 8 sequential alerts, see which fire and which throttle for the selected profile
- A `RoadSurfaceConditionGlossary` panel showing per-profile vocabulary (kanji-native for ageing-rural, simplified for foreign-tourist, etc.)
- One real-data fetch from JMA AMeDAS — current observation at the Akita-shi station (32402): temperature, humidity, wind, snow depth, observation time

The default profile is `ageingRural`. The default station is Akita. Both choices are deliberate — the first customer we serve is the most-vulnerable cohort member.

## What this is NOT

**This is alpha software in active development.** It is not for production navigation. The driver remains responsible for all driving decisions. The app surfaces information; it does not control the vehicle.

There is no map. No routing. No navigation in the GPS sense. No alerts on a real device. No telemetry. No consent flow. No real-user beta. Slice 0 is foundation — these arrive in subsequent slices.

The aspirational target is the November 2026 winter driving season, when real beta-testers in HER's cohort might use a working version on real snow roads. Whether that target is met depends on what fails between now and then.

## How to run

```sh
git clone https://github.com/aki1770-del/sngnav-app
cd sngnav-app
flutter pub get
flutter run
```

The JMA fetch happens on app start; the first observation appears within a few seconds. Tap "Fire 8 sequential warning alerts" to watch the throttle behavior for the selected profile.

If JMA fetch fails (network, endpoint changes, etc.) you'll see an explicit error — never silent fallback to displayed-as-fresh stale data.

## Provenance

This repository is part of the SPA Actuator unit's work — a governance-disciplined human + AI collaboration shipping the SNGNav package family. The `navigation_safety_core` package is on pub.dev; the [spa-ai](https://github.com/aki1770-del/spa-ai) tool ships build-time looms with the same vocabulary used here.

Per the tradition Sakichi Toyoda set: the first customer for invention is a named person in your own household. We started with HER's mother at her Akita weather station.

## License

BSD 3-Clause (matches the navigation_safety_core package).

## Honest disclosure

If you spot something wrong — a calculation that seems off, a JMA reading that doesn't match what you see out your window, an alert that fired when it shouldn't have — please open an issue. Silent gaps are a worse failure than acknowledged ones.
