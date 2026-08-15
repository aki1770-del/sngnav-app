# The Oct 31 route — what only the Chair can do, in order

Measured 2026-08-10 by AAE. Every Play figure below was read live from Google's own pages
on that date, not recalled. **Today is 82 days from Oct 31, and 92 from first ice (Nov 10–25).**

> **Independently re-measured the same day, second AAE pass.** Every Play figure in this
> document was re-read from Google's own pages by a second turn that did not take the first
> turn's word for any of them, and **every one held**: the 12-tester / 14-continuous-day /
> closed-track rule and its "7 days or less" review, targetSdk 36 on 2026-08-31, 16 KB from
> 2027-02-01, "up to 5 days" identity verification, D-U-N-S "up to 30 days", 100 internal
> testers / "within minutes" / "a few hours" for the first link, and Japan's absence from the
> Sept 30 sideload-verification wave. The preflight was re-run rather than trusted — as it
> then stood, four gates, **PASS, exit 0** — and the claim that the *published* privacy policy
> is wrong was confirmed by fetching the public URL itself. **One figure changed, and three
> things were fixed in the repo, including the root cause of that wrong policy page** — see
> "What changed on the second pass" below. The fifth gate is one of those fixes.

---

## The one-paragraph answer

**Oct 31 is reachable, and the engineering is not what stands in the way — the account is.**
Today's tree builds a release-signed App Bundle that passes all five of Play's acceptance
gates (`tool/preflight_play_upload.sh` → PASS: signed `CN=SNGNav Upload` valid to 2053,
targetSdk 36, every 64-bit library 16 KB-aligned, versionCode 2 unspent, and the permissions
we declare identical to the five the app ships), so from an
artifact standpoint we could upload this afternoon. What does not exist is a Google Play
Console account, and nothing but the Chair's own legal identity and payment card can create
one; it was due 2026-07-15 in our own plan and is 26 days late. So, in order:
**(1) register a Play Console account as a PERSONAL account, not an organization** — an
organization account needs a D-U-N-S number, which Google says "can take up to 30 days",
and it buys a beta nothing; **(2) complete identity/contact verification** — one-time
registration fee, email and phone confirmed by one-time password, and Google states
verification "can take up to 5 days"; **(3) push the two documents already written in this
repo** so the privacy-policy URL is live and current (the published copy is the 2026-07-10
version and is missing the VIBRATE permission the app actually ships — corrected in this
change-set but not yet public); **(4) create the app and fill App content** — privacy policy
URL, Data safety (transcribe `docs/store/data_safety_declaration.md`, which is written
answer-by-answer from measured code and flags the one judgement that is yours), content
rating questionnaire, target audience; **(5) upload the `.aab` to the INTERNAL testing
track** — either `bash tool/preflight_play_upload.sh` locally, or simply download the
`sngnav-app-release-aab` artifact from a green CI run, which is gated identically and is
pinned to a commit so there is no question of which tree it came from — then add testers by
email, up to
100, and Google says new builds reach them "within minutes", with a few hours for the very
first test link. **Steps 1–5 are about a week of elapsed time, most of it waiting on
step 2, against 82 days of runway — so the date has roughly ten weeks of slack and is in no
danger from Play's machinery.** The two things that *can* still lose Oct 31 are both human
and both yours: the account not being started, and **no tester having been asked by name**
— our own plan flagged that as its only pull item on 2026-07-14 and it is still open. If you
also want the app on the **public** Play listing before the snow, that is a different and
much tighter clock: production access for a new personal account requires **12 testers
opted-in continuously for 14 days on a CLOSED track** and then a review Google says "usually
takes 7 days or less, but may occasionally take longer" — counting back from first ice on
Nov 10, the 12 testers must be opted in by **Oct 12** and recruited during September, which
is the deadline actually worth putting in the calendar today.

---

## The dates, laid out

| What | Lead time (Google's own words, read 2026-08-10) | Must start by |
|---|---|---|
| Personal account registration | one-time fee; email + phone verified by OTP | — |
| Identity / payment verification | "Verification can take up to 5 days" | ~Oct 20 for Oct 31 |
| *(organization account instead)* | D-U-N-S "can take up to 30 days" | **avoid — do not choose this** |
| App content declarations | Chair-hours, not days | with step 4 |
| *(targetSdk 36 deadline)* | 2026-08-31, **extendable to 2026-11-01** on request | **n/a — we already target 36** |
| First test link visible | "may take a few hours" on first publish | — |
| Later builds to testers | "available to testers within minutes" | — |
| **In-hands via internal testing** | **≈ 1 week total** | **~Oct 20** (82 days of slack today) |
| Production: 12 testers × 14 continuous days, CLOSED track | 14 days, and they must be *consecutive* — "we won't count testers who opted in, tested for less than 14 days, and then opted out" | **Oct 12** |
| Production access review | "usually takes 7 days or less, but may occasionally take longer" | apply by ~Oct 26 |

## What is already done, and verified by running it

- **Release signing.** Upload keystore present, RSA 2048, `CN=SNGNav Upload`, valid
  2026-07-20 → **2053-12-05** (Play requires validity past 2033). Keystore and
  `key.properties` are gitignored — confirmed with `git check-ignore`.
- **targetSdk 36.** Play requires API 36 for new apps and updates **from 2026-08-31** — 21
  days away. We already meet it; no work needed, but the preflight gate now asserts it so a
  toolchain change cannot quietly lose it.
- **16 KB page size.** Every 64-bit library in the bundle is LOAD-aligned ≥ 16 KB
  (`libapp.so`/`libflutter.so` at 64 KB, `libdartjni.so`/`libsqlite3.so` at 16 KB). Required
  for apps targeting API 35+; enforced for updates from **2027-02-01**. Also confirmed
  `zipalign -c -P 16` on the APK: "Verification successful".
- **Permissions.** INTERNET, ACCESS_FINE/COARSE_LOCATION, WAKE_LOCK, VIBRATE — read from the
  built artifact, and now identical to the set we declare (gate 5). **No
  background location**, so the heavy Play background-location review does not apply to us.
  The app's own `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` is a signature-level permission
  AndroidX synthesises; the OS never shows it to a user and it belongs in no declaration.
- **Privacy policy + Data safety.** Both written, code-grounded, ja-primary.

## Three things worth knowing before you start

1. **The published privacy policy is currently wrong, in our favour, which is the worst
   direction.** *Confirmed by fetching the public URL itself on 2026-08-10, not inferred from
   the working tree:* `raw.githubusercontent.com/aki1770-del/sngnav-app/main/docs/store/privacy_policy_ja.md`
   resolves without credentials — so the repo is public and this URL is usable as the privacy
   policy link Play requires — and what it serves is the 2026-07-10 version; it lists four
   permissions
   and then says "no other permissions are requested", while the shipped app also requests
   **VIBRATE** (from the `vibration` plugin — genuinely used, at
   `lib/actuators/mobile_alert_actuators.dart:191-192`, for the haptic cue a driver feels
   without looking). The page had been written from the manifest we hand-author rather than
   the merged manifest that is actually packaged. Corrected here; **it must be pushed before
   that URL is registered with Play**, because a data-safety declaration that contradicts the
   app is a policy violation, and this one would have contradicted it on day one.
2. **There are two divergent working trees of this app**, and only one should ever be built
   for a tester. `/home/komada/tmp/sngnav-app` is on `main`; the copy under the masterplan
   directory sits on `feat/measured-hazard-rung-fusion` at 2026-07-27. Building from the
   wrong one hands a tester an older app while everyone believes otherwise. The preflight
   prints the commit and warns when the tree is dirty, but it cannot know which tree you
   meant.

   *Re-measured 2026-08-15 (AAE), and the ahead-count that used to sit in this sentence is
   removed rather than updated. It read "dated 2026-08-09, and is **8 commits ahead of the
   pushed remote**"; `git rev-list --left-right --count origin/main...HEAD` now returns
   `0 0`, because those commits were pushed on 2026-08-15. A hard-coded divergence count in
   a document is false the moment anyone pushes, and this one would have been published
   already false. The durable fact is WHICH TREE, not how far ahead it was on one afternoon
   — so only the durable half is kept, and the count is something you run the command for.*
3. **If Play slips for any reason, Oct 31 still holds — by sideloading.** A release-signed
   installable APK exists today (85 MB). Google's developer-verification requirement for
   sideloaded apps begins **2026-09-30 in Brazil, Indonesia, Singapore and Thailand only**,
   expanding globally in 2027 — **Japan is not in the first wave**, so a Japanese tester can
   install our APK directly this autumn with no Play involvement at all. Two honest costs:
   it does **not** satisfy our own criterion C3 ("release-signed build on Play internal
   testing; ≥1 tester installed via the track"), and it gives no update channel — every
   mid-season fix would be hand-delivered to every tester. Play is the better road. Sideload
   is the road that cannot be closed by a verification queue.

## What changed on the second pass (2026-08-10, AAE)

**One figure moved, and it moves in our favour without helping us.** Play's target-API page
also offers an **extension to 2026-11-01** for developers who need more time past Aug 31.
It costs us nothing either way — we already target 36 — but the first version of this
document presented Aug 31 as a hard wall, and it is not one.

**Two things were fixed in the repo, both of them the root of the privacy-policy error
rather than the error itself.** The correction that had been made was to the *policy text*;
the reason the text was wrong was still fully in place.

1. **`VIBRATE` is now declared in the manifest we author** (`android/app/src/main/AndroidManifest.xml`).
   It was already shipping — the `vibration` plugin injects it at merge time — but it was
   invisible in the file a human reads, which is precisely why a declaration written from
   that file listed four permissions for an app that requests five. **A fifth preflight gate
   now compares the two mechanically** and fails in both directions, so the next plugin that
   quietly adds a permission cannot make our store declarations false again. It was proven
   against the real bundle, not just in theory: with `VIBRATE` deleted from the manifest the
   gate **FAILED and named it**, then the manifest was restored byte-identical.
2. **The permission guard now covers the channels she feels rather than only the ones that
   carry data.** `tool/assert_manifest_perms.sh` guarded INTERNET and the two location
   permissions; `WAKE_LOCK` and `VIBRATE` — the lit screen and the haptic cue, the two things
   that reach a driver who cannot look — were unguarded, so an edit dropping either would
   have shipped a silent app while the guard printed PASS. Both are now required, with new
   cases proving the guard rejects their absence (self-test **31/31**).

**And the CI release job was building the wrong artifact.** It produced only an `.apk`;
**Play will not accept an APK for a new app.** It now also builds the `.aab` and runs all
five gates against it, publishing the bundle as a downloadable CI artifact — which means
**you can take an upload-ready bundle straight from a green CI run without building locally,
and without anyone having to choose between the two divergent working copies on the build
machine.** Honest bound: that CI change is **UNVERIFIED** — verifying it requires pushing,
and pushing is yours, not ours. The YAML was checked to parse and the step order confirmed;
that is all that can be claimed until a run happens.

## What this document does not claim

Whether a Play Console account already exists is **UNVERIFIED** — that requires a credential
no skill here holds, and the finding above rests on this repo's own unticked checklist rather
than on the Console. And nothing here says the app *works*: the bundle is proven
upload-acceptable, not proven to help anyone. Nobody has yet heard this app speak on a real
phone (BETA_PLAN C1), and that is a separate and larger debt than any of the above.
