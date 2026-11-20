package com.example.myplayer.transfer

import org.json.JSONObject

/** 邀请码：二维码文本与解析共用同一份结构。 */
data class TransferInvite(
    val sessionId: String,
    val ip: String,
    val port: Int,
    val fingerprint: String,
    val token: String,
    val expiresAt: Long,
) {
    fun encode(): String =
        "LUMI1|$sessionId|$ip|$port|$fingerprint|$token|$expiresAt"

    companion object {
        fun decode(text: String): TransferInvite? {
            val parts = text.trim().split('|')
            if (parts.size != 7 || parts[0] != "LUMI1") return null
            val port = parts[3].toIntOrNull() ?: return null
            val expires = parts[6].toLongOrNull() ?: return null
            if (port !in 1..65535) return null
            if (!parts[2].matches(Regex("^\\d{1,3}(\\.\\d{1,3}){3}$"))) return null
            if (parts[4].length != 64 || parts[5].length < 32) return null
            if (parts[1].isEmpty()) return null
            return TransferInvite(
                sessionId = parts[1],
                ip = parts[2],
                port = port,
                fingerprint = parts[4].lowercase(),
                token = parts[5],
                expiresAt = expires,
            )
        }
    }
}

/** 清单中的一个文件（发送端提交给接收端）。 */
data class ManifestFile(
    val id: String,
    val name: String,
    val mime: String,
    val type: String,
    val size: Long,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("mime", mime)
        .put("type", type)
        .put("size", size)
}

/** 发送端本地文件来源。 */
data class SendFile(
    val id: String,
    val name: String,
    val mime: String,
    val type: String,
    val size: Long,
    val uri: String,
) {
    fun toManifest(): ManifestFile = ManifestFile(id, name, mime, type, size)
}

/** 统一的事件回调：state / progress / file / error。 */
typealias TransferEvents = (Map<String, Any?>) -> Unit
