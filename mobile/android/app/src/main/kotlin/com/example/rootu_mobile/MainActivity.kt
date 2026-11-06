package com.example.rootu_mobile

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Surface
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Granularity
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.rootu_mobile/gps_hardware"
    private val EVENT_CHANNEL = "com.example.rootu_mobile/gps_stream"

    // Location management
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var locationManager: LocationManager? = null
    private var gpsListener: LocationListener? = null
    private var latestLocation: Location? = null

    // Sensor & heading management
    private var sensorManager: SensorManager? = null
    private var rotationVectorSensor: Sensor? = null
    private var sensorEventListener: SensorEventListener? = null
    private var latestCompassHeading: Double = -1.0
    private var lastSensorEmitTimeMs: Long = 0L
    private var lastEmittedHeading: Double = -1.0

    // Flutter EventChannel sink & UI Handler
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Alarm & audio management
    private var alarmRingtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize system services
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        // Find primary rotation sensor with geomagnetic fallback
        rotationVectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)

        // Setup MethodChannel handler
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRawGpsLocation" -> {
                    val loc = latestLocation ?: getRawGpsFix()
                    if (loc != null) {
                        result.success(locationToMap(loc))
                    } else {
                        result.success(null)
                    }
                }
                "isGpsHardwareAvailable" -> {
                    val isGmsAvailable = isGooglePlayServicesAvailable()
                    val hasGpsProvider = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true
                    result.success(isGmsAvailable || hasGpsProvider)
                }
                "startGpsStream" -> {
                    startLocationUpdates()
                    startSensorUpdates()
                    result.success(true)
                }
                "stopGpsStream" -> {
                    stopLocationUpdates()
                    stopSensorUpdates()
                    result.success(true)
                }
                "startAlarmTone" -> {
                    startAlarm()
                    result.success(true)
                }
                "stopAlarmTone" -> {
                    stopAlarm()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Setup EventChannel handler
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                @SuppressLint("MissingPermission")
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startLocationUpdates()
                    startSensorUpdates()
                }

                override fun onCancel(arguments: Any?) {
                    stopLocationUpdates()
                    stopSensorUpdates()
                    eventSink = null
                }
            }
        )
    }

    private fun isGooglePlayServicesAvailable(): Boolean {
        return try {
            val availability = GoogleApiAvailability.getInstance()
            availability.isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS
        } catch (_: Exception) {
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun emitCachedLocationIfAvailable() {
        latestLocation?.let {
            emitLocation(it)
            return
        }

        if (isGooglePlayServicesAvailable()) {
            try {
                fusedLocationClient?.lastLocation?.addOnSuccessListener { loc ->
                    if (loc != null && latestLocation == null) {
                        latestLocation = loc
                        emitLocation(loc)
                    }
                }
            } catch (_: SecurityException) {}
        } else {
            val lm = locationManager ?: return
            try {
                val cached = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                    ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                if (cached != null && latestLocation == null) {
                    latestLocation = cached
                    emitLocation(cached)
                }
            } catch (_: SecurityException) {}
        }
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        stopLocationUpdates()
        emitCachedLocationIfAvailable()

        if (isGooglePlayServicesAvailable()) {
            try {
                val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
                    .setMinUpdateIntervalMillis(500L)
                    .setMinUpdateDistanceMeters(0f)
                    .setGranularity(Granularity.GRANULARITY_FINE)
                    .setWaitForAccurateLocation(false)
                    .build()

                locationCallback = object : LocationCallback() {
                    override fun onLocationResult(locationResult: LocationResult) {
                        for (location in locationResult.locations) {
                            location?.let {
                                latestLocation = it
                                emitLocation(it)
                            }
                        }
                    }
                }

                fusedLocationClient?.requestLocationUpdates(
                    locationRequest,
                    locationCallback!!,
                    Looper.getMainLooper()
                )?.addOnFailureListener {
                    // Fallback to LocationManager if FLP request fails
                    stopLocationUpdates()
                    startLegacyLocationUpdates()
                }
            } catch (e: Exception) {
                startLegacyLocationUpdates()
            }
        } else {
            startLegacyLocationUpdates()
        }
    }

    @SuppressLint("MissingPermission")
    private fun startLegacyLocationUpdates() {
        val lm = locationManager ?: return
        try {
            if (gpsListener == null) {
                gpsListener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        latestLocation = location
                        emitLocation(location)
                    }
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                }
            }

            var providerRegistered = false
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    1000L,
                    0f,
                    gpsListener!!,
                    Looper.getMainLooper()
                )
                providerRegistered = true
            }
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    1000L,
                    0f,
                    gpsListener!!,
                    Looper.getMainLooper()
                )
                providerRegistered = true
            }

            if (!providerRegistered) {
                mainHandler.post {
                    eventSink?.error(
                        "NO_LOCATION_PROVIDER",
                        "Neither GPS nor Network provider is enabled on this device.",
                        null
                    )
                }
            }
        } catch (e: Exception) {
            mainHandler.post {
                eventSink?.error("LEGACY_GPS_ERROR", e.message, null)
            }
        }
    }

    private fun stopLocationUpdates() {
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
            locationCallback = null
        }
        gpsListener?.let {
            locationManager?.removeUpdates(it)
            gpsListener = null
        }
    }

    private fun startSensorUpdates() {
        if (sensorEventListener != null) return
        val sm = sensorManager ?: return
        val sensor = rotationVectorSensor ?: return

        val rotationMatrix = FloatArray(9)
        val remappedMatrix = FloatArray(9)
        val orientation = FloatArray(3)

        sensorEventListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent?) {
                if (event == null) return
                if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR ||
                    event.sensor.type == Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) {

                    SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

                    // Compensate for screen orientation
                    val displayRotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        display?.rotation ?: Surface.ROTATION_0
                    } else {
                        @Suppress("DEPRECATION")
                        windowManager.defaultDisplay.rotation
                    }

                    when (displayRotation) {
                        Surface.ROTATION_90 ->
                            SensorManager.remapCoordinateSystem(
                                rotationMatrix,
                                SensorManager.AXIS_Y,
                                SensorManager.AXIS_MINUS_X,
                                remappedMatrix
                            )
                        Surface.ROTATION_180 ->
                            SensorManager.remapCoordinateSystem(
                                rotationMatrix,
                                SensorManager.AXIS_MINUS_X,
                                SensorManager.AXIS_MINUS_Y,
                                remappedMatrix
                            )
                        Surface.ROTATION_270 ->
                            SensorManager.remapCoordinateSystem(
                                rotationMatrix,
                                SensorManager.AXIS_MINUS_Y,
                                SensorManager.AXIS_X,
                                remappedMatrix
                            )
                        else ->
                            System.arraycopy(rotationMatrix, 0, remappedMatrix, 0, 9)
                    }

                    SensorManager.getOrientation(remappedMatrix, orientation)
                    val degrees = (Math.toDegrees(orientation[0].toDouble()) + 360.0) % 360.0
                    latestCompassHeading = degrees

                    // Throttle sensor-driven updates: max 20Hz (50ms interval) and >= 1.0 degree change
                    val now = System.currentTimeMillis()
                    val delta = headingDelta(degrees, lastEmittedHeading)
                    if (now - lastSensorEmitTimeMs >= 50L && (lastEmittedHeading < 0.0 || delta >= 1.0)) {
                        lastSensorEmitTimeMs = now
                        lastEmittedHeading = degrees
                        latestLocation?.let { loc ->
                            emitLocation(loc)
                        }
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }

        sm.registerListener(
            sensorEventListener,
            sensor,
            SensorManager.SENSOR_DELAY_UI,
            mainHandler
        )
    }

    private fun stopSensorUpdates() {
        sensorEventListener?.let {
            sensorManager?.unregisterListener(it)
            sensorEventListener = null
        }
    }

    private fun headingDelta(h1: Double, h2: Double): Double {
        val diff = Math.abs(h1 - h2) % 360.0
        return if (diff > 180.0) 360.0 - diff else diff
    }

    private fun emitLocation(loc: Location) {
        val map = locationToMap(loc)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            eventSink?.success(map)
        } else {
            mainHandler.post { eventSink?.success(map) }
        }
    }

    @SuppressLint("MissingPermission")
    private fun getRawGpsFix(): Location? {
        latestLocation?.let { return it }
        val lm = locationManager ?: return null
        return try {
            lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        } catch (_: Exception) {
            null
        }
    }

    private fun locationToMap(loc: Location): Map<String, Any> {
        val isMockLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            loc.isMock
        } else {
            @Suppress("DEPRECATION")
            loc.isFromMockProvider
        }

        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "accuracy" to loc.accuracy.toDouble(),
            "altitude" to loc.altitude,
            "speed" to loc.speed.toDouble(),
            "bearing" to loc.bearing.toDouble(),
            "compassHeading" to latestCompassHeading,
            "time" to loc.time,
            "isMock" to isMockLocation
        )
    }

    private fun startAlarm() {
        try {
            if (alarmRingtone == null) {
                val alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                alarmRingtone = RingtoneManager.getRingtone(applicationContext, alertUri)
            }
            alarmRingtone?.play()

            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (_: Exception) {}
    }

    private fun stopAlarm() {
        try {
            alarmRingtone?.stop()
            alarmRingtone = null
            vibrator?.cancel()
            vibrator = null
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopLocationUpdates()
        stopSensorUpdates()
        stopAlarm()
        super.onDestroy()
    }
}
