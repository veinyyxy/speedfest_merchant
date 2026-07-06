package com.techlong.speedfestmerchant.speedfest_merchant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val newOrdersChannel = NotificationChannel(
            "new_orders",
            "New orders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications for newly paid merchant orders"
            enableVibration(true)
            setShowBadge(true)
        }

        val orderCancelledChannel = NotificationChannel(
            "order_cancelled",
            "Order cancelled",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications for customer-cancelled merchant orders"
            enableVibration(true)
            setShowBadge(true)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(newOrdersChannel)
        notificationManager.createNotificationChannel(orderCancelledChannel)
    }
}
