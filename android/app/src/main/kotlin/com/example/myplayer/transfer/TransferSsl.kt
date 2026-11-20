package com.example.myplayer.transfer

import android.content.Context
import com.example.myplayer.R
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.Certificate
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * TLS 身份与指纹。
 *
 * 首版服务端证书随包发布（res/raw/transfer_identity.p12）；发送端不信任系统 CA，
 * 握手后强制比对二维码里的 SHA-256 指纹，指纹不符立即断开。
 */
object TransferSsl {
    private const val PASS = "lumi-local-transfer"

    @Volatile private var server: SSLContext? = null

    fun serverContext(context: Context): SSLContext = server ?: synchronized(this) {
        server ?: build(context).also { server = it }
    }

    /** 发送端：接受任意证书，随后用指纹做真正的校验。 */
    fun clientContext(): SSLContext {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        })
        val ctx = SSLContext.getInstance("TLS")
        ctx.init(null, trustAll, null)
        return ctx
    }

    fun fingerprint(cert: Certificate): String = sha256Hex(cert.encoded)

    /** 本机接收服务的证书指纹，写进二维码供发送端比对。 */
    fun serverFingerprint(context: Context): String {
        val keyStore = KeyStore.getInstance("PKCS12")
        context.resources.openRawResource(R.raw.transfer_identity).use { input ->
            keyStore.load(input, PASS.toCharArray())
        }
        val cert = keyStore.getCertificate("lumi-transfer") ?: error("证书缺失")
        return fingerprint(cert)
    }

    fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun build(context: Context): SSLContext {
        val keyStore = KeyStore.getInstance("PKCS12")
        context.resources.openRawResource(R.raw.transfer_identity).use { input ->
            keyStore.load(input, PASS.toCharArray())
        }
        val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        kmf.init(keyStore, PASS.toCharArray())
        val ctx = SSLContext.getInstance("TLS")
        ctx.init(kmf.keyManagers, null, null)
        return ctx
    }
}
