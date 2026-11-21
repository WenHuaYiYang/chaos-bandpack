package com.chaos.chaos_bandpack

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ChaosConnect 的标准经典蓝牙 SPP 载波。
 *
 * 设备侧(Chaos-Module supervisor/bridge/android_radio.inc)注册的是**私有 UUID**
 * 43434e31-0001-4a10-8000-4348414f5301、服务通道 19、最多 1 条连接;Android 侧按
 * 文档用公开的 createRfcommSocketToServiceRecord(UUID) 连接,由系统完成配对与安全连接,
 * 不反射隐藏的 classic L2CAP API。
 *
 * 这一层只管字节:把 socket 读到的裸流原样抛给 Dart,Dart 侧 FrameLink 负责切
 * “u32LE 长度 + WearPacket”的流帧。所以这里不做任何协议解析,也不解析分片。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.chaos.chaos_bandpack/spp"
        private const val PERM_CODE = 0x5350
        private const val READ_CHUNK = 4096
    }

    private var channel: MethodChannel? = null
    private var socket: BluetoothSocket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null
    private val open = AtomicBoolean(false)
    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermissions: MethodChannel.Result? = null

    private val adapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "adapter" -> result.success(adapterState())
                "permissions" -> requestBluetoothPermissions(result)
                "bonded" -> result.success(bondedDevices())
                "discover" -> discover(
                    call.argument<Int>("timeoutMs") ?: 12000,
                    result,
                )
                "pair" -> pair(call.argument<String>("address").orEmpty(), result)
                "connect" -> connect(
                    call.argument<String>("address").orEmpty(),
                    call.argument<String>("uuid").orEmpty(),
                    result,
                )
                "send" -> send(call.argument<ByteArray>("bytes"), result)
                "close" -> { closeSilently(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun adapterState(): String {
        val a = adapter ?: return "unsupported"
        if (!a.isEnabled) return "off"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            return "unauthorized"
        }
        return "on"
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(true)
            return
        }
        // 搜索附近设备要 BLUETOOTH_SCAN, 连设备要 BLUETOOTH_CONNECT —— 两个都得问。
        // 只问 CONNECT 会出现"能看到已配对的手环, 却搜不到新的"这种半残状态。
        val needed = arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
        ).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (needed.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingPermissions != null) {
            result.error("busy", "已有权限请求在进行", null)
            return
        }
        pendingPermissions = result
        requestPermissions(needed.toTypedArray(), PERM_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERM_CODE) return
        val r = pendingPermissions
        pendingPermissions = null
        r?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
    }

    private fun bondedDevices(): List<Map<String, String>> {
        if (adapterState() != "on") return emptyList()
        return try {
            adapter?.bondedDevices?.map {
                mapOf("address" to it.address, "name" to (it.name ?: it.address))
            }.orEmpty()
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    /** 搜索期间挂着的广播接收器与答复。一次只允许搜一轮。 */
    private var scanResult: MethodChannel.Result? = null
    private var scanReceiver: BroadcastReceiver? = null
    private var scanTimeout: Runnable? = null

    private fun discover(timeoutMs: Int, result: MethodChannel.Result) {
        val a = adapter
        if (a == null) { result.error("unsupported", "本机没有蓝牙适配器", null); return }
        if (!a.isEnabled) { result.error("off", "蓝牙未开启", null); return }
        if (scanResult != null) { result.error("busy", "上一次搜索还没结束", null); return }
        scanResult = result

        // 搜到的设备按地址去重: 同一个手环会随着信号强弱被重复上报好几次。
        val found = LinkedHashMap<String, Map<String, Any>>()
        // 先把已配对的塞进去 —— 它们不会出现在 discovery 的广播里, 但界面上要一起显示。
        for (d in bondedDevices()) {
            found[d["address"]!!] = mapOf(
                "address" to d["address"]!!,
                "name" to d["name"]!!,
                "paired" to true,
            )
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != BluetoothDevice.ACTION_FOUND) return
                val device: BluetoothDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                } ?: return
                val address = try { device.address } catch (e: SecurityException) { return }
                val name = try { device.name } catch (e: SecurityException) { null } ?: address
                found[address] = mapOf(
                    "address" to address,
                    "name" to name,
                    "paired" to (device.bondState == BluetoothDevice.BOND_BONDED),
                )
            }
        }
        scanReceiver = receiver
        registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND))

        val finish = Runnable { finishDiscover(found.values.toList()) }
        scanTimeout = finish
        main.postDelayed(finish, timeoutMs.toLong())

        try {
            // cancelDiscovery 之后再 startDiscovery: 上一次没停干净的搜索会让
            // startDiscovery 直接返回 false。
            a.cancelDiscovery()
            if (!a.startDiscovery()) finishDiscover(found.values.toList())
        } catch (e: SecurityException) {
            finishDiscover(found.values.toList())
        }
    }

    private fun finishDiscover(peers: List<Map<String, Any>>) {
        val r = scanResult ?: return
        scanResult = null
        scanTimeout?.let { main.removeCallbacks(it) }
        scanTimeout = null
        scanReceiver?.let {
            try { unregisterReceiver(it) } catch (e: IllegalArgumentException) { /* 已经没了 */ }
        }
        scanReceiver = null
        try { adapter?.cancelDiscovery() } catch (e: SecurityException) { /* 权限没了 */ }
        // 一个都没搜到不是错误: 附近真的没人应答, 由界面去说"没有"。
        r.success(peers)
    }

    private fun pair(address: String, result: MethodChannel.Result) {
        if (address.isEmpty()) { result.error("argument", "地址不能为空", null); return }
        val a = adapter
        if (a == null) { result.error("unsupported", "本机没有蓝牙适配器", null); return }
        try {
            val device = a.getRemoteDevice(address)
            if (device.bondState == BluetoothDevice.BOND_BONDED) { result.success(true); return }
            // createBond 只是"发起", 真正的结果在 ACTION_BOND_STATE_CHANGED 里。
            // 这里等到状态变成 BONDED 或者失败再回话, 界面才不用猜。
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                    val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                    if (state == BluetoothDevice.BOND_BONDING) return
                    try { unregisterReceiver(this) } catch (e: IllegalArgumentException) { /* 已经没了 */ }
                    result.success(state == BluetoothDevice.BOND_BONDED)
                }
            }
            registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED))
            if (!device.createBond()) {
                try { unregisterReceiver(receiver) } catch (e: IllegalArgumentException) { /* 已经没了 */ }
                result.success(false)
            }
        } catch (e: SecurityException) {
            result.error("permission", "没有蓝牙配对权限", null)
        }
    }

    private fun connect(address: String, uuid: String, result: MethodChannel.Result) {
        if (address.isEmpty() || uuid.isEmpty()) {
            result.error("argument", "address 与 uuid 都不能为空", null)
            return
        }
        if (open.get()) {
            result.error("busy", "已经有一条 SPP 连接", null)
            return
        }
        val a = adapter
        if (a == null) { result.error("unsupported", "本机没有蓝牙适配器", null); return }
        if (!a.isEnabled) { result.error("off", "蓝牙未开启", null); return }
        io.execute {
            try {
                val socket = a.getRemoteDevice(address)
                    .createRfcommSocketToServiceRecord(UUID.fromString(uuid))
                // connect() 是阻塞调用, 必须在后台线程; 取消时由 closeSocket 打断。
                socket.connect()
                this.socket = socket
                input = socket.inputStream
                output = socket.outputStream
                open.set(true)
                main.post { result.success(null) }
                readLoop(socket)
            } catch (e: Exception) {
                closeSilently()
                main.post {
                    result.error("connect", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun readLoop(socket: BluetoothSocket) {
        val buf = ByteArray(READ_CHUNK)
        try {
            while (open.get()) {
                val n = input?.read(buf) ?: -1
                if (n <= 0) break
                val data = buf.copyOf(n)
                main.post { channel?.invokeMethod("chunk", data) }
            }
        } catch (e: Exception) {
            main.post { channel?.invokeMethod("closed", e.message ?: "连接中断") }
        } finally {
            val wasOpen = open.getAndSet(false)
            closeSocketOnly(socket)
            if (wasOpen) main.post { channel?.invokeMethod("closed", "对端关闭") }
        }
    }

    private fun send(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty()) { result.success(null); return }
        if (!open.get()) { result.error("closed", "载波未连接", null); return }
        io.execute {
            try {
                output?.apply { write(bytes); flush() }
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("write", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun closeSocketOnly(s: BluetoothSocket) {
        try { s.close() } catch (_: Exception) {}
    }

    private fun closeSilently() {
        open.set(false)
        socket?.let { closeSocketOnly(it) }
        socket = null
        input = null
        output = null
    }

    override fun onDestroy() {
        closeSilently()
        io.shutdownNow()
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
