// Copy into the generated Android host and adapt the package declaration if needed.
package com.example.hybrid_music_player

import android.media.audiofx.Virtualizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var virtualizer: Virtualizer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "echo/audio_effects",
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "setVirtualizerEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val sessionId = call.argument<Int>("audioSessionId") ?: 0
                    if (enabled && sessionId == 0) {
                        result.error("NO_AUDIO_SESSION", "Load a track before enabling 3D audio.", null)
                        return@setMethodCallHandler
                    }
                    virtualizer?.release()
                    virtualizer = if (enabled) {
                        Virtualizer(0, sessionId).apply {
                            strength = 850.toShort()
                            enabled = true
                        }
                    } else {
                        null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        virtualizer?.release()
        virtualizer = null
        super.onDestroy()
    }
}
