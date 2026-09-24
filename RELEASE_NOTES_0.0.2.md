# SNGNav 0.0.2 — honest bounds

**Read this before you install it.** Everything here was measured on 2026-09-18 unless a
passage carries a later date, and the things this build has NOT been shown to do are listed as
plainly as the things it has. **Two passages carry corrections dated 2026-09-24; each says what
it corrects rather than replacing it silently.**

`0.0.2+3` · package `dev.aki1770del.sngnav_app` · versionName `0.0.2`, versionCode `3`
(read from the built artifact with `aapt2 dump badging`, not from the source tree).

---

## Why the version number went DOWN

The previous number in this repo was `0.0.5`. Nothing was ever released under it — this
repo has **one tag in its life** and `tool/play_uploaded_version_codes.txt` holds **zero**
consumed versionCodes. `0.0.5` was a build counter, not a release sequence.

**0.0.2 is the second build ever to reach a real person's phone.** The first was `0.0.5+2`,
hand-installed on 2026-09-17; `0.0.2+6` and then `0.0.2+7` followed on 2026-09-19. The sequence
starts where reach starts.

⚑ **Corrected 2026-09-24.** This paragraph previously ended *"and the first to reach the
driver this app is for."* That was not true when it was written and it is not true now. Every
install of every build of this app has landed on **one phone — the maintainer's own, by his own
hand.** **No build has yet reached the driver this app is built for, or any second person.**

**versionCode went 2 → 3, and that direction is not optional.** Android enforces
monotonicity on versionCode, never on the displayed name. A phone already holding an
install at 2 will refuse a lower one.

---

## There is no store. This is a sideload.

There is **no Google Play track, no internal track, no listing, and no account**. The only
way this build reaches a phone is by hand: `adb install`, or tapping the `.apk` in a file
manager with "install unknown apps" allowed for that file manager.

Two consequences, stated because they are yours to carry, not ours:

- **No automatic updates.** Nothing will tell you a newer build exists, and nothing will
  replace this one. If a defect is found after you install, the fix reaches you only when
  someone hands you another file.
- **No store review stood between this build and you.** The `.aab` in this release is
  upload-*acceptable* — signed with the SNGNav upload key, targetSdk 36, 16 KB-aligned,
  permissions matching what is declared. That is a statement about the file's paperwork.
  It is not a statement about the app.

## What was seen on a real phone, and what was not

| | |
|---|---|
| **Her position dot, from a real Android GPS fix** | **SEEN on a physical phone** — a Mi Note 10 Pro, 2026-09-17. The map had said 「現在地 不明 · 最後の位置 なし」 while the phone held a valid fix; after the fix it showed the position. ⚑ **The build that was installed was not this one.** It carried byte-identical position code (`lib/her_position.dart`, blob `d20c9279`, unchanged from that build through to this release), but it was a different artifact. |
| **The offline voice actually being HEARD** | **NOT VERIFIED.** What is verified is narrower and mechanical: every one of the 40 clips the voice asks Android to open is present, uncompressed and openable **inside this APK** — checked by reading the built artifact, not the source. Whether a person hears it come out of a speaker has not been observed. |
| **The haptic actually being FELT** | **NOT VERIFIED, and cannot be from here.** The available emulator (`sngnav_api30`) reports `hasVibrator()` false and runs with `-no-audio`. A pass on that emulator would mean nothing, so none was taken. |
| **This exact artifact (`0.0.2+3`) on any phone** | **NO — and that part stands.** `0.0.2+3` has never been installed on any device. ⚑ **Corrected 2026-09-24:** this cell previously read *"No build of 0.0.2 has been installed on any device by anyone."* That stopped being true on 2026-09-19 — the day after this file was written — and stood here uncorrected for nearly five days. **Later builds of 0.0.2 did reach a phone:** `0.0.2+6`, and then `0.0.2+7` (`lastUpdateTime` 2026-09-19 22:07:01 JST), installed by the maintainer's own hand on his Mi Note 10 Pro and read back from the phone afterwards. **Every measurement in this file was taken on `+3`, and none of them has been re-measured on either of those builds.** |

**An unverified line above is not a line that failed. It is a line nobody has stood in front
of.** They are written separately on purpose, because an absent verdict reads exactly like a
pass if you let it.

## What the app cannot do in the worst case it is built for

The case this app exists for is the one where Google Maps has failed **and** GPS has failed
**and** the driver cannot see where she is. Against that case:

- **If the phone has no position, this app has no position.** It does not have a second
  source. It will say 「現在地不明」 rather than draw a dot it cannot justify — that is the
  correct behaviour and it is also the limit of it.
- **The JMA warning path is live but it is not instant.** Measured live 2026-09-18 for
  Akita: the path this build reads answered with its newest bulletin **31.7 hours old**.
  That is normal and healthy for this feed, and it is still a day-scale signal, not a
  now-cast. A road can freeze between bulletins.
- **When the feed goes quiet, you are told.** A warning older than 7 days never reaches the
  screen alone — a feed-health notice travels with it. This exists because the retired JMA
  path froze on 2026-05-28 and nothing noticed for months; measured again today, that
  retired path is **113.5 days stale and still returns HTTP 200**. A dead feed and a quiet
  one look identical from the outside.
- **It advises; it does not drive.** The strongest thing it will ever say is
  「停車の検討」 — *consider stopping*. It never instructs a turn-back, and it never touches
  the vehicle.
- **The app is alpha.** The standing list of what it does not do is `KNOWN_LIMITATIONS.md`,
  and it is longer than this section.

## Toolchain and test bounds you should know about

- **43 golden-image comparisons do not compare anything on CI.** They render the screen and
  then skip the pixel check, because CI pins Flutter 3.41.4 while the goldens were cut on a
  dev host running 3.45.0-1.0.pre-48 — shaping and anti-aliasing differ, so a comparison
  would be noise. The render pipeline is still exercised; the **pixel claim is withdrawn**.
  *Until today the skip note gave the wrong reason ("no CJK fonts on this host"), which had
  stopped being true when CI began installing Japanese fonts. That note is corrected in this
  release.* **A skip is not a pass, and this is the largest block of un-compared evidence in
  the suite.**
- **1250 tests pass with 0 skipped** at dart level on the release commit's CI run.
- **The release artifact in CI is built only on an explicit `workflow_dispatch`**, never as a
  side effect of a commit. Producing a signed artifact someone can install on a phone is an
  act, not a build step.

## What this release does NOT include

- Any upload, anywhere. No Play Console account exists and none was created.
- The upstream `geolocator_android` fix. It is owed to that project and runs on a different
  clock; this app carries its own workaround for it.

---

*Written against the 0.0.2 release criteria (2026-09-18; kept outside this repository).
Anything above that is a measurement carries the date it was measured. Where a thing was not
observed, this file says so rather than leaving the space blank.*
