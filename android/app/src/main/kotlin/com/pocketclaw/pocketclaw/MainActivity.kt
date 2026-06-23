package com.pocketclaw.pocketclaw

import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class MainActivity : FlutterActivity() {
    private val shareChannelName = "pocketclaw/share"
    private val deviceChannelName = "pocketclaw/device"

    // Reusable handler that will be registered on both main and overlay engine contexts.
    private val deviceCallHandler = MethodCallHandler { call, result ->
        when (call.method) {
            "checkAppPermissions" -> {
                result.success(checkAppPermissions())
            }
            "requestAppPermissions" -> {
                requestAppPermissions()
                result.success(ok("Permissions requested."))
            }
            "setTorch" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                result.success(setTorch(enabled))
            }
            "openDialer" -> {
                val phone = call.argument<String>("phone").orEmpty()
                result.success(openDialer(phone))
            }
            "openSms" -> {
                val phone = call.argument<String>("phone").orEmpty()
                val body = call.argument<String>("body").orEmpty()
                result.success(openSms(phone, body))
            }
            "openCalendar" -> {
                val title = call.argument<String>("title").orEmpty()
                val notes = call.argument<String>("notes").orEmpty()
                result.success(openCalendar(title, notes))
            }
            "openAlarm" -> {
                val label = call.argument<String>("label").orEmpty()
                val hour = call.argument<Int>("hour")
                val minute = call.argument<Int>("minute")
                result.success(openAlarm(label, hour, minute))
            }
            "openLocationSettings" -> result.success(openLocationSettings())
            "openWebSearch" -> {
                val query = call.argument<String>("query").orEmpty()
                result.success(openWebSearch(query))
            }
            "openApp" -> result.success(openApp())
            "getVoiceTrigger" -> {
                val trigger = intent?.getBooleanExtra("pocketclaw_voice_trigger", false) ?: false
                if (trigger) {
                    intent?.removeExtra("pocketclaw_voice_trigger")
                }
                result.success(trigger)
            }
            "setWakeLock" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                result.success(setWakeLock(enabled))
            }
            "openAppSettings" -> {
                result.success(openAppSettings())
            }
            "sendNotification" -> {
                val title = call.argument<String>("title").orEmpty()
                val body = call.argument<String>("body").orEmpty()
                result.success(sendNotification(title, body))
            }
            "requestNotificationPermission" -> {
                requestNotificationPermission()
                result.success(ok("Notification permission requested."))
            }
            else -> result.notImplemented()
        }
    }

    private fun openAppSettings(): Map<String, Any> {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
            startIntent(intent, "Opening app settings.")
        } catch (e: Exception) {
            fail("Failed to open app settings: ${e.message}")
        }
    }

    private var wakeLock: android.os.PowerManager.WakeLock? = null

    private fun setWakeLock(enabled: Boolean): Map<String, Any> {
        return try {
            val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            if (enabled) {
                if (wakeLock == null) {
                    wakeLock = powerManager.newWakeLock(
                        android.os.PowerManager.PARTIAL_WAKE_LOCK,
                        "pocketclaw:continuous_voice_wakelock"
                    )
                }
                if (wakeLock?.isHeld == false) {
                    wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes max safety limit
                    android.util.Log.d("MainActivity", "PocketClaw: Acquired PARTIAL_WAKE_LOCK for continuous listening.")
                }
                ok("WakeLock acquired.")
            } else {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                    android.util.Log.d("MainActivity", "PocketClaw: Released PARTIAL_WAKE_LOCK.")
                }
                wakeLock = null
                ok("WakeLock released.")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to toggle WakeLock: ${e.message}")
            fail("Failed to toggle WakeLock: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register standard sharing
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> {
                        val text = call.argument<String>("text").orEmpty()
                        if (text.isBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                        }
                        startActivity(Intent.createChooser(sendIntent, "Share"))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Register on main engine
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
            .setMethodCallHandler(deviceCallHandler)

        // Register accessibility channel — routes to PocketClawAccessibilityService.instance
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocketclaw/accessibility")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(PocketClawAccessibilityService.instance != null)
                    "openAccessibilitySettings" -> {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS,
                        ).apply { addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK) }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> {
                        val service = PocketClawAccessibilityService.instance
                        if (service == null) {
                            result.success(
                                mapOf("ok" to false,
                                      "message" to "Accessibility service not enabled"),
                            )
                        } else {
                            service.handleCall(call, result)
                        }
                    }
                }
            }

        // Periodically scan and register on the background engine when cached
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val checkEngineRunnable = object : Runnable {
            var attempts = 0
            override fun run() {
                val bgEngine = io.flutter.embedding.engine.FlutterEngineCache.getInstance().get("cahed_overlay_engine")
                if (bgEngine != null) {
                    MethodChannel(bgEngine.dartExecutor.binaryMessenger, deviceChannelName)
                        .setMethodCallHandler(deviceCallHandler)
                    android.util.Log.d("MainActivity", "PocketClaw: Registered device MethodChannel on background overlay engine.")
                } else if (attempts < 30) {
                    attempts++
                    handler.postDelayed(this, 1000)
                }
            }
        }
        handler.post(checkEngineRunnable)
    }

    private fun ok(message: String): Map<String, Any> = mapOf("ok" to true, "message" to message)
    private fun fail(message: String): Map<String, Any> = mapOf("ok" to false, "message" to message)

    private fun checkAppPermissions(): Map<String, Any> {
        val micGranted = applicationContext.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val cameraGranted = applicationContext.checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val notificationGranted = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            applicationContext.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return mapOf(
            "mic" to micGranted,
            "camera" to cameraGranted,
            "notifications" to notificationGranted
        )
    }

    private fun requestAppPermissions() {
        val permissions = arrayOf(
            android.Manifest.permission.RECORD_AUDIO
        )
        try {
            requestPermissions(permissions, 101)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to request permissions: ${e.message}")
        }
    }

    private fun requestNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            try {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 102)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to request notification permission: ${e.message}")
            }
        }
    }

    private fun sendNotification(title: String, body: String): Map<String, Any> {
        return try {
            val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            val channelId = "pocketclaw_local_channel"
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val channel = android.app.NotificationChannel(
                    channelId,
                    "PocketClaw Local Notifications",
                    android.app.NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "PocketClaw local notifications channel"
                }
                notificationManager.createNotificationChannel(channel)
            }
            
            val builder = androidx.core.app.NotificationCompat.Builder(applicationContext, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title.ifBlank { "PocketClaw" })
                .setContentText(body)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                
            notificationManager.notify(System.currentTimeMillis().toInt(), builder.build())
            ok("Notification sent successfully.")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to send notification: ${e.message}")
            fail("Failed to send notification: ${e.message}")
        }
    }

    private fun setTorch(enabled: Boolean): Map<String, Any> {
        return try {
            val cameraManager = applicationContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: return fail("This device doesn't expose a flashlight.")
            cameraManager.setTorchMode(cameraId, enabled)
            ok(if (enabled) "Flashlight is on." else "Flashlight is off.")
        } catch (_: SecurityException) {
            fail("Camera permission is needed to control the flashlight.")
        } catch (_: Exception) {
            fail("Couldn't control the flashlight on this device.")
        }
    }

    private fun openDialer(phone: String): Map<String, Any> {
        if (phone.isBlank()) return fail("Tell me the phone number first.")
        return startIntent(
            Intent(Intent.ACTION_DIAL, Uri.parse("tel:${Uri.encode(phone)}")),
            "Opening the dialer."
        )
    }

    private fun openSms(phone: String, body: String): Map<String, Any> {
        val uri = if (phone.isBlank()) Uri.parse("smsto:") else Uri.parse("smsto:${Uri.encode(phone)}")
        return startIntent(
            Intent(Intent.ACTION_SENDTO, uri).putExtra("sms_body", body),
            "Opening SMS."
        )
    }

    private fun openCalendar(title: String, notes: String): Map<String, Any> {
        return startIntent(
            Intent(Intent.ACTION_INSERT).apply {
                data = CalendarContract.Events.CONTENT_URI
                putExtra(CalendarContract.Events.TITLE, title.ifBlank { "PocketClaw reminder" })
                if (notes.isNotBlank()) putExtra(CalendarContract.Events.DESCRIPTION, notes)
            },
            "Opening calendar."
        )
    }

    private fun openAlarm(label: String, hour: Int?, minute: Int?): Map<String, Any> {
        return startIntent(
            Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_MESSAGE, label.ifBlank { "PocketClaw alarm" })
                if (hour != null) putExtra(AlarmClock.EXTRA_HOUR, hour)
                if (minute != null) putExtra(AlarmClock.EXTRA_MINUTES, minute)
            },
            "Opening alarm."
        )
    }

    private fun openLocationSettings(): Map<String, Any> {
        return startIntent(
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
            "Opening location settings."
        )
    }

    private fun openWebSearch(query: String): Map<String, Any> {
        if (query.isBlank()) return fail("Tell me what to search for.")
        val uri = Uri.parse("https://www.google.com/search?q=${Uri.encode(query)}")
        return startIntent(Intent(Intent.ACTION_VIEW, uri), "Opening web search.")
    }

    private fun openApp(): Map<String, Any> {
        val launch = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)
            ?: return fail("Couldn't open PocketClaw.")
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch.putExtra("pocketclaw_voice_trigger", true)
        return startIntent(launch, "Opening PocketClaw.")
    }

    private fun startIntent(intent: Intent, successMessage: String): Map<String, Any> {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            applicationContext.startActivity(intent)
            ok(successMessage)
        } catch (_: Exception) {
            fail("No app is available for that action.")
        }
    }
}
