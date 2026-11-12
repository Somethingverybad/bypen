// Обновление APK: манифест Pinned.UPDATE_URL (scripts/publish.sh кладёт его в бакет)
// {"versionCode": N, "versionName": "...", "url": "...apk", "sha256": "...", "notes": "...",
//  "abis": {"arm64-v8a": {"url": "...", "sha256": "..."}, ...}} — берём свою архитектуру, иначе url.
// Качаем в кэш, сверяем sha256, отдаём системному установщику (нужно разрешение
// «установка из этого источника», Android спросит сам).
package com.hyax.bypen

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

data class UpdateInfo(val versionCode: Long, val versionName: String, val url: String, val sha256: String, val notes: String)

sealed class UpdateState {
    object None : UpdateState()
    data class Available(val info: UpdateInfo) : UpdateState()
    data class Downloading(val info: UpdateInfo, val progress: Float) : UpdateState()
    data class Ready(val info: UpdateInfo, val file: File) : UpdateState()
    data class Failed(val message: String) : UpdateState()
}

object Updater {
    val state = MutableStateFlow<UpdateState>(UpdateState.None)

    private fun currentCode(): Long = try {
        Store.ctx.packageManager.getPackageInfo(Store.ctx.packageName, 0).longVersionCode
    } catch (e: Exception) { 0 }

    suspend fun check() = withContext(Dispatchers.IO) {
        try {
            val c = URL(Pinned.UPDATE_URL).openConnection() as HttpURLConnection
            c.connectTimeout = 10000; c.readTimeout = 10000
            c.setRequestProperty("Cache-Control", "no-cache")
            if (c.responseCode != 200) return@withContext
            val o = JSONObject(c.inputStream.bufferedReader().readText())
            val mine = android.os.Build.SUPPORTED_ABIS.firstNotNullOfOrNull { abi -> o.optJSONObject("abis")?.optJSONObject(abi) }
            val info = UpdateInfo(o.getLong("versionCode"), o.optString("versionName"),
                mine?.optString("url") ?: o.getString("url"), mine?.optString("sha256") ?: o.optString("sha256"), o.optString("notes"))
            if (info.versionCode > currentCode()) {
                if (state.value is UpdateState.None || state.value is UpdateState.Failed) state.value = UpdateState.Available(info)
                TunnelLog.log("есть обновление ${info.versionName} (${info.versionCode})")
            }
        } catch (e: Exception) {
            TunnelLog.log("проверка обновлений: ${e.message}")
        }
    }

    suspend fun download(info: UpdateInfo) = withContext(Dispatchers.IO) {
        try {
            val dir = File(Store.ctx.cacheDir, "updates").apply { mkdirs() }
            val file = File(dir, "bypen-${info.versionCode}.apk")
            val c = URL(info.url).openConnection() as HttpURLConnection
            c.connectTimeout = 15000; c.readTimeout = 30000
            val total = c.contentLengthLong
            val md = MessageDigest.getInstance("SHA-256")
            c.inputStream.use { inp -> file.outputStream().use { out ->
                val buf = ByteArray(64 * 1024); var done = 0L
                while (true) {
                    val r = inp.read(buf); if (r < 0) break
                    out.write(buf, 0, r); md.update(buf, 0, r); done += r
                    state.value = UpdateState.Downloading(info, if (total > 0) done.toFloat() / total else 0f)
                }
            } }
            val sum = md.digest().joinToString("") { "%02x".format(it) }
            if (info.sha256.isNotEmpty() && !sum.equals(info.sha256, ignoreCase = true)) {
                file.delete(); state.value = UpdateState.Failed("Файл обновления повреждён (сумма не сходится)"); return@withContext
            }
            state.value = UpdateState.Ready(info, file)
        } catch (e: Exception) {
            state.value = UpdateState.Failed("Не скачалось: ${e.message}")
        }
    }

    fun install(ctx: Context, file: File) {
        val uri = FileProvider.getUriForFile(ctx, "com.hyax.bypen.files", file)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }
}
