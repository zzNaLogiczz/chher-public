package com.chhreader.chh_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

internal class MotionBridge(
    context: Context,
    engine: FlutterEngine,
    private val displayRotation: () -> Int,
) : EventChannel.StreamHandler, SensorEventListener {
    private val channel = EventChannel(engine.dartExecutor.binaryMessenger, "chh/motion")
    private val manager = context.getSystemService(SensorManager::class.java)
    private var sink: EventChannel.EventSink? = null
    private var gx = 0.0
    private var gy = 0.0
    private var gz = 0.0

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val sensors = manager ?: return
        val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        if (!sensors.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)) return
        sink = events
        sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let {
            sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    override fun onCancel(arguments: Any?) {
        manager?.unregisterListener(this)
        sink = null
        gx = 0.0
        gy = 0.0
        gz = 0.0
    }

    override fun onSensorChanged(event: SensorEvent) {
        val events = sink ?: return
        val values = event.values
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                gx = values[0].toDouble()
                gy = values[1].toDouble()
                gz = values[2].toDouble()
            }
            Sensor.TYPE_ACCELEROMETER -> events.success(
                mapOf(
                    "ax" to values[0].toDouble(),
                    "ay" to values[1].toDouble(),
                    "az" to values[2].toDouble(),
                    "gx" to gx,
                    "gy" to gy,
                    "gz" to gz,
                    "rotation" to displayRotation(),
                ),
            )
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) = Unit

    fun dispose() {
        onCancel(null)
        channel.setStreamHandler(null)
    }
}
