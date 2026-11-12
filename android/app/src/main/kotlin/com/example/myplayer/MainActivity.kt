package com.example.myplayer

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 宿主 Activity。
 *
 * 只做一件事：给 Dart 侧提供读取 / 清理 WebView Cookie 的通道，
 * 供内嵌 B 站官方登录页在登录完成后取回 SESSDATA 等凭证。
 * （SESSDATA 是 HttpOnly，JavaScript 读不到，只能走原生 CookieManager。）
 */
class MainActivity : FlutterActivity() {

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
    }
}
