// Файлы и настройки приложения (аналог App Group на iOS): профиль узлов, журнал,
// события для сервера. Служба VPN живёт в том же процессе, читает отсюда же.
package com.hyax.bypen

import android.content.Context
import android.content.SharedPreferences
import java.io.File

object Store {
    lateinit var ctx: Context
    fun init(c: Context) { ctx = c.applicationContext }

    val prefs: SharedPreferences get() = ctx.getSharedPreferences("bypen", Context.MODE_PRIVATE)
    val profileFile: File get() = File(ctx.filesDir, "profile.json")
    val logFile: File get() = File(ctx.filesDir, "tunnel.log")
    val xrayLogFile: File get() = File(ctx.filesDir, "xray.log")
    val eventsFile: File get() = File(ctx.filesDir, "events.jsonl")
    val tun2socksFile: File get() = File(ctx.filesDir, "tun2socks.yml")
}

data class TunnelSettings(
    val autoSwitch: Boolean = true,
    val rotateIdle: Boolean = true,
    val rotateMinutes: Int = 60,
    val preferredNode: String? = null,
    val appearance: String = "dark",
) {
    fun save() = Store.prefs.edit()
        .putBoolean("autoSwitch", autoSwitch).putBoolean("rotateIdle", rotateIdle)
        .putInt("rotateMinutes", rotateMinutes).putString("preferredNode", preferredNode)
        .putString("appearance", appearance).putInt("settingsV", 2).apply()

    companion object {
        fun load(): TunnelSettings = Store.prefs.let {
            TunnelSettings(
                // до версии 2 выключенная ротация была просто прежним значением по умолчанию — включаем один раз
                it.getBoolean("autoSwitch", true), if (it.getInt("settingsV", 1) < 2) true else it.getBoolean("rotateIdle", true),
                it.getInt("rotateMinutes", 60), it.getString("preferredNode", null),
                it.getString("appearance", "dark") ?: "dark",
            )
        }
    }
}
