package com.example.myplayer.transfer

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream
import org.json.JSONObject

/** 帧格式：[type:1][len:4][payload]。type 0 = JSON 控制帧，1 = 二进制块。 */
object TransferProtocol {
    const val VERSION = 1
    const val CHUNK = 256 * 1024
    const val WINDOW = 4L * 1024 * 1024
    const val CONTROL_LIMIT = 64 * 1024
    const val MAX_FILES = 200
    const val MAX_TOTAL = 8L * 1024 * 1024 * 1024

    private const val TYPE_CONTROL = 0
    private const val TYPE_DATA = 1

    fun writeControl(out: OutputStream, json: JSONObject) {
        val payload = json.toString().toByteArray(Charsets.UTF_8)
        require(payload.size <= CONTROL_LIMIT) { "控制帧过大" }
        val stream = DataOutputStream(out)
        stream.writeByte(TYPE_CONTROL)
        stream.writeInt(payload.size)
        stream.write(payload)
        stream.flush()
    }

    fun writeData(out: OutputStream, bytes: ByteArray, offset: Int, length: Int) {
        val stream = DataOutputStream(out)
        stream.writeByte(TYPE_DATA)
        stream.writeInt(length)
        stream.write(bytes, offset, length)
        stream.flush()
    }

    class Frame(val control: Boolean, val payload: ByteArray)

    fun readFrame(input: InputStream): Frame {
        val stream = DataInputStream(input)
        val type = stream.readUnsignedByte()
        val length = stream.readInt()
        if (length < 0 || length > MAX_TOTAL.toInt()) throw IllegalStateException("帧长度非法")
        if (type == TYPE_CONTROL && length > CONTROL_LIMIT) throw IllegalStateException("控制帧过大")
        val payload = ByteArray(length)
        stream.readFully(payload)
        return Frame(type == TYPE_CONTROL, payload)
    }
}
