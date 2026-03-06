package com.bell.bell

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Receives the "Decline" or "Accept" button tap from the CallStyle notification
/// and cancels it — we don't need a real phone call, just the Wahoo display.
class DismissCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(MainActivity.CALL_NOTIF_ID)
    }
}
