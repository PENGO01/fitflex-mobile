package com.fitflexafrica.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMessagesChannel()
    }

    // App photos (HERO_IMAGES_REMOTE): the app asks before downloading
    // whether Data Saver is on and how much storage is free.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fitflex/device_data")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "reducedData" -> result.success(dataSaverOn())
                    "freeBytes" -> result.success(freeBytes())
                    else -> result.notImplemented()
                }
            }
    }

    // Data Saver on and this app not exempted. Unknown, or Android below 7.0
    // (no Data Saver to ask), counts as on: no downloads (DeviceDataRules).
    private fun dataSaverOn(): Boolean {
        val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)
                ?.restrictBackgroundStatus
        } else {
            null
        }
        return DeviceDataRules.dataSaverOn(Build.VERSION.SDK_INT, status)
    }

    private fun freeBytes(): Long? = try {
        StatFs(filesDir.path).availableBytes
    } catch (e: Exception) {
        null
    }

    // Pushes without a channel land in Android's low-key default one: no
    // pop-up, easy to miss. FitFlex messages get their own channel that
    // pops up and makes a sound (AndroidManifest names it as the default).
    // Creating a channel that already exists only refreshes its name and
    // description, which follow the phone's language (res/values-sw).
    private fun createMessagesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "fitflex_messages",
            getString(R.string.channel_messages_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = getString(R.string.channel_messages_description) }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
