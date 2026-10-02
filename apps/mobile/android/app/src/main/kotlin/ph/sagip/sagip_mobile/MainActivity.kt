package ph.sagip.sagip_mobile

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Hosts the Flutter app and the Tier 2 SMS channel (plan section 11): an
 * SOS texted to the MDRRMD gateway SIM when the phone has signal but no
 * data. The app is installed directly, not from Google Play, so it may hold
 * SEND_SMS (plan Q29). It also creates the notification categories for
 * push (plan part 7).
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    /**
     * The notification categories push messages name (supabase/functions/
     * send-alerts/fcm.ts). All three can sound and pop up: each is about an
     * emergency. Creating them again changes nothing the person set.
     */
    private fun createNotificationChannels() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        fun channel(id: String, name: Int, about: Int) =
            NotificationChannel(id, getString(name), NotificationManager.IMPORTANCE_HIGH)
                .apply { description = getString(about) }
        manager.createNotificationChannels(
            listOf(
                channel("sagip_alerts", R.string.channel_alerts, R.string.channel_alerts_about),
                channel("sagip_rescue", R.string.channel_rescue, R.string.channel_rescue_about),
                channel(
                    "sagip_assignments",
                    R.string.channel_assignments,
                    R.string.channel_assignments_about,
                ),
            ),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ph.sagip/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canSend" -> result.success(canSend())
                    "send" -> {
                        val number = call.argument<String>("number")
                        val text = call.argument<String>("text")
                        if (number == null || text == null) {
                            result.success(false)
                        } else {
                            send(number, text) { ok -> result.success(ok) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canSend(): Boolean =
        packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING) &&
            checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    /**
     * Sends one text and reports whether the phone's SMS service sent it
     * (the "sent" broadcast), or false after 40 seconds without an answer.
     */
    private fun send(number: String, text: String, done: (Boolean) -> Unit) {
        if (!canSend()) {
            done(false)
            return
        }
        val answered = AtomicBoolean(false)
        val action = "ph.sagip.SMS_SENT.${System.nanoTime()}"
        val handler = Handler(Looper.getMainLooper())
        lateinit var receiver: BroadcastReceiver
        fun finish(ok: Boolean) {
            if (!answered.compareAndSet(false, true)) return
            handler.removeCallbacksAndMessages(action)
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // Already unregistered.
            }
            done(ok)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                finish(resultCode == Activity.RESULT_OK)
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        handler.postAtTime({ finish(false) }, action, android.os.SystemClock.uptimeMillis() + 40_000)

        val sent = PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            Intent(action).setPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT,
        )
        try {
            val sms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            sms.sendTextMessage(number, null, text, sent, null)
        } catch (_: Exception) {
            finish(false)
        }
    }
}
