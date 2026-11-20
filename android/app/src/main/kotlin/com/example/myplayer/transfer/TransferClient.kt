package com.example.myplayer.transfer

import android.content.Context
import android.net.Uri
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import javax.net.ssl.SSLSocket
import org.json.JSONArray
import org.json.JSONObject

/** 发送端：连接接收端、提交清单、按块发送并等待确认。 */
class TransferClient(
    private val context: Context,
    private val invite: TransferInvite,
    private val taskId: String,
    private val files: List<SendFile>,
    private val deviceName: String,
    private val events: TransferEvents,
) {
    private var socket: SSLSocket? = null
    @Volatile private var cancelled = false

    fun start() {
        val thread = Thread({ run() }, "lumi-transfer-client")
        thread.isDaemon = true
        thread.start()
    }

    fun cancel() {
        cancelled = true
        runCatching { socket?.close() }
    }

    private fun run() {
        try {
            if (System.currentTimeMillis() / 1000 > invite.expiresAt) {
                throw IllegalStateException("接收码已过期，请让对方刷新")
            }
            val raw = Socket()
            raw.connect(InetSocketAddress(invite.ip, invite.port), 5000)
            raw.soTimeout = 30_000
            val ssl = TransferSsl.clientContext().socketFactory.createSocket(
                raw,
                invite.ip,
                invite.port,
                true,
            ) as SSLSocket
            ssl.enabledProtocols = arrayOf("TLSv1.2", "TLSv1.3")
            ssl.useClientMode = true
            ssl.startHandshake()
            socket = ssl

            val peer = ssl.session.peerCertificates.firstOrNull()
                ?: throw IllegalStateException("接收端证书缺失")
            val actual = TransferSsl.fingerprint(peer)
            if (!actual.equals(invite.fingerprint, ignoreCase = true)) {
                throw IllegalStateException("接收端身份校验失败，已断开")
            }

            val input = BufferedInputStream(ssl.inputStream)
            val output = BufferedOutputStream(ssl.outputStream)

            TransferProtocol.writeControl(
                output,
                JSONObject().put("t", "HELLO")
                    .put("v", TransferProtocol.VERSION)
                    .put("sessionId", invite.sessionId)
                    .put("token", invite.token)
                    .put("name", deviceName),
            )
            val hello = readControl(input, "HELLO_OK")
            emit(
                mapOf(
                    "type" to "state",
                    "state" to "connected",
                    "taskId" to taskId,
                    "deviceName" to hello.optString("name", "Android 设备"),
                ),
            )

            val manifest = JSONArray()
            for (file in files) manifest.put(file.toManifest().toJson())
            TransferProtocol.writeControl(
                output,
                JSONObject().put("t", "MANIFEST")
                    .put("taskId", taskId)
                    .put("files", manifest),
            )
            readControl(input, "MANIFEST_OK")

            var confirmed = 0L
            val total = files.sumOf { it.size }
            for (file in files) {
                if (cancelled) throw IllegalStateException("已取消")
                confirmed += sendFile(input, output, file, confirmed, total)
            }

            TransferProtocol.writeControl(
                output,
                JSONObject().put("t", "FINISH").put("taskId", taskId),
            )
            readControl(input, "FINISH_ACK")
            emit(
                mapOf(
                    "type" to "state",
                    "state" to "completed",
                    "taskId" to taskId,
                    "confirmedBytes" to confirmed,
                ),
            )
            runCatching { ssl.close() }
        } catch (error: Exception) {
            if (cancelled) {
                emit(mapOf("type" to "state", "state" to "cancelled", "taskId" to taskId))
            } else {
                emit(
                    mapOf(
                        "type" to "error",
                        "taskId" to taskId,
                        "message" to (error.message ?: "发送失败"),
                    ),
                )
            }
            runCatching { socket?.close() }
        }
    }

    private fun sendFile(
        input: BufferedInputStream,
        output: BufferedOutputStream,
        file: SendFile,
        alreadyConfirmed: Long,
        total: Long,
    ): Long {
        val source = openSource(file.uri) ?: throw IllegalStateException("无法读取 ${file.name}")
        TransferProtocol.writeControl(
            output,
            JSONObject().put("t", "FILE_BEGIN").put("id", file.id),
        )
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(TransferProtocol.CHUNK)
        var sent = 0L
        var unconfirmed = 0L

        source.use { stream ->
            while (true) {
                if (cancelled) throw IllegalStateException("已取消")
                val read = stream.read(buffer)
                if (read < 0) break
                if (read == 0) continue
                TransferProtocol.writeData(output, buffer, 0, read)
                digest.update(buffer, 0, read)
                sent += read
                unconfirmed += read
                if (unconfirmed >= TransferProtocol.WINDOW) {
                    confirmedWait(input, output, alreadyConfirmed + sent, file, total)
                    unconfirmed = 0
                }
            }
        }

        if (sent != file.size) throw IllegalStateException("${file.name} 大小在传输中变化")
        val sha = digest.digest().joinToString("") { "%02x".format(it) }
        TransferProtocol.writeControl(
            output,
            JSONObject().put("t", "FILE_END")
                .put("id", file.id)
                .put("size", sent)
                .put("sha256", sha),
        )
        waitFileOk(input, file, total)
        emit(
            mapOf(
                "type" to "file",
                "id" to file.id,
                "name" to file.name,
                "status" to "ok",
                "bytes" to sent,
                "taskId" to taskId,
            ),
        )
        return sent
    }

    private fun confirmedWait(
        input: BufferedInputStream,
        output: BufferedOutputStream,
        target: Long,
        file: SendFile,
        total: Long,
    ) {
        while (true) {
            val json = readAny(input)
            when (json.optString("t")) {
                "ACK" -> {
                    val bytes = json.optLong("bytes", 0)
                    emitProgress(bytes, total, file.name)
                    if (bytes >= target) return
                }
                "PING" -> TransferProtocol.writeControl(
                    output,
                    JSONObject().put("t", "PONG"),
                )
                "FILE_ERR", "MANIFEST_ERR", "HELLO_ERR" ->
                    throw IllegalStateException(json.optString("message", "接收端拒绝"))
                else -> Unit
            }
        }
    }

    private fun waitFileOk(input: BufferedInputStream, file: SendFile, total: Long) {
        while (true) {
            val json = readAny(input)
            when (json.optString("t")) {
                "FILE_OK" -> return
                "FILE_ERR" -> throw IllegalStateException(json.optString("message", "文件保存失败"))
                "ACK" -> emitProgress(json.optLong("bytes", 0), total, file.name)
                "PING" -> Unit
                else -> Unit
            }
        }
    }

    private fun emitProgress(bytes: Long, total: Long, current: String) {
        emit(
            mapOf(
                "type" to "progress",
                "received" to bytes,
                "total" to total,
                "current" to current,
                "taskId" to taskId,
            ),
        )
    }

    private fun readControl(input: BufferedInputStream, expected: String): JSONObject {
        val json = readAny(input)
        if (json.optString("t") != expected) {
            val message = json.optString("message", "对端返回 ${json.optString("t")}")
            throw IllegalStateException(message)
        }
        return json
    }

    private fun readAny(input: BufferedInputStream): JSONObject {
        val frame = TransferProtocol.readFrame(input)
        if (!frame.control) throw IllegalStateException("期望控制帧，收到数据块")
        return JSONObject(String(frame.payload, Charsets.UTF_8))
    }

    private fun openSource(uri: String): InputStream? {
        return try {
            when {
                uri.startsWith("content://") -> context.contentResolver.openInputStream(Uri.parse(uri))
                uri.startsWith("file://") -> FileInputStream(File(Uri.parse(uri).path!!))
                uri.startsWith("/") -> FileInputStream(File(uri))
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun emit(event: Map<String, Any?>) = events(event)
}
