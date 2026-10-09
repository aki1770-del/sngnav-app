# sngnav-app developer playbook

For anyone who builds, changes, tests, versions, releases or verifies this app:
an outside contributor, a developer using it as a reference integrator for the
`navigation_safety_core` package family, or a maintainer.

**How to read this file.**

- It is cited against commit `0149fa6f` of `main` (2026-10-09). Every rule,
  path and version is cited as `file:line` at that commit. Line numbers move
  when files change, so if a cited line no longer says what this page says,
  the file is right and this page is stale.
- Where this page says **Measured 2026-10-09**, the command was run on a fresh
  clone of `0149fa6f` on an Ubuntu 24.04 host, and the output shown is what it
  printed. Where it says **Cited**, the command comes from the repository or
  from the tool's own documentation and was not run for this page.
- The first version of this page was followed step by step, by someone who
  did not write it, on a clean clone and an emulator. The steps that were
  wrong or unclear for them are rewritten here: the tile archive loop in 3.1,
  installing the toolchain (2.5), and several commands in chapter 6. Running
  2.5 on a bare machine then found one more: the render tests need the time
  zone UTC+9 (3.3).
- The repository already has docs. This page puts them in order and points to
  them; it does not repeat what they already say correctly. Where a doc
  disagrees with the code, Appendix A lists the difference. The code wins.
- The app is safety-adjacent: it warns a driver about winter road conditions.
  The person who pays for a mistake in a build is the driver holding the
  phone, so several steps below exist only to stop a wrong build from reaching
  a phone. Do not skip them because they are slow.

---

## 1. What the app is, and what it is not

| | |
|---|---|
| **What** | An alpha-stage navigation companion for snow-zone driving in Hokkaido and Tohoku, and the first app built on the `navigation_safety_core` package family from pub.dev (`README.md:3-7`). |
| **Package** | `dev.aki1770del.sngnav_app` (`android/app/build.gradle.kts:140,151`). A development build is another app, `dev.aki1770del.sngnav_app.dev` (`build.gradle.kts:133`, chapter 5). |
| **Advisory only** | It shows information and never controls the vehicle. The highest caution it gives is 停車の検討 ("consider stopping"); it never says "turn back" (`KNOWN_LIMITATIONS.md:19-24`). |
| **Routing** | Road connectivity only, from the public OSRM demo server. It does not know about closed passes, plowing or chain zones (`KNOWN_LIMITATIONS.md:155-164`). |
| **Location** | Opt-in, deny by default. No `ACCESS_BACKGROUND_LOCATION`. During a drive a foreground location service keeps running with the screen off, behind a notification (`KNOWN_LIMITATIONS.md:189-240`; `android/app/src/main/AndroidManifest.xml:5-110` for the eight permissions). |
| **Distribution** | No store. Builds reach phones by sideload only (`RELEASE_NOTES_0.0.2.md:34-38`). Nothing has been uploaded to Google Play (`tool/play_uploaded_version_codes.txt:28-42`). |
| **Phone vs head unit** | The Android app is a proof slice. The intended product is an in-vehicle head unit; nothing embedded is built in this repository (`docs/ARM_IVI_HANDOFF.md:3-8,19-22`). |
| **Verification state** | Hearing the voice and feeling the vibration on a physical phone are still unverified (`KNOWN_LIMITATIONS.md:30-39`). The beta gate of 2026-08-05 was missed at 0 of 6 criteria (`README.md:29`; `BETA_PLAN.md:315-346`). |

Read `README.md` and `KNOWN_LIMITATIONS.md` before you change anything that
the driver sees.

---

## 2. Toolchain

If your machine has none of this yet, start with 2.5, which installs all of
it on a bare Ubuntu 24.04 machine, then check yourself against 2.1 to 2.4.

### 2.1 What CI uses

| Tool | Version CI pins | Source |
|---|---|---|
| Flutter | stable **3.47.5**, in all three jobs | `.github/workflows/ci.yml:182-185, 558-561, 668-671` |
| Java | Temurin **17** | `ci.yml:509-512, 614-617` |
| Python | **3.12** | `ci.yml:94-96, 524-526, 631-633` |
| Runner | `ubuntu-24.04` | `ci.yml:71, 497, 608` |
| Android Gradle Plugin | 9.1.0; Kotlin 2.4.0 | `android/settings.gradle.kts:22-23` |
| Gradle | 9.3.1 (wrapper) | `android/gradle/wrapper/gradle-wrapper.properties:5` |
| compile/target/min SDK, NDK | from the Flutter Gradle plugin; in a built APK: compileSdk 36, targetSdk 36, minSdk 24, native code `arm64-v8a armeabi-v7a x86_64` | `android/app/build.gradle.kts:141-142, 154-155`; Measured with `aapt2 dump badging` |

**Why the Flutter version is exact.** The committed `pubspec.lock` and the
golden images were made with stock Flutter 3.47.5. Another Flutter version
resolves a different lock and renders some goldens differently, so a build or
test run there is not CI's result (`ci.yml:492-495`;
`test/render_see/render_see_env.dart:10-16`). `pubspec.yaml:60-62` accepts
Dart `^3.11.1` and Flutter `>=3.41.0`; that range is wider than what is
tested. Use 3.47.5.

**How to tell you have it.** Measured 2026-10-09:

```console
$ flutter --version
Flutter 3.47.5 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 6a19cca564 (3 weeks ago) • 2026-09-17 14:13:22 -0400
...
Tools • Dart 3.13.4 • DevTools 2.60.0
```

`scripts/build-verify.sh` pins the same revision and Dart
(`scripts/build-verify.sh:30-35`), and prints `TOOLCHAIN DRIFT` only on
another toolchain (`scripts/build-verify.sh:51-57`). Measured: both of its
checks match the output above.

**Java.** CI builds with JDK 17. The app compiles to Java 17
(`build.gradle.kts:144-147, 1209-1213`). To choose the JDK Flutter builds
with, set it: `flutter config --jdk-dir <path>` (2.5 does this). The
maintainer's host builds with JDK 21 (Measured:
`flutter config --list` reports `jdk-dir: .../jdk-21.0.11+10`). Both build
this commit: CI's `android-build` job and the bare-machine run in 2.5 with
17, and this page's host builds with 21. Gradle is given an 8 GB heap
(`android/gradle.properties:1`); a machine with less memory may fail in the
Gradle step.

### 2.2 Host packages the guards need

The repository's own checks under `tool/` need more than Flutter. On Ubuntu
24.04 these are the packages CI installs:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  open-jtalk open-jtalk-mecab-naist-jdic hts-voice-nitech-jp-atr503-m001 \
  fonts-ipafont-gothic fonts-droid-fallback strace
```

(`ci.yml:262, 306, 431`). What each is for:

- **open-jtalk and its voice and dictionary.** The offline voice guard
  re-renders every bundled Japanese voice clip and compares the bytes
  (`tool/offline_voice_render_guard.sh:25-37`). The committed clips were
  rendered with open-jtalk 1.11-5, the dictionary 1.11-5 and the voice
  1.05-8; a different engine build makes every clip differ
  (`offline_voice_render_guard.sh:34-37`; `ci.yml:257-258`).
- **fonts-ipafont-gothic, fonts-droid-fallback.** Seven legibility tests read
  the Japanese screen with real glyph metrics and fail closed without these
  two faces (`ci.yml:270-302`). Do not substitute Noto CJK: it has different
  metrics (`ci.yml:298-302`).
- **strace.** The self-test hermeticity guard traces what each guard reads
  (`ci.yml:423-434`).

Measured 2026-10-09 on the host used for this page:
`open-jtalk 1.11-5`, `open-jtalk-mecab-naist-jdic 1.11-5`,
`hts-voice-nitech-jp-atr503-m001 1.05-8`, `fonts-ipafont-gothic 00303-21ubuntu1`,
`fonts-droid-fallback 1:6.0.1r16-1.1build1`, `strace 6.8-0ubuntu2`.

Two more that a CI runner already has and a fresh Ubuntu does not:
`sqlite3`, which the tile archive identity guard calls
(`tool/tile-archive-identity-guard.sh:98`), and `python3-venv`, without
which the `python3 -m venv` line below fails. 2.5 installs both.

**Python 3.12, not 3.13.** The voice renderer imports `audioop`, which
Python 3.13 removed; on 3.13 the voice guard reports `UNDETERMINED` and exits
3 (`tool/offline_voice_render_guard.sh:171-172`; `tool/render_offline_voice.sh:76`).
The guards call `python3`, never `python` (`ci.yml:370-375`).

**Python packages for the tile guards.** `tool/requirements.txt` is the
declared list (`osmium==4.3.1`, `pillow==12.3.0`, `shapely==2.1.2`,
`tool/requirements.txt:48-50`). Ubuntu 24.04's system Python refuses a global
`pip install`, so use a virtual environment, and **put it in a dot-directory
under your home directory**:

```sh
# from the repository root
python3 -m venv ~/.cache/sngnav-app-tool-venv
~/.cache/sngnav-app-tool-venv/bin/python3 -m pip install -r tool/requirements.txt
export PATH="$HOME/.cache/sngnav-app-tool-venv/bin:$PATH"
```

Why the location matters: the self-test hermeticity guard reports any file a
self-test reads outside the checkout as `OUTSIDE-REPO`; among the paths it
excludes are system paths, dot-paths under `$HOME`, and paths under a
directory on `$PATH`
(`tool/selftest-hermeticity-guard.sh:485-503`). A venv's `pyvenv.cfg` sits
one level above its `bin/`, so a venv anywhere else turns that guard red.
Measured 2026-10-09, same clone, same guard, only the venv moved:

- venv at `~/work/<run>/venv` (not a dot-directory): exit 1, eight guards listed as
  `OUTSIDE-REPO`, each because of `venv/pyvenv.cfg` or Pillow's bundled
  libraries under `venv/lib/`.
- venv at `~/.cache/sngnav-app-tool-venv`: exit 0,
  `HERMETIC: 9/9 self-test(s) run from a clean checkout.`

So a red from this guard on your machine may be your venv, not the guard.
Read the paths it prints before you change anything.

### 2.3 Android SDK

`tool/preflight_play_upload.sh` finds `aapt2` under
`${ANDROID_HOME:-$HOME/android-sdk}/build-tools/*/` (`preflight_play_upload.sh:795`);
`aapt2` and `apksigner` are not on `PATH` by default. Set `ANDROID_HOME`.
Measured 2026-10-09 on the maintainer's host: platforms 34, 35, 36;
build-tools 34.0.0, 35.0.0, 36.0.0; NDK 27.0, 27.2, 28.2. The preflight
requires target SDK 36 (`preflight_play_upload.sh:194`) and 16 KB page
alignment, which depends on the NDK (`preflight_play_upload.sh:44-47`).

### 2.4 Clone the whole history

```sh
git clone https://github.com/aki1770-del/sngnav-app
```

Do not use `--depth`. The loom mutation gate rebuilds an older version of the
manifest guard from git history and must see that commit; on a shallow clone
it stops rather than pass (`ci.yml:75-81`).

### 2.5 Installing it on a bare Ubuntu 24.04 machine

CI cannot show you this part: its runner image already holds the Android
SDK, and it installs Flutter, Java and Python through GitHub actions
(`ci.yml:94-96, 182-185, 509-512`). The steps below use each tool's own
distribution instead. Run them as an ordinary user with `sudo`, in this
order, one block at a time.

**1. System packages.** The first line is Flutter's own list of Linux
prerequisites (https://docs.flutter.dev/install/manual). The second adds
JDK 17, the venv module and `sqlite3`. The rest are the guard packages
from 2.2.

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  curl git unzip xz-utils zip libglu1-mesa ca-certificates \
  openjdk-17-jdk-headless python3 python3-venv sqlite3 \
  open-jtalk open-jtalk-mecab-naist-jdic hts-voice-nitech-jp-atr503-m001 \
  fonts-ipafont-gothic fonts-droid-fallback strace
```

**2. Flutter 3.47.5.** The archive and its SHA-256 are the ones Flutter's
release manifest lists for 3.47.5 stable
(https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json,
read 2026-10-09). If `sha256sum -c` does not print `OK`, stop.

```sh
mkdir -p ~/sdk
curl -fL -o ~/sdk/flutter_linux_3.47.5-stable.tar.xz \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
echo "2132e990f236f8d22e7c6314b29a191a95b10d7cbcfec9b4e2e303d996652cbb  $HOME/sdk/flutter_linux_3.47.5-stable.tar.xz" | sha256sum -c
tar -xf ~/sdk/flutter_linux_3.47.5-stable.tar.xz -C ~/sdk
export PATH="$HOME/sdk/flutter/bin:$PATH"
flutter --version
```

On a first run `flutter --version` may also say that a new version of
Flutter is available. Do not run `flutter upgrade`: CI pins 3.47.5.

**3. Android SDK.** Platform 36 and NDK 28.2.13676358 are what Flutter
3.47.5's Gradle plugin asks for; the app takes both from it
(`android/app/build.gradle.kts:141-142, 154-155`). The command-line tools
archive and its SHA-1 are the ones in Google's SDK repository index
(https://dl.google.com/android/repository/repository2-3.xml, read
2026-10-09); the `cmdline-tools/latest` layout and `--licenses` are from
https://developer.android.com/tools/sdkmanager.

```sh
export ANDROID_HOME="$HOME/android-sdk"
mkdir -p "$ANDROID_HOME/cmdline-tools"
curl -fL -o ~/sdk/commandlinetools-linux-16111833_latest.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
echo "e025545c62a8e64c7559119566a569fb1dec5f60  $HOME/sdk/commandlinetools-linux-16111833_latest.zip" | sha1sum -c
unzip -q ~/sdk/commandlinetools-linux-16111833_latest.zip -d "$ANDROID_HOME/cmdline-tools"
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
  "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"
```

These command-line tools (version 23.0) print that `sdkmanager` is
deprecated and that `--licenses` is no longer needed, then download a newer
`android` command and hand the work to it. Both lines above still worked
(measured 2026-10-09). The sdkmanager page names `android sdk install` as
the replacement.

**4. Point Flutter at the SDK and the JDK.** On an arm64 machine the JDK
directory ends in `-arm64`, not `-amd64`.

```sh
flutter config --android-sdk "$ANDROID_HOME"
flutter config --jdk-dir /usr/lib/jvm/java-17-openjdk-amd64
flutter doctor -v
```

`flutter doctor` should show the Android toolchain without an error. It
also complains about Chrome and the Linux desktop toolchain; this app needs
neither. Add the two `export` lines from steps 2 and 3 to `~/.profile` so a
new shell has them. Then clone (2.4), make the venv (2.2), and run
chapter 3.

**Measured 2026-10-09** in a fresh `ubuntu:24.04` container, in UTC, as an
ordinary user with `sudo`: the four blocks above, run with `bash -e`, exited
0 in 7 min 31 s. `flutter doctor -v` printed `Platform android-36,
build-tools 36.0.0`, `Java version OpenJDK Runtime Environment (build
17.0.20.1+1-1-24.04-Ubuntu)` and `All Android licenses accepted.`, and
complained only about Chrome and the Linux desktop toolchain. Then 2.4 and
the venv from 2.2 exited 0, and every step of 3.1 up to `flutter analyze`
passed. `flutter test` failed five render tests there, which is how the
time-zone rule in 3.3 was found; `TZ=Asia/Tokyo flutter test` then printed
`06:18 +1966 ~2: All tests passed!`, and both notification gates passed.
The rest of 3.1 (`flutter build apk --debug` and the audio-key check) was not
run on that machine: its network was lost partway through, and its first
Gradle build would have had to download its dependencies again. On the
main host those steps pass (3.1).

---

## 3. Build, analyze, test, run

### 3.1 The CI steps, in CI order

Run these from the repository root, in this order. This is CI's `test` job
(`ci.yml:70-481`) followed by its `android-build` job (`ci.yml:496-581`),
minus the `apt-get` and `pip` lines from chapter 2. One line differs from
CI: `flutter test` runs with `TZ=Asia/Tokyo`, because on your machine the
render tests compare their golden images, and those were cut at UTC+9 (3.3).
CI skips that comparison.

CI runs every step with `bash -e` (its log prints
`shell: /usr/bin/bash -e {0}`), so a step stops at the first command that
fails. Run them the same way: save the block below to a file outside the
checkout, for example `~/sngnav-ci-steps.sh`, and from the repository root
run

```sh
bash -e ~/sngnav-ci-steps.sh
```

It stops at the first command that exits non-zero, and that command's output
is the last thing on your screen. If you paste the lines into a terminal
instead, a failed line does not stop the next one, so read each exit status
(`echo $?`) before you go on.

Measured 2026-10-09: the block below, saved to a file and run with `bash -e`
on a fresh clone of `0149fa6f` with the venv from 2.2 on `PATH`, exited 0.
The audio keys file may live anywhere outside the checkout; CI uses
`$RUNNER_TEMP` (`ci.yml:577-581`).

```sh
# job: test
bash tool/loom_mutation_gate.sh --self-test
bash tool/assert_manifest_perms.sh --self-test
bash tool/assert_manifest_perms.sh
bash tool/assert_disclosure_parity.sh --self-test
bash tool/assert_disclosure_parity.sh
bash tool/glance_gate.sh --self-test
bash tool/glance_gate.sh
bash tool/offline_voice_render_guard.sh --self-test
bash tool/offline_voice_render_guard.sh
bash tool/tile-pipeline-defaults-guard.sh --self-test
bash tool/tile-archive-identity-guard.sh --self-test
SELFTEST_HERMETIC_REQUIRE_TRACE=1 bash tool/selftest-hermeticity-guard.sh --self-test
SELFTEST_HERMETIC_REQUIRE_TRACE=1 bash tool/selftest-hermeticity-guard.sh
# every tile archive; stops at the first that fails, and fails if there are none
(
  shopt -s nullglob
  archives=(assets/tiles/*.mbtiles)
  test ${#archives[@]} -gt 0 || { echo "no tile archives in checkout"; exit 1; }
  for m in "${archives[@]}"; do
    bash tool/tile-archive-identity-guard.sh "$m" || exit
  done
)
flutter pub get
flutter analyze
# off CI the render tests compare their goldens, which were cut at UTC+9 (3.3)
TZ=Asia/Tokyo flutter test
bash tool/assert_notification_fit.sh --self-test
bash tool/assert_notification_fit.sh

# job: android-build
flutter build apk --debug
KEYS="$(mktemp)"
SNGNAV_BUNDLED_AUDIO_KEYS_OUT="$KEYS" \
  flutter test test/voice/bundled_audio_platform_keys_test.dart
python3 tool/check_bundled_audio_in_apk.py \
  build/app/outputs/flutter-apk/app-debug.apk "$KEYS"
```

**What success looks like.** Measured 2026-10-09: the whole block exited 0
in 12 min 14 s, on a host that was also running another build (an earlier
run of the same steps without that load, before `TZ=Asia/Tokyo` was added on
this UTC+9 host, took 9 min 37 s). The table gives the line each step printed
**last**; where its pass line comes earlier, both are shown.

| Step | What it prints when it passes | Time |
|---|---|---|
| `loom_mutation_gate.sh --self-test` | `>> SELF-TEST: 2/2` | 2 s |
| `assert_manifest_perms.sh --self-test` | `SELF-TEST: 31/31 PASS` | 2 s |
| `assert_manifest_perms.sh` | `PASS: 5 WS1-blocker permissions + 1 voice-lane query intent(s) effectively declared in .../AndroidManifest.xml` | <1 s |
| `assert_disclosure_parity.sh --self-test` | `SELF-TEST: 13/13 PASS` | 1 s |
| `assert_disclosure_parity.sh` | `PASS: every egress host is named in both halves.` | 1 s |
| `glance_gate.sh --self-test` | `[self-test] refuses a hue-only surface, accepts a shape/size one, and fails closed ...` | <1 s |
| `glance_gate.sh` | `VERDICT: PASS`, then last `GLANCE GATE: 1 declared state surface(s) checked.` | <1 s |
| `offline_voice_render_guard.sh --self-test` | `SELF-TEST OK: 11/11 cases behaved.` | 12 s |
| `offline_voice_render_guard.sh` | `OK: 42 of 42 clips are byte-identical to what their catalog words render to.`, then last `Byte identity is not a listening test; nobody's ear is in this check.` | 28 s |
| `tile-pipeline-defaults-guard.sh --self-test` | `self-test 5/5 OK` | 2 s |
| `tile-archive-identity-guard.sh --self-test` | `self-test 12/12 OK` | 1 s |
| `selftest-hermeticity-guard.sh --self-test` | `>> SELF-TEST: 12/12` | 13 s |
| `selftest-hermeticity-guard.sh` | `HERMETIC: 9/9 self-test(s) run from a clean checkout.` (see 2.2) | 1 min 52 s |
| the tile archive step | `PASS — archive is self-consistent.` once per archive (Akita 1,552 tiles, then Gunma 777) | <1 s |
| `flutter pub get` | `Got dependencies!`, then `30 packages have newer versions incompatible with dependency constraints.`, then last ``Try `flutter pub outdated` for more information.`` That is expected: the lock is committed; do not upgrade it as a side effect (8.2) | 2 s |
| `flutter analyze` | `No issues found! (ran in 10.6s)` | 15 s |
| `TZ=Asia/Tokyo flutter test` | `07:48 +1966 ~2: All tests passed!` | 8 min 3 s |
| `assert_notification_fit.sh --self-test` | `SELF-TEST: 24/24 PASS` | <1 s |
| `assert_notification_fit.sh` | `PASS: every notification string fits by measurement, and the stop word survives at every checked text scale (NOT a device capture — see the header).` | 1 s |
| `flutter build apk --debug` | `✓ Built build/app/outputs/flutter-apk/app-debug.apk` | 49 s |
| `bundled_audio_platform_keys_test.dart` | `00:00 +1: All tests passed!` | 10 s |
| `check_bundled_audio_in_apk.py` | `GREEN: every key the offline voice sends opens in this APK.` (42 keys) | <1 s |

The two skipped tests (`~2`) are deliberate: they hold GPS-fault vectors "in
shadow until honest phone fixes are measured"
(`test/services/drive_gps_trust_invariant_test.dart`, printed as `Skip:`).

**How each fails.** Every guard prints the file and the reason, and exits
non-zero: 1 for a defect it found, 2 or 3 where it could not check (for
example `UNDETERMINED`, `UNMEASURED`, `trace-UNCHECKED`). Treat 2 and 3 as
"not checked", never as a pass.

**Why the tile archive step is written as it is.** A `for` loop's exit
status is that of its last command, so a one-line loop over the archives
reports only the last one: a missing or defective first archive passes
unseen. A pipe does the same (`ENCOUNTERED_TRAPS.md` TRAP-09). The step
above is CI's own (`ci.yml:436-443`), plus `|| exit`, so that it stops at the
first failing archive even when pasted into a terminal; it also fails when
there are no archives at all. Measured 2026-10-09 on a copy of the tree
whose first archive was absent and whose second was real: the one-line loop
this page used to give exited 0, and the step above exits 2. With a
defective first archive (its centre outside its bounds) they exit 0 and 1;
with none at all, the step above prints `no tile archives in checkout` and
exits 1. Run under `bash -e`, as CI runs it, the one-line loop did stop;
pasted into a terminal, it did not.

The most common causes of a red on a
developer machine are environmental: a missing face or open-jtalk (2.2),
Python 3.13 (2.2), a venv outside a dot-directory (2.2), a shallow clone
(2.4), another Flutter version (2.1), or a machine not at UTC+9 running the
render tests without `TZ=Asia/Tokyo` (3.3).

Notes on order, from the workflow itself:

- The cheap source-only guards run first so that a flaky SDK download cannot
  hide the manifest check (`ci.yml:168-181`).
- The glance gate runs after the Flutter SDK is present, because it reads the
  SDK's `material/colors.dart` to resolve colour names
  (`ci.yml:195-202`; `tool/glance_gate_run.py:52-66`).
- The notification fit gate runs after `flutter test` because it needs the
  Roboto font the SDK downloads (`ci.yml:465-473`).

### 3.2 What each guard checks

| Guard | What it refuses | Needs |
|---|---|---|
| `tool/loom_mutation_gate.sh` | A guard that passes a known-bad input (`loom_mutation_gate.sh:29-33`) | full git history |
| `tool/assert_manifest_perms.sh` | A manifest that lost INTERNET, location, WAKE_LOCK, VIBRATE or the text-to-speech `<queries>` entry, including by `tools:node="remove"` (`assert_manifest_perms.sh:1-33`) | python3 |
| `tool/assert_disclosure_parity.sh` | A permission the app holds, or a network host it contacts, that the privacy policy does not name (`assert_disclosure_parity.sh:1-40`) | |
| `tool/glance_gate.sh` | A declared state surface whose states differ only by colour (`ci.yml:238`; `tool/glance_gate_run.py:36-41`) | the Flutter SDK |
| `tool/offline_voice_render_guard.sh` | A bundled voice clip that no longer says its catalog words (`offline_voice_render_guard.sh:25-33`) | open-jtalk, Python 3.12 |
| `tool/tile-pipeline-defaults-guard.sh` | Tile renderer defaults that drifted from the shipped archive (`ci.yml:326-357`) | `tool/requirements.txt` |
| `tool/tile-archive-identity-guard.sh` | An `.mbtiles` whose metadata contradicts itself (`tile-archive-identity-guard.sh:1-20`) | |
| `tool/selftest-hermeticity-guard.sh` | A guard self-test that only passes because of a file outside the checkout (`selftest-hermeticity-guard.sh:1-40`) | strace |
| `tool/assert_notification_fit.sh` | Drive-notification text that does not fit its row, or loses the word 停止 / Stop, at text scale 1.0 to 2.0 (`assert_notification_fit.sh:33-36`; `ci.yml:474-477`) | Pillow, the fonts, the SDK's Roboto |
| `tool/check_bundled_audio_in_apk.py` | An APK that does not hold a voice clip at the key the app opens it by (`ci.yml:569-574`) | a built APK |
| `tool/preflight_play_upload.sh` | A release artifact Play would reject: signer, target SDK, 16 KB alignment, version code, permission parity (`preflight_play_upload.sh:23-56`) | release artifacts, `ANDROID_HOME` (chapter 5) |

Each guard with `--self-test` proves it can fail before it is trusted. A
guard that cannot check something exits non-zero; it does not skip. Do not
change a guard so that it passes in an environment it cannot check
(`ci.yml:75-81, 362-364`).

`tool/shipped_is_reachable.py` (every declared asset is reachable from code)
is not run by CI. Run it from the repository root:

```sh
python3 tool/shipped_is_reachable.py
```

Measured 2026-10-09: `declared assets checked: 4   unreachable: 0   undeclared
files under assets/: 0`, exit 0.

### 3.3 Golden images: CI does not compare them

The render tests under `test/render_see/` compare widgets against PNGs in
`render_out/` and `ladder_out/`. **They compare only off CI.** When `CI` or
`GITHUB_ACTIONS` is `true`, every golden comparison is replaced by a skip note
(`test/render_see/render_see_env.dart:460-464, 498-506`). Measured: the CI log
of `main` at `0149fa6f` (run 37887353459, job `test`) holds 43 lines
`render_see: golden comparison SKIPPED for ...`. The local run for this page
(no `CI` variable, both faces present) printed none, and every render test
passed with its comparison made.

So a green CI run says nothing about the goldens. Run them yourself, on
Flutter 3.47.5 with the two fonts from 2.2:

```sh
TZ=Asia/Tokyo flutter test test/render_see/
```

Measured 2026-10-09: `00:50 +60: All tests passed!`, exit 0, in 65 s, with
no golden comparison skipped.

**Set the time zone to UTC+9.** Five of these tests draw a time of day in
the machine's own time zone, and their goldens were cut on a machine at
UTC+9, Japan's offset. Anywhere else they fail by the difference. Measured
2026-10-09 on a bare Ubuntu machine in UTC: `04_advisory_ja_ordering`,
`06_advisory_jp_jma_only`, `16_advisory_retained_null_expires_jma`,
`19a_stale_feed_with_warning` and the feed-loss forecast-memory card failed
(19a: `Pixel test failed, 0.01%, 518px diff`; its golden reads
`2026-05-28 14:00`, and the run drew `05:00`). With `TZ=Asia/Tokyo` the same
files passed there, and on a UTC+9 host `TZ=UTC` made the same five fail.
CI cannot show this, because it skips the comparison. `scripts/build-verify.sh`
runs `flutter test` without a zone (`scripts/build-verify.sh:63`), so outside
UTC+9 run it as `TZ=Asia/Tokyo bash scripts/build-verify.sh` (not run for
this page).

To re-cut goldens after an intended visual change (`scripts/build-verify.sh:67`):

```sh
TZ=Asia/Tokyo flutter test --update-goldens test/render_see/
```

then **open the changed PNGs and look at them**, and commit them with the
change. On a tree you have not changed it rewrites nothing (measured
2026-10-09 in a separate clone of `0149fa6f`: exit 0, 0 files changed), so
every PNG it does change is a difference you, or your machine, made. Without
the zone it is worse than a red test: the same re-cut with `TZ=UTC` exited 0
and rewrote five goldens (`render_out/04_advisory_ja_ordering.png`, `06_`,
`16_`, `19a_` and `ladder_out/feed_loss/feed_loss_forecast_memory_ja.png`)
with UTC times, which a commit would then carry. A regenerated golden is
not a verified screen (`scripts/build-verify.sh:17-21, 70`). `SNGNAV_TEST_COMPARE_GOLDENS=1`
forces comparison anywhere (`render_see_env.dart:458-462`). Without the
Japanese faces, the render tests withdraw their pixel claim and print why
(`render_see_env.dart:17-23`).

### 3.4 Running the app (debug)

```sh
flutter run -d <emulator-or-test-device>
```

**Only against an emulator, or a phone that has no SNGNav release installed.**
When `flutter run` fails to install over an existing app, the Flutter tool
uninstalls that app, which deletes its data, and installs again, without
asking (`android/app/build.gradle.kts:58-81`, citing flutter_tools 3.47.5).
An install fails whenever the installed app was signed by another key, and on
the maintainer's phone every `adb` install fails (chapter 6). `flutter install`
and `flutter drive` uninstall the same way. The build script's own instruction
is: never point any of them at a phone that holds an SNGNav release
(`build.gradle.kts:120-132`).

The development page (cards built for testing, not shown to the driver)
appears only in a non-release build started with
(`lib/main.dart:146-155`):

```sh
flutter run -d <emulator-or-test-device> --dart-define=SNGNAV_DEVELOPER_PAGE=true
```

Always give `-d`. Without it, `flutter run` picks the device itself: if only
one is attached, it uses that one (flutter_tools 3.47.5,
`findAllTargetDevices` in `lib/src/runner/target_devices.dart`), so a phone
that holds a release, left plugged in, is where the build goes.

Measured 2026-10-09 on the API 30 emulator: each of the two lines above
built a debug build, installed it in place, launched it, and stayed
resident; `q` ended it (`Application finished.`, exit 0). With the
`--dart-define`, the app bar carried one more icon, the entry to the
development page; without it, the app bar held only the title (seen on
screenshots of both).

### 3.5 Commit hooks

The repository ships one hook (`.githooks/pre-commit`). Enable it per clone:

```sh
git config core.hooksPath .githooks
```

(`.githooks/README.md:8-10`). It fires only when `tool/*.py`,
`tool/requirements.txt` or `assets/tiles/*.mbtiles` are staged
(`.githooks/pre-commit:5`), and it runs a script that lives **outside this
repository** (`.githooks/pre-commit:7-9`). On any machine without that
script it prints `WARNING: gate script not found ... not blocking` and lets
the commit through (`pre-commit:13`); `.githooks/README.md:12-17` says the
same. In practice, for a contributor, the hook checks nothing. Where the
default script does exist, it checks the archives of a fixed directory
named inside that script, not those of the clone you are committing
(measured 2026-10-09; the script is outside this repository). Either way,
run the tile guards from 3.1 yourself when you touch those files.

---

## 4. Version identity

A version code names exactly one set of bytes. Android refuses an update
whose version code is not higher than the installed one, and Play refuses a
code it has seen before, so a second build at a used code reaches nobody as
an update (`tool/version_code_floor:5-8`). Every file below exists to keep
that true.

### 4.1 The pieces

| Piece | What it holds | Source |
|---|---|---|
| `pubspec.yaml` `version:` | `0.0.2+10` on `main`. Name `0.0.2`, code 10. The comment above it records why each code moved. | `pubspec.yaml:6-57` |
| `android/local.properties` | Gitignored. The Flutter Gradle plugin takes the version code **only** from here, and defaults an absent key to `1`. `flutter build` rewrites it from `pubspec.yaml`; a direct `gradlew` build does not. | `android/.gitignore:7`; `build.gradle.kts:215-228` |
| `assertVersionIdentity` | Refuses a **release or profile** build whose stamped version differs from `pubspec.yaml`. Debug builds and IDE sync are not blocked. | `build.gradle.kts:229-232, 262-304` |
| `tool/version_code_floor` | **14**: the highest code already spent under the release key or reported by a device. One number line only. Raise it, never lower it. The Play preflight's gate 4 reads it too. | `tool/version_code_floor:10-18, 25` |
| mint ledger | `$HOME/.sngnav/minted_release.tsv`, one row per release-key artifact built on that host (code, kind, sha256, commit, time). `SNGNAV_MINTED_LEDGER` moves where rows are written; the check reads that file and the default together. | `build.gradle.kts:332-348, 363-371` |
| `assertVersionCodeUnspent` | Under the release key only: refuses a code at or below the floor or below a ledger row, a second artifact of the same kind at one code, `--split-per-abi`, and APKs made through bundletool tasks. | `build.gradle.kts:306-353, 427-543` |
| `tool/play_uploaded_version_codes.txt` | Codes Google Play has accepted. **Empty**: nothing has been uploaded. Append only after an accepted upload. It is not the floor. | `play_uploaded_version_codes.txt:9-11, 28-42` |
| `tool/upload_key_certificate_sha256` | The SHA-256 of the upload key's **certificate** (public): `6a4906edb4ebdc5f54ad24ab1818054618adba480df98b4f4f1dac45600d0f14`. | `upload_key_certificate_sha256:1-29` |
| `lib/build_info.dart` `appVersion` | The version **name**, mirrored by hand; a test fails if it differs from `pubspec.yaml`. | `lib/build_info.dart:15-16`; `test/architectural/build_info_matches_pubspec_test.dart:11-16` |
| installed identity | The app reads its version code, name and git commit from the installed package, not from source, and stamps them into its footer, shared error log and drive diary. The commit carries `-dirty` if the tree had changes; `UNKNOWN` if git failed. | `lib/services/build_identity.dart:1-29`; `build.gradle.kts:18-47, 161-164` |

### 4.2 What each one refuses, in the words you will see

- `VERSION IDENTITY: this build would stamp <a> but pubspec.yaml says <b>: android/local.properties holds a stale flutter.versionCode/versionName` (or `... has no flutter.versionCode, so the Flutter Gradle plugin defaulted it to 1`). **Fix:** build with `flutter build apk` or `flutter build appbundle`, which rewrite the file, or move the version in `pubspec.yaml` (`build.gradle.kts:275-288`). On success it prints `VERSION IDENTITY OK: <name>+<code> == pubspec.yaml` (`build.gradle.kts:295-297`). Measured 2026-10-09: both release builds in 5.1 printed `VERSION IDENTITY OK: 0.0.2+10 == pubspec.yaml`. The refusal itself was not provoked for this page.
- ``VERSION CODE FLOOR: versionCode <n> is spent. tool/version_code_floor says every code up to <floor> is already used``, followed by ``Move `version:` in pubspec.yaml to +<floor+1> or higher`` (`build.gradle.kts:486-495`).
- `VERSION CODE FLOOR: versionCode <n> is below what this host has already minted` (`build.gradle.kts:497-505`).
- `VERSION CODE FLOOR: versionCode <n> already names these bytes` (`build.gradle.kts:506-522`). One code may hold the APK **and** the bundle of one release, built from the same clean commit; nothing else may share it (`build.gradle.kts:338-341`).
- `... split-per-abi gives each ABI's APK abi*1000+code` (`build.gradle.kts:464-474`). At code 14, an arm64 APK would carry 2014, and a phone holding it would refuse every later release from 15 to 2013.
- Without the release key the floor is not checked and nothing is written (`build.gradle.kts:441-452`).

### 4.3 Before a release build, do this

1. Read the floor: `grep -v '^#' tool/version_code_floor` prints `14` (Measured).
2. If you mint on a host that has a ledger, read it:
   `grep -v '^#' ~/.sngnav/minted_release.tsv | cut -f1 | sort -n | tail -1`.
   (Measured on the maintainer's host 2026-10-09: `14`.)
3. Choose a code above both. **On `main` today the next code is 15 or higher.**
   `main` itself says `+10` (`pubspec.yaml:57`), so a release-key build of
   `main` as it stands is refused by the floor. This is intended.
4. Edit `version:` in `pubspec.yaml`. If you change the name, change
   `lib/build_info.dart:16` to match.
5. Commit, so the tree is clean. A dirty tree stamps `<sha>-dirty` into the
   build (`build.gradle.kts:26-29, 45`) and cannot share a code with the other
   kind of the same release (`build.gradle.kts:508-512`).
6. Build with `flutter build`, never with `gradlew` directly (4.2, first item).
7. After a build made on a machine whose ledger is not this one, or reported
   back by a device, raise `tool/version_code_floor` (`build.gradle.kts:343-345`;
   `tool/version_code_floor:15-18`).

Measured from history, not a rule: `main` says `+10`, from commit `4cb56af`,
the last version change merged there. The version commit for code 13,
`89ed430`, is only on `origin/code13-fix-timing-record`, a branch
`lib/services/code13_record_cleanup.dart:6` says "is never merged". No
remote branch holds `+11`, `+12` or `+14` (Measured: `pubspec.yaml` read on
every `origin/*` branch). So `pubspec.yaml` on `main` does not record which
codes are spent; the floor file does.

---

## 5. Release builds and signing

### 5.1 Without the upload key (every contributor)

The upload key is the maintainer's. It is gitignored and has never been
committed (`android/.gitignore:11-15`; `ci.yml:592-597`). Without it:

- **A release build of the driver's app is refused before packaging.** With
  no signing configuration, Gradle falls back to the debug key, and
  `assertReleaseSigner` refuses it (`build.gradle.kts:1003-1077`). Measured
  2026-10-09 on a fresh clone of `0149fa6f` with no signing configuration,
  `flutter build apk --release` exited 1 (after 132 s, on a host also
  running another build):

  ```text
  Execution failed for task ':app:assertReleaseSigner'.
  > RELEASE SIGNER: refused before packaging. This release build would be signed with the
    debug key: C=US, O=Android, CN=Android Debug (certificate SHA-256 <your debug key>), from
    the debug keystore (there is no android/key.properties and no injected signing).
  ```

  followed by the two ways forward the refusal names: sign with the upload
  key, or build a development release.
- **A development release is allowed, as another app.** Say so with
  `SNGNAV_DEV_RELEASE=1`. The build gets the package
  `dev.aki1770del.sngnav_app.dev`, the launcher label `DEV SNGNav`
  (開発用 SNGNav on a Japanese phone), and the debug key. It installs beside
  an SNGNav release and cannot replace it or its data, and its version code
  spends nothing (`build.gradle.kts:83-106, 191-198, 444-446`). Build first,
  then run, as one line, because `flutter run --release` decides which app to
  stop on quit before it builds (`build.gradle.kts:108-118, 1068-1073`):

  ```sh
  SNGNAV_DEV_RELEASE=1 flutter build apk --release && SNGNAV_DEV_RELEASE=1 flutter run --release -d <device>
  ```

  Measured 2026-10-09: `SNGNAV_DEV_RELEASE=1 flutter build apk --release`
  exited 0 (after 201 s, same host load) and printed `RELEASE SIGNER: NOT THE UPLOAD KEY. ...`,
  `VERSION CODE FLOOR: not checked: SNGNAV_DEV_RELEASE=1 builds this release
  as dev.aki1770del.sngnav_app.dev, another app, so its versionCode 10 spends
  none of hers, and it writes no ledger row`, and
  `✓ Built build/app/outputs/flutter-apk/app-release.apk (97.2MB)`.
  `aapt2 dump badging` on that file: `package: name='dev.aki1770del.sngnav_app.dev'
  versionCode='10'`, `application-label:'DEV SNGNav'`,
  `application-label-ja:'開発用 SNGNav'`; `apksigner` reads one signer,
  `CN=Android Debug`. The host's mint ledger was not modified (its SHA-256
  was the same before and after both builds). The file is
  still named `app-release.apk`; its package, not its name, says which app it is.
  The whole line, with `-d emulator-5580`, then built again, installed the
  `.dev` app beside the driver's app on the API 30 emulator, ran it, and
  stopped on `q` (`Application finished.`, exit 0). Give `-d` here too, for
  the reason in 3.4.
- **Profile builds are always the `.dev` app** (`build.gradle.kts:200-206`).
- **Debug builds keep the driver's package** and are never signed by the
  upload key; `assertDebugSigner` refuses one that would be
  (`build.gradle.kts:120-124, 1114-1195`). A debug build is never a build for
  the driver's phone.
- `SNGNAV_DEV_RELEASE` must be exactly `1`; any other value is refused and the
  refusal says so (`build.gradle.kts:134-135, 1074`).

### 5.2 With the upload key (maintainer only)

- Signing comes from the gitignored `android/key.properties`, or from Android
  Studio's "Generate Signed Bundle / APK" (`build.gradle.kts:13-17, 1066-1067`).
  Never commit either. If injected signing is used, set all four
  `android.injected.signing.*` properties or none; an empty one is refused
  (`build.gradle.kts:782-784, 822-846`).
- On success the build prints `RELEASE SIGNER OK: signed by ..., the upload
  key (certificate SHA-256 ... matches tool/upload_key_certificate_sha256)`
  (`build.gradle.kts:1046-1051`) and `VERSION CODE FLOOR OK: ...` (`build.gradle.kts:532-536`),
  and appends a ledger row (`MINT LEDGER: appended to ...`, `build.gradle.kts:688-690`).
- **Read the signer from the file before it goes anywhere.** The Gradle gate
  reads the keystore, not the bytes it produced (`build.gradle.kts:790-794`):

  ```sh
  "$ANDROID_HOME"/build-tools/36.0.0/apksigner verify --print-certs <file.apk>
  ```

  It must print exactly one signer whose `certificate SHA-256 digest` equals
  `tool/upload_key_certificate_sha256` (the check CI runs, `ci.yml:784-799`).
- For a Play upload, build the bundle and run the preflight
  (`preflight_play_upload.sh:164-170`):

  ```sh
  bash tool/preflight_play_upload.sh --self-test   # proves its own predicates fail
  bash tool/preflight_play_upload.sh               # builds AAB + APK here, then 5 gates
  ```

  It refuses to run while `SNGNAV_DEV_RELEASE` is set
  (`preflight_play_upload.sh:249-258`). A pass means the file is acceptable to
  upload, nothing more: "a bundle can pass all five gates and be dead on the
  driver's phone" (`preflight_play_upload.sh:58-62`). Measured 2026-10-09: `--self-test` → `SELF-TEST: 92/92 PASS`, exit 0. The full preflight was not run for this page; it needs the upload key.

### 5.3 The CI release job has never produced a build

`release-apk` runs only on manual dispatch (`ci.yml:606-607`) and refuses
without four repository secrets (`ci.yml:592-604, 716-726`). Measured
2026-10-09: `gh api repos/aki1770-del/sngnav-app/actions/secrets` → `0`
secrets; workflow runs with `event=workflow_dispatch` → `0` of 179. The
`android-build` job discards the APK it builds (`ci.yml:584-586`). So every
release build that has reached a phone was made on a developer machine
(`build.gradle.kts:750-754` says the same as of 2026-10-04, and
`docs/store/play_route_oct31.md:20-26` as of 2026-10-09).

### 5.4 Rules that hold whoever builds

- Never reuse a spent version code (chapter 4).
- With the release key, build one universal APK: no `--split-per-abi`, and no
  bundletool APK tasks (`build.gradle.kts:326-331, 454-474`).
- Never hand a `.dev` build on as SNGNav (`build.gradle.kts:1041`).
- The update check reads `tool/update_manifest.json` from `main` on GitHub
  (`lib/services/update_check.dart:204-208`). That file does not exist at
  `0149fa6f`. Measured 2026-10-09:
  `curl -s -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/aki1770-del/sngnav-app/main/tool/update_manifest.json`
  → `404`. The app treats a non-200 answer as `noAnswer`, never as "up to
  date" (`update_check.dart:50-52, 439-443`). Until that file exists, no
  build can tell its holder that a newer one is available.

---

## 6. Getting a build onto a real Android phone

### 6.1 Which kind of device you have

| Device | What to install | How |
|---|---|---|
| Emulator | debug build | `flutter run -d <emulator serial>` (3.4), or `adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk` (Measured on API 30: `Success`) |
| Your own phone, no SNGNav installed | debug build, or a `.dev` release | as above |
| A phone that holds an SNGNav release | only an upload-key release of `dev.aki1770del.sngnav_app` with a higher version code; or a `.dev` build beside it | push and tap (6.2). **Never** `flutter run`, `flutter install` or `flutter drive` (3.4). |

An installed app takes an update only from the certificate that signed it.
A release signed by any other key cannot update the app on that phone, and,
installed first, blocks every upload-signed fix until the app is uninstalled,
which deletes its data (`build.gradle.kts:742-749, 1061-1065`).

### 6.2 When `adb install` is refused: push to Download/, then tap

On the maintainer's phone (Xiaomi, MIUI), `adb install` fails whatever the
key: `Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]`,
seen on 2026-09-19 and 2026-10-02. It is a refusal of the USB install channel
by a setting on that phone, not of a key (`build.gradle.kts:68-72`). Builds
reach that phone by push and tap (`build.gradle.kts:80-81, 742-743`):

```sh
sha256sum <file.apk>                                   # on the host
adb -s <serial> push <file.apk> /sdcard/Download/<file.apk>
adb -s <serial> shell sha256sum /sdcard/Download/<file.apk>   # must equal the host's
```

Then, on the phone, open the file in a file manager and tap it, with
"install unknown apps" allowed for that file manager
(`RELEASE_NOTES_0.0.2.md:37-38`).

**On the phone: cited, not reproduced for this page.** This is the route
recorded for codes 12 to 14 on the maintainer's phone (project record outside
this repository: `adb -s <serial> push` to `/sdcard/Download/`, then the
on-device `sha256sum` compared with the host's).

**On an emulator: measured.** On the API 30 emulator `sngnav_api30`, started
`-read-only -no-snapshot`, a push 3 s after `sys.boot_completed` became `1`
failed (`adb: error: failed to copy ...`), and the same push 12 s after it
worked; the on-device `sha256sum` equalled the host's. The first version of
this page saw the same failure (`remote couldn't create file: Operation not
permitted`) on a push made seconds after boot, and suspected `-read-only`;
the person who followed that version pushed to the same read-only emulator
about two and a half minutes after boot, and it worked. So `-read-only` is
not the cause, and pushing too soon after boot is the likely one. What was
not yet ready was not determined (`sys.user.0.ce_available` was already
`true`). If you see that error on an emulator, wait a few seconds and push
again. It says nothing about a phone.

Always pass `-s <serial>` when more than one device can be attached.

### 6.3 Reading back what is installed: a receipt is a device read

"Installed" is a statement about a phone, so it is settled by reading the
phone, after the install, with the time of the read written beside it.
Four fields settle which build is there:

```sh
P=dev.aki1770del.sngnav_app
adb -s <serial> shell "dumpsys package $P | grep -E 'versionCode=|versionName=|firstInstallTime=|lastUpdateTime=|signatures='"
adb -s <serial> shell pm path $P                       # prints package:<path>/base.apk
adb -s <serial> shell sha256sum <path>/base.apk        # hash ON the device
adb -s <serial> shell date +%FT%T%z                    # the phone's clock, with its UTC offset
date -u                                                # the host's clock, in UTC: the read expires; stamp it
```

**Two clocks.** `firstInstallTime` and `lastUpdateTime` are printed in the
phone's own time zone, and the line does not say which. `date -u` on the host
is UTC. The `date +%FT%T%z` line reads the phone's clock with its offset, so
subtract that offset before you compare a phone time with a UTC stamp.
Measured 2026-10-09 on the emulator: its clock read `2026-10-09T14:59:17+0900`
while the host's `date -u` read `05:59:18 UTC`, so its
`lastUpdateTime=2026-10-09 14:59:14` below is 05:59:14 UTC.

| Field | Reading it |
|---|---|
| `versionCode=` | the code the phone runs |
| `sha256sum` of `base.apk` on the device | equals the hash of the file you built: these are your bytes |
| `firstInstallTime=` | unchanged since the first install: no uninstall happened, so the app's data was kept |
| signer | one signer, the upload key, by certificate SHA-256 |

`dumpsys package` prints only a short `signatures:[<hash>]`, not the
certificate (seen on Android 10 on the maintainer's phone, and on API 30). To read the signer, pull the installed APK and run
`apksigner verify --print-certs` on it, or show that its on-device hash
equals a file whose signer you have read. That second route is how the
maintainer's phone was read on 2026-10-09 (project record kept outside this
repository; the phone reported `versionCode=14`, a `base.apk` hash equal to
the minted file, `firstInstallTime` unchanged since 2026-09-17, and the
pinned signer).

Measured 2026-10-09 on the API 30 emulator, after
`adb -s emulator-5580 install -r build/app/outputs/flutter-apk/app-debug.apk`
(`Success`) over a debug build installed there on 2026-08-21:

```text
    versionCode=10 minSdk=24 targetSdk=36
    versionName=0.0.2
    firstInstallTime=2026-08-21 20:55:18
    lastUpdateTime=2026-10-09 14:59:14
    signatures=PackageSignatures{7ac1e19 version:2, signatures:[cb15a9b4], past signatures:[]}
```

`firstInstallTime` kept its August date: the update was in place. The
on-device `sha256sum` of `base.apk` printed `2b8173db...27d802`, the same as
`sha256sum` of the APK on the host, and `apksigner verify --print-certs` on a
pulled copy printed one signer, `CN=Android Debug`. The `.dev` release then
installed beside it: `pm list packages sngnav` printed both
`dev.aki1770del.sngnav_app` and `dev.aki1770del.sngnav_app.dev`.

**Starting it from the shell.** `am start` needs the launcher activity, which
`aapt2` reads out of the APK:

```sh
"$ANDROID_HOME"/build-tools/36.0.0/aapt2 dump badging <file.apk> | grep launchable-activity
adb -s <serial> shell am start -W -n dev.aki1770del.sngnav_app/.MainActivity
adb -s <serial> shell am start -W -n dev.aki1770del.sngnav_app.dev/dev.aki1770del.sngnav_app.MainActivity
```

The second line starts the driver's app, the third the `.dev` build: its
package differs, its activity class does not.
Measured 2026-10-09 on the emulator: `aapt2` printed
`launchable-activity: name='dev.aki1770del.sngnav_app.MainActivity'` for the
debug APK and for the `.dev` release. The `.dev` line printed `Status: ok`,
`LaunchState: COLD`, `TotalTime: 4178`. The debug build's line printed
`Status: timeout` after 10.4 s: `am start -W` stopped waiting, and the app
did start, as its `am_proc_start` and `wm_on_resume_called` in the event log
show (6.4). A debug build starts more slowly than a release one; when you see
`timeout`, read the event log before you conclude anything.

A debug build also logs its own identity at each launch, debug builds only
(`lib/main.dart:1687-1700`). Measured on the emulator:

```text
I flutter : SNGNAV_UPDATE_CHECK status=noAnswer running=0.0.2 (10) · 2b8173dbd68d · 0149fa6 ...
```

that is: name, code, the first 12 hex digits of the APK's hash, and the git
commit it was built from.

A process that is not running is not a build that never ran: `pidof` printing
nothing says only that there is no process now. The event log (6.4) says
whether it started.

### 6.4 Logs

```sh
adb -s <serial> logcat -d -s flutter                    # the app's own lines (docs/on_device_verify_checklist.md:166)
adb -s <serial> shell "logcat -d -b events -v UTC -v year | grep dev.aki1770del.sngnav_app"
adb -s <serial> shell dumpsys activity services dev.aki1770del.sngnav_app
adb -s <serial> shell cmd appops get dev.aki1770del.sngnav_app START_FOREGROUND
adb -s <serial> shell cmd appops get dev.aki1770del.sngnav_app FINE_LOCATION
```

In the first line the first `-s` is `adb`'s and names the device; the second
is `logcat`'s and keeps only the `flutter` tag.

Use `-d` (dump and exit). Do not use `logcat -c`, which clears a buffer
someone else may still need. The `events` buffer records process starts
(`am_proc_start`) and kills (`am_kill`). Every buffer covers a limited window;
read its first line to know how far back it goes. Measured on the emulator
after `am start`: `am_proc_start: [0,3931,10168,dev.aki1770del.sngnav_app,pre-top-activity,...]`,
then `wm_on_create_called` and `wm_on_resume_called`, and
`wm_activity_launch_time` for a launch that `am start -W` waited out (6.3).

**Reading `dumpsys activity services`: the record is not the drive.** The
location service `com.baseflow.geolocator.GeolocatorLocationService` is
listed after a plain launch, as a service the app's own process has bound.
Measured on the emulator about 20 s after a launch with no drive started: the
record was present with `hasBound=true`, and there was no `isForeground`
line and no notification from the app; the `START_FOREGROUND` line of 6.4
printed `No operations.` (then `Default mode: allow`), and the `FINE_LOCATION`
line `FINE_LOCATION: allow; time=+48d16h33m48s493ms ago`, a last location
access 48 days earlier. A
running drive shows `isForeground=true` in that record
(`docs/DEVICE_VERIFICATION.md:126-129`; `docs/on_device_verify_checklist.md:152-155`).
Grep for `isForeground`, not for the service name.

**With the `.dev` build installed beside, the services line shows both
apps.** The name you give is not matched exactly:
`dumpsys activity services dev.aki1770del.sngnav_app` also listed
`dev.aki1770del.sngnav_app.dev`, and its record came first (measured). Read the
`packageName=` line of a record before you read its `isForeground`.

---

## 7. Traps measured on a real phone

These were found on the maintainer's phone, a Xiaomi Mi Note 10 Pro on
Android 10 (MIUI 12), in October 2026. Tests and emulators did not show them.

### 7.1 Whatever runs at launch runs before anyone can act

`main()` awaits `deleteCode13FixTimingRecord()` before `runApp`
(`lib/main.dart:157-176`). It deletes two files a test build (code 13) wrote,
because that build told its user the next build would
(`lib/services/code13_record_cleanup.dart:1-14`). Anything in `main()` before
`runApp`, and anything in the first frame, runs on the **first launch after an
update**, and the first launch may be the installer's own "Open" button. On
2026-10-08 code 14 was launched from the package installer's screen 2 min 6 s
after it was installed (project record outside this repository). If a user
must do something first, such as share a record that a launch-time step
deletes, they have to do it **before** the new build is installed. Nothing in
the app can wait for them once it is installed.

### 7.2 MIUI's power manager ends a running drive

On 2026-10-08 at 11:28:53Z, MIUI ended the app's running location foreground
service, about four hours into a drive and 3 min 48 s after the user left the
app. The event log read:

```text
am_kill: [0,15712,dev.aki1770del.sngnav_app,200,AutoPowerKill]
```

followed by `am_proc_died` and the geolocator notification being cancelled
(project record outside this repository). The app did not end the drive and
neither did the driver; the phone's power manager did. Look for it with the
`events` command in 6.4 and `grep am_kill`; the last field names the reason.
No output (and `grep` exiting 1) means no kill of the app inside the
buffer's window, which starts at the buffer's first line.
`docs/DEVICE_VERIFICATION.md:55-58` asks for exactly this ("document any
OEM ... killer"), and `KNOWN_LIMITATIONS.md:196-200` says that if Android
ends the app, everything ends. A stock emulator cannot reproduce this.

A cached, idle process was also killed later that night
(`AutoLockOffCleanByPriority`, about 91 minutes in the background, no service
running). That one is ordinary.

### 7.3 An in-place update keeps data and notification settings

On the same phone, the update from code 13 to 14 kept the app's data directory
(same `firstInstallTime`, same data inode) and the notification settings (the
filtered `dumpsys notification --proto` output was byte-identical before and
after). The system log said `Update package ... Retain data and using new`
(project record outside this repository). This holds only for an in-place
update signed by the same key. An uninstall, including the one `flutter run`
performs (3.4), deletes the data.

### 7.4 Known from the repository

- `flutter run` / `flutter install` / `flutter drive` uninstall on a failed
  install (`build.gradle.kts:58-81, 120-132`).
- `adb install` is refused on that phone (`build.gradle.kts:68-72`).
- The drive notification: on an Android 14 emulator it was absent from the
  lock screen and one swipe removed it while the service kept running; the
  maintainer's phone is unverified (`docs/DEVICE_VERIFICATION.md:99-159`).
- The first drive after a fresh install on Android 13+ runs screen-on only,
  because the notification permission is asked but not awaited
  (`KNOWN_LIMITATIONS.md:228-235`).
- Code-level traps for anyone changing the app: `ENCOUNTERED_TRAPS.md`
  TRAP-03 (stream errors), TRAP-08 and TRAP-10 (what actually resolved),
  TRAP-09 (exit codes through pipes), TRAP-17 to TRAP-21 (guards that read
  text instead of code, and release-only silence that `flutter test` cannot
  see because it runs in debug mode).

---

## 8. Changing the app

### 8.1 Branch, push, PR

1. Branch from `main`. Any branch name gets CI on push (`ci.yml:32-34, 62`),
   and a pull request runs it again (`ci.yml:63`).
2. Before you push, run chapter 3.1, and `TZ=Asia/Tokyo flutter test
   test/render_see/` on Flutter 3.47.5 if you changed anything visible (3.3).
3. Open a pull request against `main`.
4. Check that CI is green for your head commit; nothing enforces it.
   Measured 2026-10-09: `main` has one active ruleset, which blocks deletion
   and force-push and nothing else; there are no required status checks and
   no required reviews (`gh api repos/aki1770-del/sngnav-app/rulesets/16050281`).
   Read the result yourself:

   ```sh
   gh pr checks <number>
   ```

5. Expect review by the maintainer. The last eight merged pull requests were
   all opened from the maintainer's account, with no review decision
   recorded (Measured: `gh pr list --state merged --limit 8`).

There is no `CONTRIBUTING.md` and no pull-request template. Blank issues are
disabled (`.github/ISSUE_TEMPLATE/config.yml:1`); the two issue templates are
written in Japanese for drivers and testers (`.github/ISSUE_TEMPLATE/02_bug_report.yml:1-12`).

Observed practice, not an enforced rule (Measured over the last 200
non-merge commits on `main`): commit subjects are plain sentences saying what
changed and why, with no `feat:`/`fix:` prefixes (0 of 200), and almost no
trailers (one `Co-Authored-By` in 200).

### 8.2 Gates a change must pass, by what you touched

| You changed | Run, and read |
|---|---|
| any Dart | `flutter analyze` (0 issues) and `flutter test`; see `ENCOUNTERED_TRAPS.md` TRAP-20: `flutter test` runs in debug mode and cannot see a line silenced only in release |
| anything drawn | `TZ=Asia/Tokyo flutter test test/render_see/` locally (3.3); re-cut goldens only for an intended change, at the same zone, and look at them |
| a state the driver must tell apart (real / mock / degraded, and so on) | the glance gate checks only surfaces declared in `tool/glance_gate_run.py:36-41`; today that is one, `_HerDot` in `lib/akita_map.dart`. A new state surface is not checked until you declare it there with a rendered-pixel test |
| the drive-notification strings | `bash tool/assert_notification_fit.sh`; it measures width, not character count, because a Japanese glyph is about two Latin ones wide (`assert_notification_fit.sh:12-16`) |
| `AndroidManifest.xml`, a permission, or a new network host | `bash tool/assert_manifest_perms.sh` and `bash tool/assert_disclosure_parity.sh`; a new host or permission must be named in both language halves of `docs/store/privacy_policy_ja.md`, and the gate clears itself (`assert_disclosure_parity.sh:46, 95`; `ci.yml:158-161`) |
| a spoken Japanese safety line | re-render with `bash tool/render_offline_voice.sh` (`render_offline_voice.sh:19-20`), then `bash tool/offline_voice_render_guard.sh`; the app finds a clip by its exact words (`offline_voice_render_guard.sh:7-23`) |
| `pubspec.yaml` dependencies | commit `pubspec.lock`; a lock overrides a range (`pubspec.yaml:52-54`); print what resolved (`ENCOUNTERED_TRAPS.md` TRAP-08, TRAP-10, TRAP-17) |
| `tool/*.py`, `tool/requirements.txt`, `assets/tiles/` | the tile guards in 3.1; to rebuild the basemap, follow `tool/README_TILES.md`, which installs from `tool/requirements.txt` |
| the version | chapter 4; `lib/build_info.dart` for a name change |
| a guard under `tool/` | its `--self-test`, `tool/loom_mutation_gate.sh --self-test`, and the hermeticity guard |

The accessibility floor is a reach requirement, not polish: location consent
is deny-by-default and in the phone's language, alerts go out by voice and
vibration as well as on screen, and the screen is held lit during a drive
(`KNOWN_LIMITATIONS.md:30-39, 189-240`; `docs/DEVICE_VERIFICATION.md:27-66`).

### 8.3 When you find a new trap

Add a `TRAP-NN` entry to `ENCOUNTERED_TRAPS.md` before the change merges,
using the same fields as the entries above it (`ENCOUNTERED_TRAPS.md:236-238`).

---

## 9. When something is wrong

### 9.1 Where to look

| Symptom | Look at |
|---|---|
| a guard is red | its own output names the file and the reason; run its `--self-test` to see whether the guard or the input is at fault |
| red only on your machine | toolchain (2.1), fonts and open-jtalk (2.2), the venv location (2.2), a shallow clone (2.4), a time zone other than UTC+9 for the render tests (3.3) |
| the app misbehaves on a device | `adb -s <serial> logcat -d -s flutter`; the `events` buffer for kills (6.4); `isForeground=true` in `dumpsys activity services` for a running drive (6.4) |
| a user reports a problem | the in-app ログを共有 action exports the on-device error log (size-capped, never sent automatically, `KNOWN_LIMITATIONS.md:343-347`), stamped with the installed build's identity (`lib/services/build_identity.dart:1-6`) |
| on-device checks to run | `docs/on_device_verify_checklist.md` (10-minute pass) and `docs/DEVICE_VERIFICATION.md` (actuators, long drive); both now say which device to run them on, and why (`docs/on_device_verify_checklist.md:72-78`; `docs/DEVICE_VERIFICATION.md:17-19`) |

### 9.2 The existing docs, and what each is for

| Doc | For | State at `0149fa6f` |
|---|---|---|
| `README.md` | what the app does and does not do | "How to run" names Flutter 3.47.5 and the device condition (corrected 2026-10-09) |
| `KNOWN_LIMITATIONS.md` | every limit a user or developer must know | its two stale sections carry dated corrections (2026-10-09) |
| `ENCOUNTERED_TRAPS.md` | trap log, pre-flight checks per change | some entries cite files kept outside this repository (Appendix A) |
| `docs/DEVICE_VERIFICATION.md` | on-device checklist: voice, vibration, wakelock, long drive, notification | install condition and status corrected 2026-10-09; no item ticked on a physical phone |
| `docs/on_device_verify_checklist.md` | 10-minute on-device pass | install step and status corrected 2026-10-09; no item ticked on a physical phone |
| `BETA_PLAN.md` | the July beta plan and why it was missed | a dated plan; read as history |
| `docs/store/play_route_oct31.md` | the Play Console route | a dated plan; a 2026-10-09 note says its CI-artifact step names a file no run has produced |
| `docs/ARM_IVI_HANDOFF.md` | what moves to a head unit, what does not | not changed since the first version of this page |
| `tool/README_TILES.md` | rebuilding the offline basemap | installs from `tool/requirements.txt` (corrected 2026-10-09) |
| `.githooks/README.md` | enabling the hook | says what the hook runs and when it checks nothing (corrected 2026-10-09) |
| `RELEASE_NOTES_0.0.2.md` | what the 0.0.2 builds have and have not been shown to do | dated 2026-09-18 and 2026-09-24 |

### 9.3 What not to claim

- **"Tests green" is not "works on a device".** A green suite proves the code
  path; only a device shows the permission dialog, the dot, the voice and the
  vibration (`docs/DEVICE_VERIFICATION.md:8-13`; `KNOWN_LIMITATIONS.md:30-39`).
- **CI green says nothing about the goldens.** CI skips them (3.3).
- **An emulator is not a phone.** The emulator walks ran with `-no-audio` and
  a server voice (`docs/on_device_verify_checklist.md:15-18`), and stock
  emulators do not have MIUI's power manager (7.2).
- **"Installed" is a device read, not a word.** Read the four fields (6.3) and
  stamp the time.
- **A passing gate is evidence about the field it reads and nothing else**
  (`tool/assert_disclosure_parity.sh:39`). The preflight passing means
  "acceptable to upload", not "works" (`preflight_play_upload.sh:58-62`).
- **"No process" is not "never ran"** (6.3).
- When you catch your own overstatement, correct it on the record in the same
  change, and say what it said before. The repository's docs do this
  throughout; follow the same habit.

---

## Appendix A. Where an existing file disagrees with the source

The first version of this page listed fifteen of these, A1 to A15, against
`ca7738d5`. Pull request #31 corrected all fifteen on `main` (merged
2026-10-09; merge commit `0149fa6f`): the run and install conditions in
`README.md` and both device checklists, the two stale sections of
`KNOWN_LIMITATIONS.md`, the line reference in `BETA_PLAN.md`, a note on the
CI-artifact step in `docs/store/play_route_oct31.md`, the toolchain pin in
`scripts/build-verify.sh`, the install line in `tool/README_TILES.md`, the
trap count and three citations of an outside file in `ENCOUNTERED_TRAPS.md`,
the comment on
the disclosure gate in `ci.yml`, the preflight comment in
`build.gradle.kts`, the code 14 line in `tool/version_code_floor`, and the
floor test, which now fails when the floor is lowered
(`test/architectural/version_code_floor_test.dart:45-57`).

Still open:

- **A16.** `ENCOUNTERED_TRAPS.md` cites files that are not in this repository
  at lines 31, 89, 95, 115, 135, 145 and 155, and names a directory outside
  it at line 101. They cannot be opened from a clone. Each entry's own
  symptom, class and pre-flight check stand without them.

## Appendix B. How this page was measured

- Clone: `git clone https://github.com/aki1770-del/sngnav-app`, at
  `0149fa6f757188b61a60f8ed0dff07d62fea14a2`, read on GitHub at
  2026-10-09T05:24:17Z (no open pull requests; CI on that commit: `test`
  success, `android-build` success, `release-apk` skipped).
- Host: Ubuntu 24.04.4 LTS at UTC+9, Flutter 3.47.5, JDK 21 for Gradle,
  Python 3.12.3.
- Run on the host: the 3.1 block, saved to a file and run with `bash -e`;
  3.2; 3.3's two commands (the re-cut in a separate clone); 5.1's two builds;
  3.4 and chapter 6 on the AVD `sngnav_api30` (Android 11, API 30), started
  `-read-only -no-snapshot`, with every `adb` call limited to that emulator.
- Run on a bare machine: 2.5, then 2.4, the venv from 2.2 and the 3.1 block
  with `bash -e`, in a fresh `ubuntu:24.04` container, as an ordinary user
  with `sudo`, in UTC: everything passed up to `flutter test`, which failed
  five render tests until run with `TZ=Asia/Tokyo` (3.3), then passed with
  the notification gates after it. `flutter build apk --debug` and the
  audio-key check were not run there (2.5).
- The tile archive step in 3.1 was also run against copies of the tree whose
  first archive was absent or defective, and with no archives.
- Not run: anything on a physical phone; anything with the upload key; a
  Play upload; the full preflight; `scripts/build-verify.sh`. The phone facts
  in chapters 6 and 7 come from the project's records of reads made on
  2026-10-08 and 2026-10-09, kept outside this repository.
