// Обёртка над libXray (gomobile): LibXray.invoke(JSON) → {success, data, error}.
package com.hyax.bypen

import libXray.LibXray
import org.json.JSONObject

object XrayCore {
    data class Reply(val ok: Boolean, val data: JSONObject?, val error: String)

    fun invoke(method: String, payload: JSONObject = JSONObject()): Reply {
        val req = JSONObject().put("apiVersion", 3).put("method", method).put("payload", payload)
        val out = try { LibXray.invoke(req.toString()) } catch (e: Throwable) { return Reply(false, null, "ядро: ${e.message}") }
        val o = try { JSONObject(out) } catch (e: Exception) { return Reply(false, null, "ответ ядра не разобран: ${out.take(200)}") }
        return Reply(o.optBoolean("success", false), o.optJSONObject("data"), o.optString("error", ""))
    }

    /** null — успех, иначе текст ошибки. */
    fun run(configJSON: String): String? {
        val r = invoke("runXray", JSONObject().put("xrayJson", configJSON))
        return if (r.ok) null else r.error.ifEmpty { "runXray: неизвестная ошибка" }
    }

    fun stop() { invoke("stopXray") }
    val version: String get() = invoke("xrayVersion").data?.optString("version") ?: "?"
}
