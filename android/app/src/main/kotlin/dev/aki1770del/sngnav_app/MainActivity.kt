package dev.aki1770del.sngnav_app

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Tier-2 AudioReadinessProbe — the unit's first first-party Kotlin
/// (Chair-ratified 2026-07-11; proposal §Tier-2).
///
/// WHY this exists: media-volume-zero silences every spoken safety alert,
/// and no plugin in our set can read the media volume — the ONE
/// Dart-unreachable gap on the voice lane. Without this read the app drives
/// HER into an Akita whiteout believing its ja warning will sound, while the
/// platform plays it into silence.
///
/// WHY it is READ-ONLY BY DESIGN (the Tier-3 dignity boundary the Chair
/// holds): we inform HER that her spoken lane is silent and let HER decide;
/// we NEVER touch her volume, request audio focus here, or override her
/// settings. A volume-raising actuator (USAGE_ALARM critical alert) is
/// Tier-3 — post-beta, evidence-gated, and a dignity question for the
/// Chair, never an engineering default. No permissions, no state, no
/// coroutines: a synchronous main-thread read, answered inline.
class MainActivity : FlutterActivity() {
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
                            "ttsServiceVisible" to ttsServiceVisible,
                        ),
                    )
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

                    // DUCKING (Chair-lifted ③, 2026-07-23): the bundled offline
                    // safety voice — the one that works in a dead zone — asks
                    // HER music/podcast to DUCK for the phrase, so a black-ice
                    // warning is heard OVER her audio instead of buried under
                    // it. TRANSIENT_MAY_DUCK only (never TRANSIENT_EXCLUSIVE,
                    // never USAGE_ALARM — those remain a deferred Chair-gated
                    // Tier-3; this stays within the ducking she authorized). A
                    // no-op focus-change listener: a STARTED safety phrase runs
                    // to completion — we asked music to yield, we never drop a
                    // half-spoken warning to yield back. On-device ducking is
                    // OPS-066-DEFERRED (no device here); a car-speaker FM/AM
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

                    try {
                        // Flutter assets live under flutter_assets/<declared path>.
                        val key = "flutter_assets/$asset"
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
                        // back to TTS.
                        abandonFocus()
                        reply(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
