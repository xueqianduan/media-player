package com.example.myplayer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.CookieManager
import com.example.myplayer.transfer.TransferBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 宿主 Activity。
 *
 * 1. B 站登录 Cookie 通道（SESSDATA 是 HttpOnly，只能走 CookieManager）。
 * 2. 文件传输桥：TLS 接收/发送、系统选择器与目录授权。
 */
class MainActivity : FlutterActivity() {

    private lateinit var transferBridge: TransferBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lumiplayer/bili_cookie")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cookies" -> {
                        val urls = call.argument<List<String>>("urls")
                            ?: listOf("https://www.bilibili.com")
                        val names = HashSet<String>()
                        val parts = ArrayList<String>()
                        for (url in urls) {
                            val raw = try {
                                CookieManager.getInstance().getCookie(url) ?: ""
                            } catch (error: Exception) {
                                ""
                            }
                            for (part in raw.split(";")) {
                                val name = part.substringBefore("=", "").trim()
                                if (name.isEmpty() || !names.add(name)) continue
                                parts.add(part.trim())
                            }
                        }
                        result.success(parts.joinToString("; "))
                    }

                    "clear" -> {
                        try {
                            CookieManager.getInstance().removeAllCookies {
                                CookieManager.getInstance().flush()
                                result.success(true)
                            }
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        transferBridge = TransferBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            ::launchDocuments,
            ::launchDirectory,
        )
        transferBridge.register()
    }

    private fun launchDocuments() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQ_DOCUMENTS)
    }

    private fun launchDirectory() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQ_DIRECTORY)
    }

    @Deprecated("FlutterActivity 只暴露 startActivityForResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (!::transferBridge.isInitialized) return
        when (requestCode) {
            REQ_DOCUMENTS -> {
                if (resultCode != Activity.RESULT_OK) {
                    transferBridge.onDocumentsPicked(emptyList())
                    return
                }
                val uris = ArrayList<Uri>()
                data?.clipData?.let { clip ->
                    for (index in 0 until clip.itemCount) {
                        uris.add(clip.getItemAt(index).uri)
                    }
                }
                data?.data?.let { uris.add(it) }
                transferBridge.onDocumentsPicked(uris)
            }
            REQ_DIRECTORY -> {
                transferBridge.onDirectoryPicked(
                    if (resultCode == Activity.RESULT_OK) data?.data else null,
                )
            }
        }
    }

    companion object {
        private const val REQ_DOCUMENTS = 4101
        private const val REQ_DIRECTORY = 4102
    }
}
