package com.arena.os

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "arena/app" channel — lets Flutter ask the OS to send the app to
        // the BACKGROUND (like pressing Home) instead of destroying the
        // activity. Used by the root screen's back-button handler so a
        // double-back doesn't kill the realtime connection.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arena/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
