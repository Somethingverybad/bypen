// Проверка подписи профиля: Ed25519 по байтам строки payload. Публичный ключ зашит —
// подменить список узлов через провайдера или CDN нельзя.
package com.hyax.bypen

import android.util.Base64
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer

object Pinned {
    /** base64 публичного ключа сервера (manage.py vpn_pubkey). null — отладка. */
    val PUBLIC_KEY: String? = "mom4ETYn/8XuqZxbKEWEgk9DJcGK+l31/i4e9Bwc4Bw="
    const val API_BASE = "https://hyax.ru/api"
    const val UPDATE_URL = "https://hyax.ru/apk/bypen/android.json"
}

class SignatureError(msg: String) : Exception(msg)

object Signature {
    /** Возвращает предупреждение (null — всё строго) или бросает SignatureError. */
    fun verify(payload: String, sig: String, pub: String): String? {
        var warning: String? = null
        val expected: String
        if (Pinned.PUBLIC_KEY != null) {
            expected = Pinned.PUBLIC_KEY
            if (pub != expected) throw SignatureError("Ключ подписи не совпадает с зашитым в приложение")
        } else {
            if (sig.isEmpty()) return "Профиль без подписи (сервер без ключа) — отладка"
            expected = pub
            warning = "Ключ подписи не зашит в сборку — принят ключ сервера (отладка)"
        }
        if (sig.isEmpty()) throw SignatureError("Ответ сервера без подписи")
        val key = try { Ed25519PublicKeyParameters(Base64.decode(expected, Base64.DEFAULT), 0) }
            catch (e: Exception) { throw SignatureError("Ключ подписи не разобран") }
        val signer = Ed25519Signer()
        signer.init(false, key)
        val data = payload.toByteArray(Charsets.UTF_8)
        signer.update(data, 0, data.size)
        if (!signer.verifySignature(Base64.decode(sig, Base64.DEFAULT))) throw SignatureError("Подпись профиля не сходится")
        return warning
    }
}
