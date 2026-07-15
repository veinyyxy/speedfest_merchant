package com.techlong.speedfeast.merchant

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val localNotificationsChannel = "speedfeast_merchant/local_notifications"
    private var localNotificationMethodChannel: MethodChannel? = null
    private var pendingNotificationTapPayload: Map<String, String>? = null
    private var starPrinterChannel: StarPrinterChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingNotificationTapPayload =
            readNotificationTapPayload(intent) ?: pendingNotificationTapPayload

        starPrinterChannel = StarPrinterChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger
        ).also { it.register() }

        localNotificationMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            localNotificationsChannel
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "showMerchantNotification" -> {
                        val arguments = call.arguments as? Map<*, *>
                        if (arguments == null) {
                            result.error(
                                "invalid_arguments",
                                "Notification arguments are required.",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        result.success(showMerchantLocalNotification(arguments))
                    }
                    "consumeInitialNotificationTap" -> {
                        val payload = pendingNotificationTapPayload
                        pendingNotificationTapPayload = null
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        starPrinterChannel?.dispose()
        starPrinterChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = readNotificationTapPayload(intent) ?: return
        pendingNotificationTapPayload = payload
        localNotificationMethodChannel?.invokeMethod("notificationTap", payload)
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

    private fun showMerchantLocalNotification(arguments: Map<*, *>): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val channelId = readArgument(arguments, "channelId").ifBlank { "new_orders" }
        val notificationId = readArgument(arguments, "notificationId")
        val eventType = readArgument(arguments, "eventType")
        val orderId = readArgument(arguments, "orderId")
        val title = readArgument(arguments, "title").ifBlank { "SpeedFeast Merchant" }
        val body = readArgument(arguments, "body")
        val notificationManager = getSystemService(NotificationManager::class.java)

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            action = "speedfeast_merchant.LOCAL_NOTIFICATION_TAP"
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("merchant_local_notification_tap", true)
            putExtra("notification_id", notificationId)
            putExtra("event_type", eventType)
            putExtra("order_id", orderId)
        }
        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        )
        val contentIntent = PendingIntent.getActivity(
            this,
            notificationKey(notificationId, orderId),
            tapIntent,
            pendingIntentFlags
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
                .setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
                .setPriority(Notification.PRIORITY_HIGH)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
        }

        notificationManager.notify(notificationKey(notificationId, orderId), builder.build())
        return true
    }

    private fun readNotificationTapPayload(intent: Intent?): Map<String, String>? {
        if (intent?.getBooleanExtra("merchant_local_notification_tap", false) != true) {
            return null
        }

        return mapOf(
            "notificationId" to (intent.getStringExtra("notification_id") ?: ""),
            "eventType" to (intent.getStringExtra("event_type") ?: ""),
            "orderId" to (intent.getStringExtra("order_id") ?: "")
        )
    }

    private fun readArgument(arguments: Map<*, *>, key: String): String {
        return arguments[key]?.toString()?.trim() ?: ""
    }

    private fun notificationKey(notificationId: String, orderId: String): Int {
        val source = notificationId.ifBlank { orderId }.ifBlank {
            System.currentTimeMillis().toString()
        }
        return source.hashCode()
    }
}
