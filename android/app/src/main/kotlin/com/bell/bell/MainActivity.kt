package com.bell.bell

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL            = "com.bell/call"
        const val WAHOO_CHANNEL      = "com.bell/wahoo"
        const val WAHOO_EVENT_CHANNEL = "com.bell/wahoo_events"
        const val CALL_NOTIF_ID      = 42
        const val CALL_CH_ID         = "bell_call_ch"

        val WAHOO_PACKAGES = listOf(
            "com.wahooligan.android.elmnt",
            "com.wahooligan.android.bolt",
            "com.wahooligan.android.roam",
        )

        // Keywords in the Bluetooth device name that identify a Wahoo head-unit.
        val WAHOO_DEVICE_KEYWORDS = listOf("ELEMNT", "BOLT", "ROAM", "WAHOO")
    }

    // ── Wahoo Bluetooth Classic event stream ──────────────────────────────────
    private var wahooEventSink: EventChannel.EventSink? = null

    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val device: BluetoothDevice? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent?.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent?.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                }
            val name = device?.name?.uppercase() ?: return
            if (WAHOO_DEVICE_KEYWORDS.none { name.contains(it) }) return

            when (intent?.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED    -> wahooEventSink?.success("wahoo_connected")
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> wahooEventSink?.success("wahoo_disconnected")
            }
        }
    }

    // ── Flutter engine setup ──────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createCallNotificationChannel()

        // ── Call channel ──────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showCall" -> {
                        val callerName = call.argument<String>("callerName") ?: "Rider Alert"
                        showCall(callerName)
                        result.success(null)
                    }
                    "dismissCall" -> {
                        dismissCall()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Wahoo status channel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAHOO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationListenerEnabled" ->
                        result.success(isNotificationListenerEnabled())
                    "isWahooInstalled" ->
                        result.success(isWahooInstalled())
                    "openNotificationSettings" -> {
                        openNotificationListenerSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Wahoo BT event stream ─────────────────────────────────────────────
        // Fires "wahoo_connected" / "wahoo_disconnected" when a Bluetooth
        // Classic device whose name contains ELEMNT / BOLT / ROAM pairs or
        // disconnects. Flutter side uses this to auto-start the DI2 connection.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WAHOO_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    wahooEventSink = events
                    val filter = IntentFilter().apply {
                        addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
                        addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(btReceiver, filter, Context.RECEIVER_EXPORTED)
                    } else {
                        registerReceiver(btReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    wahooEventSink = null
                    try { unregisterReceiver(btReceiver) } catch (_: Exception) {}
                }
            })
    }

    // ── Show fake incoming call ───────────────────────────────────────────────
    private fun showCall(callerName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            showCallStyleNotification(callerName)
        } else {
            showFallbackNotification(callerName)
        }
    }

    private fun showCallStyleNotification(callerName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return

        val declineIntent = PendingIntent.getBroadcast(
            this, 0,
            Intent(this, DismissCallReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val acceptIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(this, DismissCallReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val caller = Person.Builder().setName(callerName).setImportant(true).build()
        val notification = NotificationCompat.Builder(this, CALL_CH_ID)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle(callerName)
            .setContentText("DI2 Rider Alert")
            .setStyle(
                NotificationCompat.CallStyle.forIncomingCall(caller, declineIntent, acceptIntent)
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(buildFullScreenIntent(), true)
            .setAutoCancel(true)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(CALL_NOTIF_ID, notification)
    }

    private fun showFallbackNotification(callerName: String) {
        val notification = NotificationCompat.Builder(this, CALL_CH_ID)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle(callerName)
            .setContentText("DI2 Rider Alert")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(buildFullScreenIntent(), true)
            .setAutoCancel(true)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(CALL_NOTIF_ID, notification)
    }

    private fun buildFullScreenIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        return PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun dismissCall() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CALL_NOTIF_ID)
    }

    // ── Wahoo companion checks ────────────────────────────────────────────────
    private fun isNotificationListenerEnabled(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return enabledListeners.isNotEmpty()
    }

    private fun isWahooInstalled(): Boolean {
        return WAHOO_PACKAGES.any { pkg ->
            try { packageManager.getPackageInfo(pkg, 0); true }
            catch (_: PackageManager.NameNotFoundException) { false }
        }
    }

    private fun openNotificationListenerSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    // ── Notification channel ──────────────────────────────────────────────────
    private fun createCallNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CALL_CH_ID, "Rider Alerts", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "DI2 hold-button call alerts" }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(ch)
        }
    }
}

