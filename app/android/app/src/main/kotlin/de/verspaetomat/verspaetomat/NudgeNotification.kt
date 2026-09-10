package de.verspaetomat.verspaetomat

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** The "Am Köln Hbf?" notification. Tapping opens MainActivity with the station in the extras. */
object NudgeNotification {
    const val CHANNEL = "nudge"
    const val EXTRA_STATION_ID = "nudge.stationId"
    const val EXTRA_STATION_NAME = "nudge.stationName"
    private const val NOTIFICATION_ID = 4711

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL) != null) return
        val ch = NotificationChannel(CHANNEL, "Hinweis am Bahnhof", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Wenn du ein paar Minuten an einem Bahnhof stehst."
        }
        nm.createNotificationChannel(ch)
    }

    fun allowed(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun show(ctx: Context, station: Station) {
        if (!allowed(ctx)) return
        ensureChannel(ctx)
        val open = Intent(ctx, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_STATION_ID, station.id)
            .putExtra(EXTRA_STATION_NAME, station.name)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val tap = PendingIntent.getActivity(ctx, station.id.hashCode(), open, flags)
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle("Am ${station.name}?")
            .setContentText("Einchecken, bevor der Zug kommt.")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, n)
    }
}
