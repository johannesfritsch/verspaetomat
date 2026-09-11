package de.verspaetomat.verspaetomat

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

/** One station region. */
data class Station(val id: String, val name: String, val lat: Double, val lon: Double) {
    fun toJson(): JSONObject = JSONObject().put("id", id).put("name", name).put("lat", lat).put("lon", lon)

    companion object {
        fun from(o: JSONObject) = Station(o.getString("id"), o.getString("name"), o.getDouble("lat"), o.getDouble("lon"))
        fun list(a: JSONArray?): List<Station> = (0 until (a?.length() ?: 0)).map { from(a!!.getJSONObject(it)) }
    }
}

/**
 * Native side of the `de.verspaetomat/geofence` channel (docs/15-geofence.md).
 * Persists the last `configure` call, registers the personal station set plus one
 * umbrella region, and turns dwell transitions into the nudge notification.
 * The only network call is the nearby query on umbrella exit.
 */
object GeofenceManager {
    private const val TAG = "Geofence"
    private const val PREFS = "verspaetomat.geofence"
    const val UMBRELLA_ID = "umbrella"
    const val STATION_PREFIX = "station:"
    private const val MAX_STATIONS = 16
    private const val MAX_NEAREST = 3
    private const val COOLDOWN_MS = 30L * 60 * 1000
    private const val FIX_BUDGET_MS = 10_000L

    /**
     * Set by MainActivity while it is alive: the umbrella was left and the station set
     * re-registered around the new position, so Dart resolves its stations again
     * (docs/24 §0). Null when the exit happened with no Activity, which needs nothing —
     * the monitor refreshes on resume anyway.
     */
    var umbrellaExitListener: (() -> Unit)? = null

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun config(ctx: Context): JSONObject? = prefs(ctx).getString("config", null)?.let { JSONObject(it) }
    private fun nearest(ctx: Context): List<Station> = Station.list(prefs(ctx).getString("nearest", null)?.let { JSONArray(it) })
    fun lastEvent(ctx: Context): String? = prefs(ctx).getString("lastEvent", null)
    private fun setLastEvent(ctx: Context, s: String) = prefs(ctx).edit().putString("lastEvent", s).apply()

    fun registeredCount(ctx: Context): Int = prefs(ctx).getInt("registered", 0)

    /** A nudge tapped while no Dart engine was listening; handed out once via `status`. */
    fun takePendingNudge(ctx: Context): JSONObject? {
        val s = prefs(ctx).getString("pendingNudge", null) ?: return null
        prefs(ctx).edit().remove("pendingNudge").apply()
        return JSONObject(s)
    }

    fun setPendingNudge(ctx: Context, stationId: String, stationName: String) =
        prefs(ctx).edit().putString("pendingNudge", JSONObject().put("stationId", stationId).put("stationName", stationName).toString()).apply()

    fun hasBackgroundPermission(ctx: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) return false
        if (Build.VERSION.SDK_INT < 29) return true
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    fun permissionString(ctx: Context): String {
        val fine = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) return if (prefs(ctx).getBoolean("asked", false)) "denied" else "notDetermined"
        return if (hasBackgroundPermission(ctx)) "always" else "whileInUse"
    }

    fun markAsked(ctx: Context) = prefs(ctx).edit().putBoolean("asked", true).apply()

    /** Store the config from Dart and (re)register. Calls back with the number of regions registered. */
    fun configure(ctx: Context, config: JSONObject, done: (Int) -> Unit) {
        prefs(ctx).edit().putString("config", config.toString()).apply()
        reregister(ctx, done)
    }

    fun stop(ctx: Context, done: () -> Unit) {
        prefs(ctx).edit().remove("config").remove("nearest").putInt("registered", 0).apply()
        client(ctx).removeGeofences(pendingIntent(ctx)).addOnCompleteListener { done() }
    }

    /** Drop everything, then register stations + nearest + umbrella around the current position. */
    fun reregister(ctx: Context, done: (Int) -> Unit) {
        val cfg = config(ctx)
        val enabled = cfg?.optBoolean("enabled", false) ?: false
        client(ctx).removeGeofences(pendingIntent(ctx)).addOnCompleteListener {
            if (cfg == null || !enabled || !hasBackgroundPermission(ctx)) {
                prefs(ctx).edit().putInt("registered", 0).apply()
                done(0)
                return@addOnCompleteListener
            }
            currentLocation(ctx) { fix -> addAll(ctx, cfg, fix, done) }
        }
    }

    @SuppressLint("MissingPermission")
    private fun addAll(ctx: Context, cfg: JSONObject, fix: Location?, done: (Int) -> Unit) {
        val stations = Station.list(cfg.optJSONArray("stations")).take(MAX_STATIONS)
        val ids = stations.map { it.id }.toMutableSet()
        val extra = nearest(ctx).filter { ids.add(it.id) }.take(MAX_NEAREST)
        val radius = cfg.optDouble("stationRadiusM", 300.0).toFloat()
        val umbrellaRadius = cfg.optDouble("umbrellaRadiusM", 8000.0).toFloat()
        val fences = ArrayList<Geofence>()
        for (s in stations + extra) {
            fences.add(
                Geofence.Builder()
                    .setRequestId(STATION_PREFIX + s.id)
                    .setCircularRegion(s.lat, s.lon, radius)
                    .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_DWELL)
                    .setLoiteringDelay(60_000)
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .build()
            )
        }
        if (fix != null) {
            fences.add(
                Geofence.Builder()
                    .setRequestId(UMBRELLA_ID)
                    .setCircularRegion(fix.latitude, fix.longitude, umbrellaRadius)
                    .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_EXIT)
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .build()
            )
        }
        if (fences.isEmpty()) {
            prefs(ctx).edit().putInt("registered", 0).apply()
            done(0)
            return
        }
        val request = GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_DWELL).addGeofences(fences).build()
        client(ctx).addGeofences(request, pendingIntent(ctx))
            .addOnSuccessListener {
                prefs(ctx).edit().putInt("registered", fences.size).apply()
                setLastEvent(ctx, "registered ${fences.size}")
                done(fences.size)
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "addGeofences failed", e)
                prefs(ctx).edit().putInt("registered", 0).apply()
                setLastEvent(ctx, "register failed: ${e.message}")
                done(0)
            }
    }

    // ---- transitions -----------------------------------------------------

    /** A station dwell: confirm with one fix, then the rules, then the notification. */
    fun onStationDwell(ctx: Context, stationId: String, done: () -> Unit) {
        val cfg = config(ctx)
        val station = (Station.list(cfg?.optJSONArray("stations")) + nearest(ctx)).firstOrNull { it.id == stationId }
        if (cfg == null || station == null || !cfg.optBoolean("enabled", false)) return done()
        setLastEvent(ctx, "dwell ${station.name}")
        val radius = cfg.optDouble("stationRadiusM", 300.0).toFloat()
        currentLocation(ctx) { fix ->
            val there = fix == null || fix.accuracy > 200f || distance(fix, station) <= radius
            if (there) nudgeIfAllowed(ctx, cfg, station)
            done()
        }
    }

    private fun nudgeIfAllowed(ctx: Context, cfg: JSONObject, station: Station) {
        if (cfg.optBoolean("riding", false)) return setLastEvent(ctx, "skip riding")
        if (inQuietHours(cfg.optString("quietFrom", ""), cfg.optString("quietTo", ""))) return setLastEvent(ctx, "skip quiet")
        val key = "cooldown:" + station.id
        val last = prefs(ctx).getLong(key, 0)
        val now = System.currentTimeMillis()
        if (now - last < COOLDOWN_MS) return setLastEvent(ctx, "skip cooldown ${station.name}")
        prefs(ctx).edit().putLong(key, now).apply()
        NudgeNotification.show(ctx, station)
        setLastEvent(ctx, "nudge ${station.name}")
    }

    /** Left the umbrella: one fix, nearest stations from the API, re-register around the new position. */
    fun onUmbrellaExit(ctx: Context, done: () -> Unit) {
        val cfg = config(ctx) ?: return done()
        setLastEvent(ctx, "umbrella exit")
        currentLocation(ctx) { fix ->
            if (fix == null) return@currentLocation done()
            Thread {
                val fetched = fetchNearby(cfg.optString("apiUrl"), cfg.optString("token"), fix.latitude, fix.longitude)
                if (fetched != null) {
                    prefs(ctx).edit().putString("nearest", JSONArray(fetched.map { it.toJson() }).toString()).apply()
                }
                Handler(Looper.getMainLooper()).post {
                    client(ctx).removeGeofences(pendingIntent(ctx)).addOnCompleteListener {
                        val finish = { umbrellaExitListener?.invoke(); done() }
                        if (hasBackgroundPermission(ctx) && cfg.optBoolean("enabled", false)) addAll(ctx, cfg, fix) { finish() } else finish()
                    }
                }
            }.start()
        }
    }

    private fun fetchNearby(apiUrl: String, token: String, lat: Double, lon: Double): List<Station>? {
        if (apiUrl.isEmpty()) return null
        return try {
            val url = URL("${apiUrl.trimEnd('/')}/v1/stations/nearby?lat=$lat&lon=$lon")
            val c = url.openConnection() as HttpURLConnection
            c.connectTimeout = FIX_BUDGET_MS.toInt()
            c.readTimeout = FIX_BUDGET_MS.toInt()
            if (token.isNotEmpty()) c.setRequestProperty("Authorization", "Bearer $token")
            val body = c.inputStream.bufferedReader().use(BufferedReader::readText)
            c.disconnect()
            val arr = JSONObject(body).optJSONArray("stations") ?: return null
            (0 until arr.length()).map { arr.getJSONObject(it) }
                .sortedBy { it.optInt("distance_m", Int.MAX_VALUE) }
                .take(MAX_NEAREST)
                .map { Station.from(it) }
        } catch (e: Exception) {
            Log.w(TAG, "nearby failed", e)
            null
        }
    }

    // ---- helpers -----------------------------------------------------------

    private fun client(ctx: Context): GeofencingClient = LocationServices.getGeofencingClient(ctx)

    private fun pendingIntent(ctx: Context): PendingIntent {
        val intent = Intent(ctx, GeofenceReceiver::class.java).setAction(GeofenceReceiver.ACTION)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(ctx, 0, intent, flags)
    }

    /** One balanced-power fix within [FIX_BUDGET_MS]; null when none arrives or permission is missing. */
    @SuppressLint("MissingPermission")
    fun currentLocation(ctx: Context, cb: (Location?) -> Unit) {
        val fineOrCoarse = ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fineOrCoarse) return cb(null)
        val cts = CancellationTokenSource()
        var answered = false
        val handler = Handler(Looper.getMainLooper())
        val timeout = Runnable { if (!answered) { answered = true; cts.cancel(); cb(null) } }
        handler.postDelayed(timeout, FIX_BUDGET_MS)
        LocationServices.getFusedLocationProviderClient(ctx)
            .getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cts.token)
            .addOnCompleteListener { t ->
                if (answered) return@addOnCompleteListener
                answered = true
                handler.removeCallbacks(timeout)
                cb(if (t.isSuccessful) t.result else null)
            }
    }

    private fun distance(fix: Location, s: Station): Float {
        val out = FloatArray(1)
        Location.distanceBetween(fix.latitude, fix.longitude, s.lat, s.lon, out)
        return out[0]
    }

    /** "22:00".."06:00" in local time; the window may cross midnight. Empty strings mean no quiet hours. */
    fun inQuietHours(from: String, to: String, now: Calendar = Calendar.getInstance()): Boolean {
        val f = minutes(from) ?: return false
        val t = minutes(to) ?: return false
        val n = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return if (f <= t) n in f until t else n >= f || n < t
    }

    private fun minutes(hhmm: String): Int? {
        val p = hhmm.split(":")
        if (p.size != 2) return null
        val h = p[0].toIntOrNull() ?: return null
        val m = p[1].toIntOrNull() ?: return null
        return h * 60 + m
    }
}
