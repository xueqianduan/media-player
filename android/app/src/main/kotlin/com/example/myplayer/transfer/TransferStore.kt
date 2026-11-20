package com.example.myplayer.transfer

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

/**
 * 接收落盘。
 *
 * API 29+：MediaStore.Downloads + Download/LumiPlayer/，写入时 IS_PENDING=1，
 * 校验通过后置 0 才对外可见。旧系统写到应用外部目录（无需额外权限）。
 */
class TransferStore(private val context: Context) {

    data class Sink(
        val name: String,
        val output: OutputStream,
        val publish: () -> String,
        val abort: () -> Unit,
    )

    fun create(rawName: String, mime: String): Sink {
        val name = uniqueName(sanitize(rawName))
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            createMediaStore(name, mime)
        } else {
            createLegacy(name)
        }
    }

    private fun createMediaStore(name: String, mime: String): Sink {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime.ifEmpty { "application/octet-stream" })
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/LumiPlayer",
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("无法创建接收文件")
        val output = resolver.openOutputStream(uri)
            ?: throw IllegalStateException("无法写入接收文件")

        return Sink(
            name = name,
            output = output,
            publish = {
                runCatching { output.close() }
                val done = ContentValues().apply {
                    put(MediaStore.Downloads.IS_PENDING, 0)
                }
                resolver.update(uri, done, null, null)
                uri.toString()
            },
            abort = {
                runCatching { output.close() }
                runCatching { resolver.delete(uri, null, null) }
                Unit
            },
        )
    }

    private fun createLegacy(name: String): Sink {
        val dir = File(
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            "LumiPlayer",
        )
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, name)
        val output = FileOutputStream(file)

        return Sink(
            name = name,
            output = output,
            publish = {
                runCatching { output.close() }
                Uri.fromFile(file).toString()
            },
            abort = {
                runCatching { output.close() }
                runCatching { file.delete() }
                Unit
            },
        )
    }

    fun uniqueName(name: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val dir = File(
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                "LumiPlayer",
            )
            return numberedIfExists(name) { File(dir, it).exists() }
        }
        val resolver = context.contentResolver
        return numberedIfExists(name) { candidate ->
            val projection = arrayOf(MediaStore.Downloads._ID)
            val selection =
                "${MediaStore.Downloads.DISPLAY_NAME}=? AND " +
                    "${MediaStore.Downloads.RELATIVE_PATH}=?"
            val args = arrayOf(
                candidate,
                "${Environment.DIRECTORY_DOWNLOADS}/LumiPlayer/",
            )
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                args,
                null,
            )?.use { it.count > 0 } ?: false
        }
    }

    private fun numberedIfExists(name: String, exists: (String) -> Boolean): String {
        if (!exists(name)) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var index = 1
        while (index < 1000) {
            val candidate = "$base ($index)$ext"
            if (!exists(candidate)) return candidate
            index++
        }
        return "$base-${System.currentTimeMillis()}$ext"
    }

    private fun sanitize(name: String): String {
        var value = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").trim()
        if (value.isEmpty() || value == "." || value == "..") value = "received_file"
        if (value.length > 120) {
            val dot = value.lastIndexOf('.')
            value = if (dot > 0 && value.length - dot <= 12) {
                value.substring(0, 100) + value.substring(dot)
            } else {
                value.substring(0, 120)
            }
        }
        return value
    }
}
