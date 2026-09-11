package de.verspaetomat.verspaetomat

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "de.verspaetomat/geofence"
        private const val REQ_FINE = 41
        private const val REQ_BACKGROUND = 42
        private const val REQ_NOTIFICATIONS = 43
    }

    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private var wantAlways = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NudgeNotification.ensureChannel(this)
        handleNudgeIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNudgeIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeofenceManager.umbrellaExitListener = { channel?.invokeMethod("umbrellaExit", null) }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "configure" -> {
                        val cfg = toJson(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                        GeofenceManager.configure(this, cfg) { n -> result.success(mapOf("registered" to n)) }
                    }
                    "requestPermission" -> {
                        val always = (call.arguments as? Map<*, *>)?.get("always") as? Boolean ?: true
                        requestPermission(always, result)
                    }
                    "status" -> result.success(status())
                    "clearIgnored" -> {
                        GeofenceManager.clearIgnored(this, call.argument<String>("stationId") ?: "")
                        result.success(null)
                    }
                    "stop" -> GeofenceManager.stop(this) { result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        GeofenceManager.umbrellaExitListener = null
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    private fun status(): Map<String, Any?> {
        val m = HashMap<String, Any?>()
        m["permission"] = GeofenceManager.permissionString(this)
        m["notifications"] = NudgeNotification.allowed(this)
        m["registered"] = GeofenceManager.registeredCount(this)
        m["lastEvent"] = GeofenceManager.lastEvent(this)
        m["ignored"] = GeofenceManager.ignoredTally(this)
        GeofenceManager.takePendingNudge(this)?.let {
            m["pendingNudge"] = mapOf("stationId" to it.optString("stationId"), "stationName" to it.optString("stationName"))
        }
        return m
    }

    // ---- notification tap -------------------------------------------------

    private fun handleNudgeIntent(intent: Intent?) {
        // "3 Stunden Ruhe" from the notification's action (docs/24 §3): no screen opens.
        val snooze = intent?.getIntExtra(NudgeNotification.EXTRA_SNOOZE_HOURS, 0) ?: 0
        if (snooze > 0) {
            intent?.removeExtra(NudgeNotification.EXTRA_SNOOZE_HOURS)
            channel?.invokeMethod("nudgeTapped", mapOf("kind" to "snooze", "hours" to snooze.toString()))
            return
        }
        val id = intent?.getStringExtra(NudgeNotification.EXTRA_STATION_ID) ?: return
        val name = intent.getStringExtra(NudgeNotification.EXTRA_STATION_NAME) ?: ""
        intent.removeExtra(NudgeNotification.EXTRA_STATION_ID)
        val ch = channel
        if (ch != null) {
            GeofenceManager.clearIgnored(this, id) // acted on, so never ignored (docs/25 §4)
            ch.invokeMethod("nudgeTapped", mapOf("stationId" to id, "stationName" to name))
        } else {
            GeofenceManager.setPendingNudge(this, id, name)
        }
    }

    // ---- permissions: fine → background (29+) → notifications (33+) ---------

    private fun requestPermission(always: Boolean, result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("busy", "a permission request is already running", null)
            return
        }
        permissionResult = result
        wantAlways = always
        GeofenceManager.markAsked(this)
        val fine = ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (fine) onFineDone() else ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), REQ_FINE
        )
    }

    private fun onFineDone() {
        val hasAny = GeofenceManager.permissionString(this) != "denied"
        if (!hasAny) return finishPermission()
        if (wantAlways && Build.VERSION.SDK_INT >= 29 && !GeofenceManager.hasBackgroundPermission(this)) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQ_BACKGROUND)
        } else onBackgroundDone()
    }

    private fun onBackgroundDone() {
        if (Build.VERSION.SDK_INT >= 33 && !NudgeNotification.allowed(this)) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
        } else finishPermission()
    }

    private fun finishPermission() {
        val r = permissionResult ?: return
        permissionResult = null
        r.success(GeofenceManager.permissionString(this))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQ_FINE -> onFineDone()
            REQ_BACKGROUND -> onBackgroundDone()
            REQ_NOTIFICATIONS -> finishPermission()
        }
    }

    // ---- helpers ------------------------------------------------------------

    private fun toJson(m: Map<*, *>): JSONObject {
        val o = JSONObject()
        for ((k, v) in m) o.put(k.toString(), toJsonValue(v))
        return o
    }

    private fun toJsonValue(v: Any?): Any? = when (v) {
        null -> JSONObject.NULL
        is Map<*, *> -> toJson(v)
        is List<*> -> JSONArray().also { a -> v.forEach { a.put(toJsonValue(it)) } }
        else -> v
    }
}
