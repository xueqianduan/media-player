package com.example.myplayer.transfer

import android.app.Activity
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.security.SecureRandom
import java.util.UUID

/**
 * Dart ↔ Android 传输桥。
 *
 * MethodChannel: prepareReceive / send / cancel / stopReceive / snapshot /
 * openFile / pickDocuments。EventChannel 推送 state / invite / progress / file / error。
 */
class TransferBridge(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val launchDocuments: () -> Unit,
    private val launchDirectory: () -> Unit,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var server: TransferServer? = null
    private var client: TransferClient? = null
    private var invite: TransferInvite? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingTree: MethodChannel.Result? = null
    private val state = mutableMapOf<String, Any?>("state" to "idle")

    fun register() {
        MethodChannel(messenger, "lumiplayer/transfer").setMethodCallHandler(this)
        EventChannel(messenger, "lumiplayer/transfer/events").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        events?.success(state.toMap())
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareReceive" -> prepareReceive(result)
            "stopReceive" -> {
                stopAll()
                result.success(true)
            }
            "send" -> send(call, result)
            "cancel" -> {
                stopAll()
                result.success(true)
            }
            "snapshot" -> result.success(state.toMap())
            "openFile" -> openFile(call, result)
            "pickDocuments" -> {
                pendingPick = result
                launchDocuments()
            }
            "pickDirectory" -> {
                pendingTree = result
                launchDirectory()
            }
            else -> result.notImplemented()
        }
    }

    private fun prepareReceive(result: MethodChannel.Result) {
        stopAll()
        val ip = localIpv4()
        if (ip == null) {
            result.error("NO_NETWORK", "没有可用的局域网地址，请先连接 Wi-Fi 或热点", null)
            return
        }
        val fingerprint = TransferSsl.serverFingerprint(activity)
        val sessionId = UUID.randomUUID().toString()
        val token = randomToken()
        val expiresAt = System.currentTimeMillis() / 1000 + 120
        val draft = TransferInvite(sessionId, ip, 1, fingerprint, token, expiresAt)

        val receiver = TransferServer(activity.applicationContext, draft) { event -> emit(event) }
        val port = try {
            receiver.start()
        } catch (error: Exception) {
            result.error("BIND_FAILED", error.message ?: "无法启动接收服务", null)
            return
        }
        val real = draft.copy(port = port)
        invite = real
        server = receiver
        state.clear()
        state.putAll(mapOf("state" to "waiting", "sessionId" to sessionId))

        val payload = mapOf(
            "invite" to real.encode(),
            "ip" to ip,
            "port" to port,
            "expiresAt" to expiresAt,
            "fingerprint" to fingerprint,
            "sessionId" to sessionId,
        )
        emit(mapOf("type" to "invite") + payload)
        result.success(payload)
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        stopAll()
        val text = call.argument<String>("invite")
        val parsed = TransferInvite.decode(text ?: "")
        if (parsed == null) {
            result.error("BAD_INVITE", "接收码无法识别", null)
            return
        }
        if (System.currentTimeMillis() / 1000 > parsed.expiresAt) {
            result.error("EXPIRED", "接收码已过期，请让对方刷新", null)
            return
        }
        val rows = call.argument<List<Map<String, Any?>>>("files") ?: emptyList()
        if (rows.isEmpty()) {
            result.error("EMPTY", "没有可发送的文件", null)
            return
        }
        val files = rows.mapNotNull { row ->
            val uri = row["uri"] as? String ?: return@mapNotNull null
            SendFile(
                id = row["id"] as? String ?: uri,
                name = row["name"] as? String ?: "未命名文件",
                mime = row["mime"] as? String ?: "application/octet-stream",
                type = row["type"] as? String ?: "other",
                size = (row["size"] as? Number)?.toLong() ?: 0L,
                uri = uri,
            )
        }
        if (files.isEmpty()) {
            result.error("EMPTY", "没有可读取的文件", null)
            return
        }

        val taskId = UUID.randomUUID().toString()
        state.clear()
        state.putAll(mapOf("state" to "connecting", "taskId" to taskId, "direction" to "send"))
        val sender = TransferClient(
            activity.applicationContext,
            parsed,
            taskId,
            files,
            android.os.Build.MODEL ?: "Android 设备",
        ) { event -> emit(event) }
        client = sender
        sender.start()
        result.success(taskId)
    }

    private fun openFile(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        val mime = call.argument<String>("mime") ?: "*/*"
        if (uri.isNullOrEmpty()) {
            result.error("BAD_URI", "文件地址为空", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(uri), mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("NO_VIEWER", "没有可打开该文件的应用", null)
        }
    }

    fun onDocumentsPicked(uris: List<Uri>) {
        val items = uris.mapNotNull { uri ->
            runCatching {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            val resolver = activity.contentResolver
            var name = uri.lastPathSegment ?: "未命名文件"
            var size = 0L
            resolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }
                }
            }
            val mime = resolver.getType(uri) ?: "application/octet-stream"
            mapOf(
                "uri" to uri.toString(),
                "name" to name,
                "size" to size,
                "mime" to mime,
            )
        }
        pendingPick?.success(items)
        pendingPick = null
    }

    fun onDirectoryPicked(uri: Uri?) {
        if (uri != null) {
            runCatching {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
        }
        pendingTree?.success(uri?.toString())
        pendingTree = null
    }

    private fun stopAll() {
        runCatching { server?.cancel() }
        runCatching { client?.cancel() }
        server = null
        client = null
        invite = null
        state.clear()
        state.putAll(mapOf("state" to "idle"))
    }

    private fun emit(event: Map<String, Any?>) {
        main.post {
            val type = event["type"]
            when (type) {
                "state" -> {
                    state.clear()
                    state.putAll(event)
                }
            }
            sink?.success(event)
        }
    }

    private fun localIpv4(): String? {
        val manager = activity.getSystemService(ConnectivityManager::class.java)
        val network = manager.activeNetwork ?: return null
        val caps = manager.getNetworkCapabilities(network) ?: return null
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        ) {
            return null
        }
        val props = manager.getLinkProperties(network) ?: return null
        for (link in props.linkAddresses) {
            val address = link.address
            if (address is Inet4Address && !address.isLoopbackAddress) {
                return address.hostAddress
            }
        }
        return null
    }

    private fun randomToken(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
