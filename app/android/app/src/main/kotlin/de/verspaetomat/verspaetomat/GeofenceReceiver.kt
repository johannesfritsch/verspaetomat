package de.verspaetomat.verspaetomat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/** Receives geofence transitions from Play services, also with the app closed. */
class GeofenceReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "de.verspaetomat.verspaetomat.GEOFENCE"
        private const val TAG = "GeofenceReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            Log.w(TAG, "geofence error ${event.errorCode}")
            return
        }
        val transition = event.geofenceTransition
        val ids = event.triggeringGeofences?.map(Geofence::getRequestId) ?: return
        val pending = goAsync()
        var open = 0
        val finish = { if (--open == 0) pending.finish() }

        for (id in ids) {
            when {
                id == GeofenceManager.UMBRELLA_ID && transition == Geofence.GEOFENCE_TRANSITION_EXIT -> {
                    open++
                    GeofenceManager.onUmbrellaExit(context, finish)
                }
                id.startsWith(GeofenceManager.STATION_PREFIX) && transition == Geofence.GEOFENCE_TRANSITION_DWELL -> {
                    open++
                    GeofenceManager.onStationDwell(context, id.removePrefix(GeofenceManager.STATION_PREFIX), finish)
                }
                // ENTER is registered so the platform starts the loitering timer; nothing to do yet.
            }
        }
        if (open == 0) pending.finish()
    }
}

/** After a reboot Android forgets geofences; re-register from the persisted config. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (GeofenceManager.config(context) == null) return
        val pending = goAsync()
        GeofenceManager.reregister(context) { pending.finish() }
    }
}
