package com.example.myplayer.transfer

import android.content.Context
import android.os.Build
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.InetAddress
import java.security.MessageDigest
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import org.json.JSONObject

/** 接收端：监听 TLS、校验邀请、写入文件并回 ACK。 */
class TransferServer(
    private val context: Context,
    private val invite: TransferInvite,
    private val events: TransferEvents,
) {
    private var serverSocket: SSLServerSocket? = null
    private var socket: SSLSocket? = null
    private var thread: Thread? = null
    @Volatile private var cancelled = false
    @Volatile private var claimed = false

    fun start(): Int {
        val factory = TransferSsl.serverContext(context).serverSocketFactory
        val ss = factory.createServerSocket(
            0,
            1,
            InetAddress.getByName(invite.ip),
        ) as SSLServerSocket
        ss.soTimeout = 120_000
        ss.enabledProtocols = arrayOf("TLSv1.2", "TLSv1.3")
        serverSocket = ss
        thread = Thread({ acceptLoop() }, "lumi-transfer-server").also {
            it.isDaemon = true
            it.start()
        }
        return ss.localPort
    }

    fun cancel() {
        cancelled = true
        runCatching { socket?.close() }
        runCatching { serverSocket?.close() }
    }

    private fun acceptLoop() {
        try {
            val ss = serverSocket ?: return
            val client = ss.accept() as SSLSocket
            if (cancelled || claimed) {
                runCatching { client.close() }
                return
            }
            claimed = true
            runCatching { ss.close() }
            socket = client
            client.soTimeout = 30_000
            handle(client)
        } catch (error: Exception) {
            if (!cancelled) {
                emit(mapOf("type" to "error", "message" to (error.message ?: "接收连接中断")))
            }
        }
    }

    private fun handle(client: SSLSocket) {
        val input = BufferedInputStream(client.inputStream)
        val output = BufferedOutputStream(client.outputStream)
        val store = TransferStore(context)

        val hello = readControl(input, "HELLO")
        if (hello.optInt("v") != TransferProtocol.VERSION) {
            writeControl(output, JSONObject().put("t", "HELLO_ERR").put("message", "版本不支持"))
            throw IllegalStateException("对端协议版本不支持")
        }
        val sid = hello.optString("sessionId")
        val token = hello.optString("token")
        if (sid != invite.sessionId ||
            !MessageDigest.isEqual(token.toByteArray(), invite.token.toByteArray())
        ) {
            writeControl(output, JSONObject().put("t", "HELLO_ERR").put("message", "邀请已失效"))
            throw IllegalStateException("邀请凭证不匹配")
        }
        if (System.currentTimeMillis() / 1000 > invite.expiresAt) {
            writeControl(output, JSONObject().put("t", "HELLO_ERR").put("message", "邀请已过期"))
            throw IllegalStateException("邀请已过期")
        }

        val deviceName = hello.optString("name", "Android 设备")
        writeControl(
            output,
            JSONObject().put("t", "HELLO_OK").put("name", Build.MODEL ?: "Android 设备"),
        )

        val manifest = readControl(input, "MANIFEST")
        val taskId = manifest.optString("taskId")
        val rows = manifest.optJSONArray("files") ?: throw IllegalStateException("清单为空")
        if (rows.length() > TransferProtocol.MAX_FILES) {
            throw IllegalStateException("单次最多 ${TransferProtocol.MAX_FILES} 个文件")
        }

        val files = ArrayList<ManifestFile>(rows.length())
        var total = 0L
        val ids = HashSet<String>()
        for (index in 0 until rows.length()) {
            val row = rows.getJSONObject(index)
            val id = row.optString("id")
            val size = row.optLong("size", -1)
            if (id.isEmpty() || !ids.add(id) || size < 0) {
                throw IllegalStateException("清单字段不合法")
            }
            total += size
            if (total > TransferProtocol.MAX_TOTAL) throw IllegalStateException("传输内容过大")
            files.add(
                ManifestFile(
                    id = id,
                    name = row.optString("name", "未命名文件"),
                    mime = row.optString("mime", "application/octet-stream"),
                    type = row.optString("type", "other"),
                    size = size,
                ),
            )
        }

        writeControl(
            output,
            JSONObject().put("t", "MANIFEST_OK").put("taskId", taskId),
        )
        emit(
            mapOf(
                "type" to "state",
                "state" to "receiving",
                "taskId" to taskId,
                "deviceName" to deviceName,
                "totalBytes" to total,
                "fileCount" to files.size,
            ),
        )

        var received = 0L
        for (file in files) {
            if (cancelled) throw IllegalStateException("已取消")
            received += receiveFile(input, output, store, file, taskId, received, total)
        }

        val finish = readControl(input, "FINISH")
        writeControl(
            output,
            JSONObject().put("t", "FINISH_ACK").put("taskId", finish.optString("taskId")),
        )
        emit(
            mapOf(
                "type" to "state",
                "state" to "completed",
                "taskId" to taskId,
                "receivedBytes" to received,
            ),
        )
        runCatching { client.close() }
    }

    private fun receiveFile(
        input: BufferedInputStream,
        output: BufferedOutputStream,
        store: TransferStore,
        file: ManifestFile,
        taskId: String,
        alreadyReceived: Long,
        total: Long,
    ): Long {
        val begin = readControl(input, "FILE_BEGIN")
        if (begin.optString("id") != file.id) throw IllegalStateException("文件顺序不一致")

        val sink = store.create(file.name, file.mime)
        val digest = MessageDigest.getInstance("SHA-256")
        var written = 0L
        var windowReceived = 0L
        var lastAck = System.currentTimeMillis()
        var published = false

        try {
            loop@ while (true) {
                if (cancelled) throw IllegalStateException("已取消")
                val frame = TransferProtocol.readFrame(input)
                if (frame.control) {
                    val json = JSONObject(String(frame.payload, Charsets.UTF_8))
                    when (json.optString("t")) {
                        "PING" -> writeControl(output, JSONObject().put("t", "PONG"))
                        "CANCEL" -> throw IllegalStateException("对端已取消")
                        "FILE_END" -> {
                            val size = json.optLong("size", -1)
                            val sha = json.optString("sha256")
                            if (size != file.size || written != file.size) {
                                throw IllegalStateException("字节数不一致")
                            }
                            val actual = digest.digest().joinToString("") { "%02x".format(it) }
                            if (!actual.equals(sha, ignoreCase = true)) {
                                throw IllegalStateException("校验失败")
                            }
                            val uri = sink.publish()
                            published = true
                            writeControl(
                                output,
                                JSONObject().put("t", "FILE_OK")
                                    .put("id", file.id)
                                    .put("name", sink.name)
                                    .put("uri", uri),
                            )
                            emit(
                                mapOf(
                                    "type" to "file",
                                    "id" to file.id,
                                    "name" to sink.name,
                                    "status" to "ok",
                                    "bytes" to written,
                                    "uri" to uri,
                                    "taskId" to taskId,
                                ),
                            )
                            break@loop
                        }
                    }
                    continue@loop
                }

                val length = frame.payload.size
                if (written + length > file.size) throw IllegalStateException("数据超出文件长度")
                sink.output.write(frame.payload)
                digest.update(frame.payload)
                written += length
                windowReceived += length

                val now = System.currentTimeMillis()
                val windowFull = windowReceived >= TransferProtocol.WINDOW
                if (windowFull || now - lastAck >= 200) {
                    writeControl(
                        output,
                        JSONObject().put("t", "ACK").put("bytes", alreadyReceived + written),
                    )
                    // 定时 ACK 只更新进度；只有窗口边界 ACK 才能开始下一个发送窗口。
                    // 否则发送端仍按 4 MiB 等待时，接收端可能清零计数后等下一块，形成死锁。
                    if (windowFull) windowReceived = 0
                    lastAck = now
                    emit(
                        mapOf(
                            "type" to "progress",
                            "received" to alreadyReceived + written,
                            "total" to total,
                            "current" to sink.name,
                            "taskId" to taskId,
                        ),
                    )
                }
            }
        } catch (error: Exception) {
            if (!published) runCatching { sink.abort() }
            emit(
                mapOf(
                    "type" to "file",
                    "id" to file.id,
                    "name" to file.name,
                    "status" to "failed",
                    "bytes" to written,
                    "error" to (error.message ?: "写入失败"),
                    "taskId" to taskId,
                ),
            )
            throw error
        }
        return written
    }

    private fun readControl(input: BufferedInputStream, expected: String): JSONObject {
        val frame = TransferProtocol.readFrame(input)
        if (!frame.control) throw IllegalStateException("期望控制帧 $expected")
        val json = JSONObject(String(frame.payload, Charsets.UTF_8))
        if (json.optString("t") != expected) {
            throw IllegalStateException("期望 $expected，收到 ${json.optString("t")}")
        }
        return json
    }

    private fun writeControl(output: BufferedOutputStream, json: JSONObject) {
        TransferProtocol.writeControl(output, json)
    }

    private fun emit(event: Map<String, Any?>) {
        if (!cancelled || event["type"] == "error") events(event)
    }
}
