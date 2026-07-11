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
    }
}
