package dev.aki1770del.sngnav_app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Tier-2 AudioReadinessProbe — the unit's first first-party Kotlin
/// (decided 2026-07-11; proposal §Tier-2).
///
/// WHY this exists: media-volume-zero silences every spoken safety alert,
/// and no plugin in our set can read the media volume — the ONE
/// Dart-unreachable gap on the voice channel. Without this read the app sends
/// the driver into an Akita whiteout believing its ja warning will sound, while the
/// platform plays it into silence.
///
/// WHY it is READ-ONLY BY DESIGN (the Tier-3 dignity boundary the project
/// holds): we inform the driver that her spoken channel is silent and let her decide;
/// we NEVER touch her volume, request audio focus here, or override her
/// settings. A volume-raising actuator (USAGE_ALARM critical alert) is
/// Tier-3 — post-beta, evidence-gated, and a dignity question for the
/// project owner, never an engineering default. No permissions, no state, no
/// coroutines: a synchronous main-thread read, answered inline.
class MainActivity : FlutterActivity() {
    /// The one outstanding POST_NOTIFICATIONS ask, held between requestPermissions
    /// and its callback. Exactly one may be in flight: a second ask while one is
    /// pending is answered false rather than queued, because two system dialogs
    /// stacked over a driver who is trying to start a drive is not a consent
    /// surface, it is an obstacle.
    private var pendingNotificationPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sngnav/audio_readiness",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    // Explicit types at SDK seams (platform-type discipline):
                    // getSystemService returns Object/platform types; pin them.
                    val audioManager: AudioManager =
                        getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    // Is ANY TTS service resolvable? A device with no TTS
                    // engine at all cannot speak regardless of volume.
                    val ttsServiceVisible: Boolean = packageManager.resolveService(
                        Intent(TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE),
                        0,
                    ) != null
                    result.success(
                        mapOf(
                            "mediaVolume" to
                                audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
                            "mediaVolumeMax" to
                                audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                            // A stream can be MUTED at a non-zero index, and
                            // Android answers that through a different call.
                            // Measured 2026-08-22 on AVD sngnav_api30:
                            // dumpsys audio said "STREAM_MUSIC: Muted: true"
                            // while getStreamVolume returned 5 of 15 — so the
                            // index alone read a silent device as audible and
                            // the media-muted caution never rendered.
                            "streamMuted" to
                                audioManager.isStreamMute(AudioManager.STREAM_MUSIC),
                            "ttsServiceVisible" to ttsServiceVisible,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }

        // ------------------------------------------------------------------
        // BUILD IDENTITY -- "which artifact is this, actually?"
        //
        // BIS ruled 2026-09-24 that a versionCode does NOT name a build: as of
        // that day versionCode 2 carried SEVEN distinct release-signed
        // byte-sets under one upload certificate, all mutually installable
        // over each other on her phone. `package_info_plus` is confirmed as
        // the read but REJECTED as sufficient alone, and two alongside-values
        // are required. This channel supplies both.
        //
        // A-1 selfSha256 -- SHA-256 of applicationInfo.sourceDir, the APK's own
        //     bytes. Derived from NOTHING BUT THE ARTIFACT: no injection, no
        //     operator step, no file to forget, no permission. V15 tier 1,
        //     *cannot be done wrong*. Computed off the main thread and cached
        //     for the process: BIS measured 636-950 ms over the real 50 MB APK
        //     on this emulator, which is far too long to sit on a frame.
        //     BOUND (BIS): sourceDir is the BASE split. Under an AAB with
        //     splits this names only part of what is installed; splitSourceDirs
        //     are folded in below in a defined order so the value stays honest,
        //     and a multi-split install is reported by count.
        //
        // A-2 gitSha -- read back from the manifest meta-data gradle stamped,
        //     through PackageManager, NOT from a Dart constant.
        // ------------------------------------------------------------------
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sngnav/build_identity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    // Answer on a worker thread: hashing ~50 MB must never
                    // touch the frame pump of a surface she drives on.
                    Thread {
                        val payload = try {
                            val ai = applicationInfo
                            // Defined order: base first, then any splits
                            // sorted, so the digest is reproducible.
                            val parts = mutableListOf<String>()
                            ai.sourceDir?.let { parts.add(it) }
                            ai.splitSourceDirs?.let { parts.addAll(it.sorted()) }
                            val md = java.security.MessageDigest.getInstance("SHA-256")
                            val buf = ByteArray(1 shl 16)
                            for (path in parts) {
                                java.io.FileInputStream(path).use { ins ->
                                    while (true) {
                                        val n = ins.read(buf)
                                        if (n <= 0) break
                                        md.update(buf, 0, n)
                                    }
                                }
                            }
                            val hex = md.digest().joinToString("") {
                                "%02x".format(it)
                            }
                            val meta = packageManager.getApplicationInfo(
                                packageName,
                                android.content.pm.PackageManager.GET_META_DATA,
                            ).metaData
                            mapOf(
                                "selfSha256" to hex,
                                "artifactCount" to parts.size,
                                "gitSha" to (meta?.getString(
                                    "dev.aki1770del.sngnav_app.gitSha",
                                ) ?: "UNKNOWN"),
                            )
                        } catch (e: Exception) {
                            // A build that cannot name itself must still drive
                            // her home. Null selfSha256 is the honest third
                            // state; the Dart side renders UNIDENTIFIED BUILD
                            // and refuses to compare, rather than guessing.
                            android.util.Log.w(
                                "SngnavBuildIdentity",
                                "could not read build identity: " +
                                    "${e.javaClass.simpleName}: ${e.message}",
                            )
                            null
                        }
                        runOnUiThread { result.success(payload) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // The offline MOUTH — plays a bundled ja safety phrase from the APK.
        //
        // WHY FIRST-PARTY: the safety voice was briefly routed through the
        // `audioplayers` plugin, whose Android module ships its own buildscript
        // pinned to Kotlin 1.7.10 / AGP 7.3.1 and declares a top-level
        // `kotlin { }` block for a plugin it never applies. Under Flutter's
        // modern plugin-loader that block cannot resolve, and it BROKE THE APK
        // BUILD OUTRIGHT while `flutter test` stayed green — the tests never
        // build an APK. A voice that must work on a road with no network cannot
        // sit on a third-party Gradle contract that can silently un-build the
        // app. So the mouth is ours: MediaPlayer, one file, no plugin.
        //
        // Contract: play(asset) resolves TRUE only when playback actually
        // COMPLETED. It used to resolve at start(): every caller's `await`
        // returned the moment audio BEGAN, so two sequential safety phrases
        // (e.g. black-ice then turmoil, awaited one after the other on the
        // Dart side) each created an un-queued MediaPlayer and SPOKE ON TOP
        // OF EACH OTHER — two overlapping warnings deliver zero warnings.
        // Resolving on the completion listener makes sequential awaits
        // serialize again. A false/absent result means she was NOT verifiably
        // spoken to in full, and the caller falls back rather than assuming
        // she heard something. The Dart side keeps its own timeout as the
        // recovery cap; the Handler cap below is the native backstop that
        // frees a wedged player and answers the channel.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sngnav/bundled_audio",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    val asset: String? = call.argument<String>("asset")
                    if (asset.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler // pre-focus: nothing to abandon
                    }
                    // Exactly-once reply guard: completion, error, cap, and
                    // the catch below all race for the single result slot —
                    // a MethodChannel result must never be answered twice.
                    // `focusAbandoned` mirrors it so audio-focus is abandoned
                    // exactly once whichever of the four exits wins the race.
                    val replied = java.util.concurrent.atomic.AtomicBoolean(false)
                    val focusAbandoned = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun reply(ok: Boolean) {
                        if (replied.compareAndSet(false, true)) result.success(ok)
                    }

                    // DUCKING (lifted ③, decided 2026-07-23): the bundled offline
                    // safety voice — the one that works in a dead zone — asks
                    // the driver's music/podcast to DUCK for the phrase, so a black-ice
                    // warning is heard OVER her audio instead of buried under
                    // it. TRANSIENT_MAY_DUCK only (never TRANSIENT_EXCLUSIVE,
                    // never USAGE_ALARM — those remain a deferred owner-decided
                    // Tier-3; this stays within the ducking she authorized). A
                    // no-op focus-change listener: a STARTED safety phrase runs
                    // to completion — we asked music to yield, we never drop a
                    // half-spoken warning to yield back. On-device ducking is
                    // on-device verification DEFERRED (no device here); a car-speaker FM/AM
                    // radio cannot be ducked by the phone (VOICE_MISSION.md).
                    val audioManager: AudioManager =
                        getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val focusListener = AudioManager.OnAudioFocusChangeListener { }
                    val nav = android.media.AudioAttributes.Builder()
                        .setUsage(
                            android.media.AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE,
                        )
                        .setContentType(
                            android.media.AudioAttributes.CONTENT_TYPE_SPEECH,
                        )
                        .build()
                    // API 26+ carries a request object; 24-25 (our minSdk is 24)
                    // requests/abandons by listener. The request is INSTANTIATED
                    // only inside SDK_INT>=26 guards, so the API-26 class never
                    // loads on 24-25.
                    val focusRequest: android.media.AudioFocusRequest? =
                        if (android.os.Build.VERSION.SDK_INT >=
                            android.os.Build.VERSION_CODES.O) {
                            android.media.AudioFocusRequest.Builder(
                                android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                            )
                                .setAudioAttributes(nav)
                                .setOnAudioFocusChangeListener(
                                    focusListener,
                                    android.os.Handler(android.os.Looper.getMainLooper()),
                                )
                                .build()
                        } else {
                            null
                        }
                    fun abandonFocus() {
                        if (focusAbandoned.compareAndSet(false, true)) {
                            try {
                                if (android.os.Build.VERSION.SDK_INT >=
                                    android.os.Build.VERSION_CODES.O) {
                                    focusRequest?.let {
                                        audioManager.abandonAudioFocusRequest(it)
                                    }
                                } else {
                                    @Suppress("DEPRECATION")
                                    audioManager.abandonAudioFocus(focusListener)
                                }
                            } catch (_: Exception) {
                                // best-effort; never crash the surface she drives on
                            }
                        }
                    }

                    // Flutter assets live under flutter_assets/<declared path>.
                    // tool/check_bundled_audio_in_apk.py reads this line to check
                    // a built APK, so keep the rule on one line in this form.
                    val key = "flutter_assets/$asset"
                    try {
                        val afd = assets.openFd(key)
                        val player = android.media.MediaPlayer()
                        player.setAudioAttributes(nav)
                        player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                        afd.close()
                        // Free the native player when the phrase finishes AND
                        // abandon focus (EXIT 1 — normal end); a leaked
                        // MediaPlayer or a never-released duck over a long winter
                        // drive is the failure. Completion is the TRUE
                        // resolution: the phrase reached its end.
                        player.setOnCompletionListener {
                            it.release()
                            abandonFocus()
                            reply(true)
                        }
                        // A mid-phrase error is NOT a completed delivery
                        // (EXIT 2): abandon focus + resolve false so the Dart
                        // side can fall back.
                        player.setOnErrorListener { mp, _, _ ->
                            mp.release()
                            abandonFocus()
                            reply(false)
                            true
                        }
                        player.prepare()
                        // Request the duck AFTER a good prepare() (so a prepare
                        // failure never leaves music ducked for a phrase that
                        // never plays) and before start(). DENIAL does not gate
                        // a safety phrase — we speak regardless; the grant only
                        // decides whether her audio ducks. Return discarded.
                        if (android.os.Build.VERSION.SDK_INT >=
                            android.os.Build.VERSION_CODES.O) {
                            focusRequest?.let { audioManager.requestAudioFocus(it) }
                        } else {
                            @Suppress("DEPRECATION")
                            audioManager.requestAudioFocus(
                                focusListener,
                                android.media.AudioManager.STREAM_MUSIC,
                                android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                            )
                        }
                        player.start()
                        // Native backstop cap (EXIT 3): a player still unresolved
                        // at 30 s is wedged (neither completion nor error will
                        // fire). Release it, abandon focus, and answer the channel
                        // so nothing is leaked even if the Dart timeout already
                        // gave up listening. The longest bundled phrase is ~14 s.
                        android.os.Handler(android.os.Looper.getMainLooper())
                            .postDelayed({
                                if (replied.compareAndSet(false, true)) {
                                    try {
                                        player.release()
                                    } catch (_: Exception) {
                                    }
                                    abandonFocus()
                                    result.success(false)
                                }
                            }, 30_000)
                    } catch (e: Exception) {
                        // Never crash the surface she is driving on. Abandon
                        // focus (EXIT 4 — idempotent whether or not it was held)
                        // and report the failure honestly so the caller falls
                        // back to TTS. One log line, no stack trace: without it a
                        // clip that cannot be opened turns into a TTS line with
                        // nothing in a release logcat to say so.
                        android.util.Log.w(
                            "SngnavBundledAudio",
                            "bundled clip not played, falling back to TTS: $key " +
                                "(${e.javaClass.simpleName}: ${e.message})",
                        )
                        abandonFocus()
                        reply(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // THE NOTIFICATION SHE CAN SEE -- the permission that decides whether
        // the ongoing-drive service is honest or invisible.
        //
        // Measured 2026-09-24 on AVD sng_arc (API 34) at targetSdk 36, before
        // this existed: the foreground service started fine and its notification
        // was BLOCKED (numEnqueuedByApp=1, numPostedByApp=0, numBlocked=1; no
        // entry in the shade). She would have had location running with nothing
        // on screen naming it or ending it. See AndroidManifest.xml.
        //
        // READ-ONLY where it can be: `read` never prompts. `request` prompts
        // once and answers what she said. Neither decides anything -- the Dart
        // side decides, and its rule is that a denied notification means NO
        // foreground service, not a silent one.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sngnav/notification_permission",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    val nm: NotificationManager =
                        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    // Two DIFFERENT questions, both of which can silence her:
                    //  - granted: the API-33 runtime permission.
                    //  - enabled: notifications switched off for the app in
                    //    Settings, which is possible at ANY api level and which
                    //    the permission check alone reads as fine.
                    val granted: Boolean =
                        Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(
                                "android.permission.POST_NOTIFICATIONS",
                            ) == PackageManager.PERMISSION_GRANTED
                    result.success(
                        mapOf(
                            "granted" to granted,
                            "enabled" to nm.areNotificationsEnabled(),
                            "needsRuntimeRequest" to (Build.VERSION.SDK_INT >= 33),
                        ),
                    )
                }
                "request" -> {
                    if (Build.VERSION.SDK_INT < 33) {
                        // No runtime permission exists below 33; the channel
                        // answers the QUESTION ("can we post?"), not the API.
                        val nm: NotificationManager =
                            getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager
                        result.success(nm.areNotificationsEnabled())
                        return@setMethodCallHandler
                    }
                    if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (pendingNotificationPermission != null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    pendingNotificationPermission = result
                    requestPermissions(
                        arrayOf("android.permission.POST_NOTIFICATIONS"),
                        POST_NOTIFICATIONS_REQUEST,
                    )
                }
                else -> result.notImplemented()
            }
        }

        // BACK DURING A DRIVE -- the app goes to the background, as with Home.
        //
        // Without this, Back on the main page ended the drive with nothing
        // said to her: Flutter's SystemNavigator.pop() makes this plain
        // Activity call finish(), the engine goes with it, and the position
        // stream and the drive notification with the engine. Measured on an
        // Android 14 emulator on 2026-09-25. The Dart side (lib/main.dart,
        // PopScope) now intercepts Back while a drive runs and asks for this
        // instead. moveTaskToBack does not finish the activity, so nothing is
        // torn down: the drive continues as the consent she read says it does
        // when she switches away, and 停止 remains the way to end it.
        // nonRoot=true: move the whole task whichever activity is on top.
        // Answers what the platform answered; false leaves the app where it
        // is, with the drive running and 停止 on the page.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sngnav/app_task",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveTaskToBack" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != POST_NOTIFICATIONS_REQUEST) return
        val granted: Boolean =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        // A dismissed dialog returns an EMPTY grantResults, which is a denial
        // for our purposes: she was not asked-and-agreed, so the service must
        // not start behind an invisible notification.
        pendingNotificationPermission?.success(granted)
        pendingNotificationPermission = null
    }

    companion object {
        private const val POST_NOTIFICATIONS_REQUEST = 4331
    }
}
