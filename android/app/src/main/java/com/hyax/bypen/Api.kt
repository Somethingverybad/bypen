// Связь с сервером WYX: вход по аккаунту мессенджера (JWT), профиль узлов, отчёты.
package com.hyax.bypen

import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class ApiError(message: String, val unauthorized: Boolean = false) : Exception(message)

object Api {
    val base: String get() = Store.prefs.getString("apiBase", null) ?: Pinned.API_BASE
    var access: String? get() = Store.prefs.getString("access", null); set(v) { Store.prefs.edit().putString("access", v).apply() }
    var refresh: String? get() = Store.prefs.getString("refresh", null); set(v) { Store.prefs.edit().putString("refresh", v).apply() }
    var username: String? get() = Store.prefs.getString("username", null); set(v) { Store.prefs.edit().putString("username", v).apply() }
    val isLoggedIn get() = refresh != null

    val version: String get() = try {
        val p = Store.ctx.packageManager.getPackageInfo(Store.ctx.packageName, 0)
        "${p.versionName} (${p.longVersionCode})"
    } catch (e: Exception) { "?" }
    val appTag get() = "android $version"

    val deviceId: String get() = Store.prefs.getString("deviceId", null) ?: ("bypen-" + UUID.randomUUID().toString()).also {
        Store.prefs.edit().putString("deviceId", it).apply()
    }

    suspend fun login(username: String, password: String) {
        val body = JSONObject().put("username", username).put("password", password)
            .put("device_id", deviceId).put("device_name", "Бупень · ${Build.MANUFACTURER} ${Build.MODEL}")
            .put("platform", "android").put("app_version", version)
        val (code, obj) = send("token/", "POST", body, auth = false)
        val a = obj?.optString("access", ""); val r = obj?.optString("refresh", "")
        if (code != 200 || a.isNullOrEmpty() || r.isNullOrEmpty()) throw ApiError(detail(obj) ?: "Не удалось войти ($code)")
        access = a; refresh = r; Api.username = username
    }

    // Вход через бота в WYX (сервер: chat/bypen_login.py)

    const val WYX_DOWNLOADS = "https://wyx.su/#download"
    const val WYX_PACKAGE = "com.hyax.messenger"

    data class BotLoginRequest(val id: String, val secret: String, val expiresIn: Int, val interval: Int, val bot: String)

    /** Бот «Бупень» пишет человеку в WYX «Подтвердить вход?». */
    suspend fun startBotLogin(username: String): BotLoginRequest {
        val body = JSONObject().put("username", username)
            .put("device_id", deviceId).put("device_name", "Бупень · ${Build.MANUFACTURER} ${Build.MODEL}")
            .put("platform", "android").put("app_version", version)
        val (code, obj) = send("vpn/login/start/", "POST", body, auth = false)
        val id = obj?.optString("id", ""); val secret = obj?.optString("secret", "")
        if (code != 200 || id.isNullOrEmpty() || secret.isNullOrEmpty()) throw ApiError(detail(obj) ?: "Не удалось отправить запрос ($code)")
        return BotLoginRequest(id, secret, obj.optInt("expires_in", 300), obj.optInt("interval", 2).coerceAtLeast(1), obj.optString("bot", "Бупень"))
    }

    /** Ждать «Да» в WYX; отмена корутины прерывает. Сетевые сбои по пути — спрашиваем снова. */
    suspend fun waitBotLogin(r: BotLoginRequest) {
        val deadline = System.currentTimeMillis() + (r.expiresIn + 10) * 1000L
        while (System.currentTimeMillis() < deadline) {
            kotlinx.coroutines.delay(r.interval * 1000L)
            val (code, obj) = try {
                send("vpn/login/poll/", "POST", JSONObject().put("id", r.id).put("secret", r.secret), auth = false)
            } catch (e: ApiError) { continue }
            if (code == 404) throw ApiError("Запрос устарел — попробуйте ещё раз")
            if (code != 200) continue
            when (obj?.optString("status")) {
                "approved" -> {
                    val a = obj.optString("access", ""); val rf = obj.optString("refresh", "")
                    if (a.isEmpty() || rf.isEmpty()) throw ApiError("Запрос устарел — попробуйте ещё раз")
                    access = a; refresh = rf; username = obj.optString("username", "")
                    return
                }
                "denied" -> throw ApiError("Вход отклонён в WYX")
                "expired", "used" -> throw ApiError("Запрос устарел — попробуйте ещё раз")
            }
        }
        throw ApiError("Запрос устарел — попробуйте ещё раз")
    }

    fun logout() { access = null; refresh = null; username = null }

    private suspend fun refreshTokens() {
        val r = refresh ?: throw ApiError("Нужно войти", true)
        val (code, obj) = send("token/refresh/", "POST", JSONObject().put("refresh", r), auth = false)
        val a = obj?.optString("access", "")
        if (code != 200 || a.isNullOrEmpty()) {
            if (code == 401 || code == 400) { logout(); throw ApiError("Сеанс истёк — войдите снова", true) }
            throw ApiError(detail(obj) ?: "Не удалось обновить сеанс ($code)")
        }
        access = a
        obj!!.optString("refresh", "").takeIf { it.isNotEmpty() }?.let { refresh = it }
    }

    data class SignedProfile(val payload: String, val sig: String, val pub: String)

    suspend fun fetchProfile(): SignedProfile {
        val (code, obj) = authorized("vpn/profile/", "GET")
        if (code != 200) throw ApiError(detail(obj) ?: "Профиль не получен ($code)")
        val payload = obj?.optString("payload", "") ?: ""
        if (payload.isEmpty()) throw ApiError("Профиль в неожиданном виде")
        return SignedProfile(payload, obj!!.optString("sig", ""), obj.optString("pub", ""))
    }

    suspend fun report(events: List<JSONObject>): Int {
        val (code, obj) = authorized("vpn/report/", "POST", JSONObject().put("events", JSONArray(events)))
        if (code != 200) throw ApiError(detail(obj) ?: "Отчёт не принят ($code)")
        return obj?.optInt("saved", 0) ?: 0
    }

    private suspend fun authorized(path: String, method: String, body: JSONObject? = null): Pair<Int, JSONObject?> {
        if (access == null) refreshTokens()
        var r = send(path, method, body, auth = true)
        if (r.first == 401) {
            refreshTokens()
            r = send(path, method, body, auth = true)
            if (r.first == 401) { logout(); throw ApiError("Сеанс истёк — войдите снова", true) }
        }
        return r
    }

    private suspend fun send(path: String, method: String, body: JSONObject?, auth: Boolean): Pair<Int, JSONObject?> = withContext(Dispatchers.IO) {
        try {
            val c = URL("$base/$path").openConnection() as HttpURLConnection
            c.requestMethod = method; c.connectTimeout = 15000; c.readTimeout = 20000
            c.setRequestProperty("Content-Type", "application/json"); c.setRequestProperty("Accept", "application/json")
            c.setRequestProperty("X-WYX-App", appTag); c.setRequestProperty("User-Agent", "Bypen/$version Android")
            if (auth) access?.let { c.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) { c.doOutput = true; c.outputStream.use { it.write(body.toString().toByteArray()) } }
            val code = c.responseCode
            val text = (if (code < 400) c.inputStream else c.errorStream)?.bufferedReader()?.readText() ?: ""
            code to (try { JSONObject(text) } catch (e: Exception) { null })
        } catch (e: ApiError) { throw e } catch (e: Exception) {
            throw ApiError("Сервер недоступен: ${e.message}")
        }
    }

    private fun detail(o: JSONObject?): String? = o?.optString("detail", null) ?: o?.optString("error", null)
}
