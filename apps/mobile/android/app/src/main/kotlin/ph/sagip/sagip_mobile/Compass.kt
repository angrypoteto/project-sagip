package ph.sagip.sagip_mobile

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/**
 * Which way the phone is facing, in degrees from north (2026-10-19: the
 * "your location" marker points where the person is looking). Read from
 * Android's rotation sensor only while a map listens; a phone without one
 * sends nothing and the marker stays a plain dot.
 */
class Compass(private val activity: Activity) : EventChannel.StreamHandler {
    private val sensors get() = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private var listener: SensorEventListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val manager = sensors
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (manager == null || sensor == null) {
            events.endOfStream()
            return
        }
        val rotation = FloatArray(9)
        val remapped = FloatArray(9)
        val orientation = FloatArray(3)
        var last = -1000.0
        var lastAt = 0L
        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                // The screen may be turned; north is measured from its top.
                val (x, y) = when (displayRotation()) {
                    Surface.ROTATION_90 -> Pair(SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X)
                    Surface.ROTATION_180 -> Pair(SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y)
                    Surface.ROTATION_270 -> Pair(SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X)
                    else -> Pair(SensorManager.AXIS_X, SensorManager.AXIS_Y)
                }
                SensorManager.remapCoordinateSystem(rotation, x, y, remapped)
                SensorManager.getOrientation(remapped, orientation)
                val degrees = (Math.toDegrees(orientation[0].toDouble()) + 360.0) % 360.0
                val now = System.currentTimeMillis()
                // A few updates a second, and only on a real turn.
                var turn = Math.abs(degrees - last)
                if (turn > 180) turn = 360 - turn
                if (turn < 2.0 || now - lastAt < 100) return
                last = degrees
                lastAt = now
                events.success(degrees)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { sensors?.unregisterListener(it) }
        listener = null
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            activity.windowManager.defaultDisplay.rotation
        }
}
