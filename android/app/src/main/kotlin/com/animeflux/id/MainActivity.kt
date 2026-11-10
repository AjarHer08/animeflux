package com.animeflux.id

import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "animeflux/pip"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // FlutterActivity sudah meregistrasi plugin otomatis; registrasi manual
        // kedua kali bisa menimbulkan error plugin ganda.
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPiP" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                enterPictureInPictureMode()
                                result.success(null)
                            } else {
                                result.error(
                                    "UNSUPPORTED",
                                    "PiP butuh Android 8+",
                                    null
                                )
                            }
                        } catch (e: Exception) {
                            Log.e("AnimeFlux", "PiP error", e)
                            result.error("PIP_FAILED", e.message, null)
                        }
                    }
                    "isPiPSupported" -> {
                        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        result.success(supported)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
