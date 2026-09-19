# ARM-IVI handoff — the phone is a proof-slice, the head unit is the product

**Status (BOD-17, WS9): STATE-only. Nothing embedded is built here.** This document
DECIDES and STATES the trajectory. It does **not** build geolocator_linux, a
CAN/serial GNSS feed, or a Yocto recipe — building any of those trips the BOD-15
embedded tripwire (T2 new recipe / T3 embedded build-out on spec) → reverts the
#188063 bridge to monitor-only, and is the **project owner's to raise**,
owned by the embedded-integration work when raised. Not by this app.

**Mission anchor.** The driver — an older driver in Akita — drives an actual vehicle
with an ARM-class head unit, not a phone taped to the dash. The phone is how we
*prove the reach mechanics* cheaply and honestly; the **head unit is where she is
actually served** in the compound-failure whiteout (Maps + GPS fail, no sight).

---

## The honest claim

**`sngnav-app` on Android = a PROOF-SLICE. The ARM-IVI head unit = the product.**
The phone build is never sold as the driver's deployment. It exists to prove — on cheap,
observable hardware — that the catalog reaches a driver through the modalities she
can use eyes-off-the-road. Whatever the phone proves must then cross to the IVI.

## What the phone proves (and that transfers unchanged)

The reach architecture was built platform-agnostic on purpose:

- **The actuator seam (WS5).** `AlertActuators { speak, haptic, keepAwake }` is an
  injectable interface. Android gets `MobileAlertActuators` (flutter_tts /
  vibration / wakelock_plus, guarded to android/ios). The **app logic never calls a
  plugin directly** — so an IVI impl (`IviAlertActuators`: system/automotive TTS,
  a CAN chime or seat/wheel haptic, an always-lit cluster) slots in **behind the
  same seam** with zero change to the safety logic. The `NoOp` default already
  keeps desktop/test safe; the IVI is just a third impl.
- **The honest position spine (WS6).** `localization_fallback` (trusted →
  dead-reckoning → `lost`, never a confidently-wrong dot) + the finite-position
  guard are pure Dart, no platform dependency — they transfer as-is.
- **The compound-failure caution (WS6)** + **the Japanese consent/disclosure (WS7)**
  + the JMA-first advisory ordering are pure Dart / Flutter widgets — they render
  on the IVI's Flutter embedder unchanged.

## What the IVI needs that the phone does NOT (the handoff to the embedded-integration work)

Each of these is **stated, not built** — a work item for the embedded work if/when
the project owner raises the hardware question:

1. **Positioning.** `geolocator` has no Linux/ARM implementation. The IVI path is
   either `geolocator_linux`-class GNSS **or**, better, the **vehicle's own GNSS
   over CAN/serial** (more accurate, survives when a phone's GPS is cold). The
   finite-position guard + `localization_fallback` sit *downstream* of whatever
   feeds position, so only the *source* changes.
2. **Actuators.** An `IviAlertActuators` behind the WS5 seam (automotive TTS +
   CAN/steering-wheel haptic + always-on cluster instead of wakelock). Design work,
   not app work.
3. **Offline basemap.** MORE critical on the IVI than on a phone — a car in an
   Akita whiteout has no cellular. This is the **same tileset** the offline-tiles
   escalation (2026-07-01, recorded outside this repository)
   must produce (OSM-policy / ODbL clean). **Produce once, serve both.** The
   provenance decision precedes any wiring on either target.
4. **Packaging.** A Yocto recipe (`inherit flutter-app`) for the embedded target —
   **the Yocto recipe work**, not this app's, and only on an owner-raised hardware decision.

## Fences (binding)

- **No embedded build here.** geolocator_linux / CAN-GNSS /
  Yocto recipe are the project owner's to raise, owned by the embedded work. This doc is the honest map, not
  a build order.
- **No over-sell.** The phone build carries the honest bound everywhere
  (`docs/DEVICE_VERIFICATION.md`, the in-app footers): on-device HEAR/FEEL/SEE is
  deferred; the phone is a proof-slice, never the driver's car.
- **The seam is the durable asset.** The value of the phone slice is that it forced
  the reach architecture (injectable actuators, pure-Dart safety spine) that lets
  the IVI reuse everything but the three platform edges above.
