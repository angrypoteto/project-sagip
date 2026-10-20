package ph.sagip.sagip_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid

/**
 * Tier 3 (plan section 11, Q32): an SOS passed between phones over
 * Bluetooth LE advertising. Not Bluetooth SIG Mesh, which apps cannot use:
 * each phone advertises small packets (24 bytes of service data, see
 * packages/shared sos_relay.dart) and scans for them. Every phone in the
 * chain must have the app running.
 *
 * Bluetooth may be off when the app starts or go off later (airplane mode
 * turns it off). Android stops every advert and scan then, so the relay
 * keeps what it was asked to do and starts it again the moment Bluetooth
 * is back (2026-10-20: a phone signed in with Bluetooth off never listened).
 */
class BleRelay(private val context: Context) {
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val adverts = mutableMapOf<String, AdvertiseCallback>()
    private var scan: ScanCallback? = null

    /** Every packet asked for and not stopped, even those Bluetooth was off for. */
    private val packets = mutableMapOf<String, ByteArray>()

    /** Set while the app listens for SOS, even when Bluetooth is off. */
    private var listener: ((ByteArray) -> Unit)? = null

    private val stateChanges = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_ON -> resume()
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                    // Android drops them; start afresh when it is back.
                    adverts.clear()
                    scan = null
                }
            }
        }
    }

    init {
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(stateChanges, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(stateChanges, filter)
        }
    }

    /** Bluetooth came back: listen again, and advertise what is still asked for. */
    private fun resume() {
        listener?.let { startScan(it) }
        for ((key, packet) in packets.toMap()) advertise(key, packet) {}
        if (listener != null) RelayService.start(context)
    }

    /**
     * The app came to the front: start the scan again. Xiaomi's HyperOS
     * refuses a scan from an app it counts as in the background (screen
     * locked) and does not start it later by itself (2026-10-20).
     */
    fun resumeScan() {
        listener?.let { startScan(it) }
    }

    /** True when Bluetooth is on (the phone's question is not needed). */
    fun isEnabled(): Boolean = adapter?.isEnabled == true

    /** 0x5A61 on the Bluetooth base UUID; matches SosRelayPacket.serviceUuid16. */
    private val service = ParcelUuid.fromString("00005a61-0000-1000-8000-00805f9b34fb")

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** Android 12 and up ask for "Nearby devices"; older versions use location for scans. */
    private fun permitted(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            granted(Manifest.permission.BLUETOOTH_ADVERTISE) && granted(Manifest.permission.BLUETOOTH_SCAN)
        } else {
            granted(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    /** The hardware can advertise (whether or not Bluetooth is on right now). */
    fun hasHardware(): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) &&
            adapter?.isMultipleAdvertisementSupported == true

    fun isSupported(): Boolean =
        adapter?.isEnabled == true && adapter?.bluetoothLeAdvertiser != null && permitted()

    /**
     * Advertises [packet] under [key], replacing what was there. Answers
     * once. With Bluetooth off it answers false and advertises it as soon
     * as Bluetooth is on again.
     */
    @SuppressLint("MissingPermission")
    fun advertise(key: String, packet: ByteArray, done: (Boolean) -> Unit) {
        packets[key] = packet
        val advertiser = adapter?.bluetoothLeAdvertiser
        if (!isSupported() || advertiser == null) {
            done(false)
            return
        }
        stopAdvert(key)
        var answered = false
        fun answer(ok: Boolean) {
            if (answered) return
            answered = true
            done(ok)
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceData(service, packet)
            .build()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) = answer(true)
            override fun onStartFailure(errorCode: Int) {
                adverts.remove(key)
                answer(false)
            }
        }
        adverts[key] = callback
        try {
            advertiser.startAdvertising(settings, data, callback)
        } catch (_: SecurityException) {
            adverts.remove(key)
            answer(false)
        } catch (_: IllegalArgumentException) {
            adverts.remove(key)
            answer(false)
        }
    }

    fun stop(key: String) {
        packets.remove(key)
        stopAdvert(key)
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvert(key: String) {
        val callback = adverts.remove(key) ?: return
        try {
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
        } catch (_: Exception) {
            // Bluetooth went off: the advert is gone anyway.
        }
    }

    fun stopAll() {
        for (key in (adverts.keys + packets.keys).toList()) stop(key)
    }

    /** The app is closing: stop everything and stop watching Bluetooth. */
    fun close() {
        stopAll()
        stopListening()
        try {
            context.unregisterReceiver(stateChanges)
        } catch (_: IllegalArgumentException) {
            // Not registered.
        }
    }

    /**
     * Scans for SOS packets; [onPacket] gets each one's 24 bytes. False
     * when Bluetooth is off or not allowed: the scan then starts by itself
     * once Bluetooth is on.
     */
    @SuppressLint("MissingPermission")
    fun startScan(onPacket: (ByteArray) -> Unit): Boolean {
        listener = onPacket
        val scanner = adapter?.bluetoothLeScanner
        if (!isSupported() || scanner == null) return false
        stopScan()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                result.scanRecord?.getServiceData(service)?.let(onPacket)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                for (r in results) r.scanRecord?.getServiceData(service)?.let(onPacket)
            }
        }
        val filter = ScanFilter.Builder().setServiceData(service, ByteArray(0), ByteArray(0)).build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
            .build()
        return try {
            scanner.startScan(listOf(filter), settings, callback)
            scan = callback
            true
        } catch (_: SecurityException) {
            false
        }
    }

    /** The app stopped listening (signed out). */
    fun stopListening() {
        listener = null
        stopScan()
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        val callback = scan ?: return
        scan = null
        try {
            adapter?.bluetoothLeScanner?.stopScan(callback)
        } catch (_: Exception) {
            // Bluetooth went off.
        }
    }
}
