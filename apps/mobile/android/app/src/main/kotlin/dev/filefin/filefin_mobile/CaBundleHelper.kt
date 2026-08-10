package dev.filefin.filefin_mobile

import android.content.Context
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.security.cert.X509Certificate

/**
 * Exports the device's live CA trust store to a PEM file that mpv can read.
 *
 * Android's system trust store lives under `/system/etc/security/cacerts` (and,
 * on API 34+, inside the Conscrypt APEX). Neither path is a single PEM bundle
 * that FFmpeg/mbedTLS can consume — they are individual DER files named by
 * subject hash — so libmpv has no native way to verify TLS certificates against
 * the platform store.
 *
 * This class reads every certificate from `AndroidCAStore` (which covers both
 * system and user-installed CAs), encodes each as PEM, and writes the result to
 * a file in the app's cache directory. The path is handed to mpv as
 * `tls-ca-file`, and from that point on `tls-verify=yes` works against the
 * device's actual trust store rather than against a bundled snapshot.
 *
 * Regenerated on every app cold start so newly installed enterprise CAs get
 * picked up.
 */
object CaBundleHelper {

    private const val FILENAME = "cacerts.pem"

    /**
     * Writes the CA bundle and returns its absolute path.
     *
     * Returns an empty string when the KeyStore is empty (unlikely but
     * defensive — an empty bundle is not a trust store and calling it one
     * would be the claim the method name makes).
     */
    fun export(context: Context): String {
        val ks = KeyStore.getInstance("AndroidCAStore").apply { load(null, null) }
        val out = File(context.cacheDir, FILENAME)

        var count = 0
        out.bufferedWriter().use { writer ->
            for (alias in ks.aliases()) {
                val cert = ks.getCertificate(alias) as? X509Certificate ?: continue
                val encoded = Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
                writer.write("-----BEGIN CERTIFICATE-----\n")
                encoded.chunked(64).forEach { writer.write(it); writer.write("\n") }
                writer.write("-----END CERTIFICATE-----\n")
                count++
            }
        }
        return if (count > 0) out.absolutePath else ""
    }
}
