package ph.sagip.sagip_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid

/**
 * Tier 3 (plan section 11, Q32): an SOS passed between phones over
 * Bluetooth LE advertising. Not Bluetooth SIG Mesh, which apps cannot use:
 * each phone advertises small packets (24 bytes of service data, see
 * packages/shared sos_relay.dart) and scans for them. Every phone in the
 * chain must have the app running.
 */
class BleRelay(private val context: Context) {
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val adverts = mutableMapOf<String, AdvertiseCallback>()
    private var scan: ScanCallback? = null

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

    /** Advertises [packet] under [key], replacing what was there. Answers once. */
    @SuppressLint("MissingPermission")
    fun advertise(key: String, packet: ByteArray, done: (Boolean) -> Unit) {
        val advertiser = adapter?.bluetoothLeAdvertiser
        if (!isSupported() || advertiser == null) {
            done(false)
            return
        }
        stop(key)
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

    @SuppressLint("MissingPermission")
    fun stop(key: String) {
        val callback = adverts.remove(key) ?: return
        try {
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(callback)
        } catch (_: Exception) {
            // Bluetooth went off: the advert is gone anyway.
        }
    }

    fun stopAll() {
        for (key in adverts.keys.toList()) stop(key)
    }

    /** Scans for SOS packets; [onPacket] gets each one's 24 bytes. */
    @SuppressLint("MissingPermission")
    fun startScan(onPacket: (ByteArray) -> Unit): Boolean {
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
