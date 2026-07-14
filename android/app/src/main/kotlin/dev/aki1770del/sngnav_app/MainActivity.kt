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
                        return@setMethodCallHandler
                    }
                    // Exactly-once reply guard: completion, error, cap, and
                    // the catch below all race for the single result slot —
                    // a MethodChannel result must never be answered twice.
                    val replied = java.util.concurrent.atomic.AtomicBoolean(false)
                    fun reply(ok: Boolean) {
                        if (replied.compareAndSet(false, true)) result.success(ok)
                    }
                    try {
                        // Flutter assets live under flutter_assets/<declared path>.
                        val key = "flutter_assets/$asset"
                        val afd = assets.openFd(key)
                        val player = android.media.MediaPlayer()
                        player.setAudioAttributes(
                            android.media.AudioAttributes.Builder()
                                .setUsage(
                                    android.media.AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE,
                                )
                                .setContentType(
                                    android.media.AudioAttributes.CONTENT_TYPE_SPEECH,
                                )
                                .build(),
                        )
                        player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                        afd.close()
                        // Free the native player when the phrase finishes; a
                        // leaked MediaPlayer per warning would exhaust the
                        // device over a long winter drive. Completion is the
                        // TRUE resolution: the phrase reached its end.
                        player.setOnCompletionListener {
                            it.release()
                            reply(true)
                        }
                        // A mid-phrase error is NOT a completed delivery:
                        // resolve false so the Dart side can fall back.
                        player.setOnErrorListener { mp, _, _ ->
                            mp.release()
                            reply(false)
                            true
                        }
                        player.prepare()
                        player.start()
                        // Native backstop cap: the longest bundled phrase is
                        // ~13.5 s; a player still unresolved at 30 s is wedged
                        // (neither completion nor error will ever fire).
                        // Release it and answer the channel so the native
                        // player is not leaked even if the Dart timeout
                        // already gave up listening.
                        android.os.Handler(android.os.Looper.getMainLooper())
                            .postDelayed({
                                if (replied.compareAndSet(false, true)) {
                                    try {
                                        player.release()
                                    } catch (_: Exception) {
                                    }
                                    result.success(false)
                                }
                            }, 30_000)
                    } catch (e: Exception) {
                        // Never crash the surface she is driving on. Report the
                        // failure honestly so the caller can fall back to TTS.
                        reply(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
