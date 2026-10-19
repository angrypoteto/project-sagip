package ph.sagip.sagip_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Tier 3 (plan section 11): keeps the phone passing SOS on over Bluetooth
 * while S.A.G.I.P. is in the background, as a foreground service with a
 * quiet notification ("connected device" type). The advertising and
 * scanning themselves stay in [BleRelay]; this only keeps the app's process
 * at foreground priority so Android does not stop them. It ends when the
 * relay stops, at sign-out, or when the app is closed.
 */
class RelayService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                getString(R.string.channel_relay),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = getString(R.string.channel_relay_about) },
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = notice(this, open)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(ID, notification)
            }
        } catch (_: Exception) {
            // Not allowed now (no Bluetooth permission, or Android refused a
            // start from the background): the relay still runs while the app
            // is open.
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "sagip_relay"
        private const val ID = 4211

        // What the notice says (2026-10-19): only what is true. It used to
        // say "listening for SOS nearby" all the time, which read as SOS
        // coming in when none had.
        @Volatile private var carrying = 0
        @Volatile private var sent = 0
        @Volatile private var running = false

        private fun notice(context: Context, open: PendingIntent): Notification {
            val res = context.resources
            val (title, text) = when {
                carrying > 0 -> Pair(
                    res.getQuantityString(R.plurals.relay_carrying_title, carrying, carrying),
                    context.getString(R.string.relay_carrying_text),
                )
                sent > 0 -> Pair(
                    res.getQuantityString(R.plurals.relay_sent_title, sent, sent),
                    context.getString(R.string.relay_idle_text),
                )
                else -> Pair(
                    context.getString(R.string.relay_idle_title),
                    context.getString(R.string.relay_idle_text),
                )
            }
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_sagip)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build()
        }

        /** The relay's counts changed: say so on the notice, if it is up. */
        fun update(context: Context, carrying: Int, sent: Int) {
            this.carrying = carrying
            this.sent = sent
            if (!running) return
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            context.getSystemService(NotificationManager::class.java)
                ?.notify(ID, notice(context, open))
        }

        fun start(context: Context) {
            try {
                context.startForegroundService(Intent(context, RelayService::class.java))
            } catch (_: Exception) {
                // Android refused; the relay runs while the app is open.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RelayService::class.java))
        }
    }
}
