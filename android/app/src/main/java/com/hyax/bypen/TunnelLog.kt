// Журнал для пользователя: строка на событие, с обрезкой; экран «Журнал» читает файл.
package com.hyax.bypen

import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object TunnelLog {
    @Volatile var tag = "app"
    private const val MAX = 400 * 1024
    private val fmt = SimpleDateFormat("dd.MM HH:mm:ss", Locale("ru"))
    private val lock = Any()

    fun log(message: String) {
        Log.i("bypen", message)
        val line = "${fmt.format(Date())} [$tag] $message\n"
        synchronized(lock) {
            try {
                val f = Store.logFile
                f.appendText(line)
                if (f.length() > MAX) {
                    val bytes = f.readBytes()
                    var tail = bytes.copyOfRange(bytes.size - MAX / 2, bytes.size)
                    val nl = tail.indexOf('\n'.code.toByte())
                    if (nl >= 0) tail = tail.copyOfRange(nl + 1, tail.size)
                    f.writeBytes(tail)
                }
            } catch (e: Exception) { /* журнал не важнее работы */ }
        }
    }

    fun read(): String = synchronized(lock) { try { Store.logFile.readText() } catch (e: Exception) { "" } }
    fun readXray(): String = try { Store.xrayLogFile.readText().takeLast(6000) } catch (e: Exception) { "" }
    fun clear() = synchronized(lock) { Store.logFile.writeText(""); Store.xrayLogFile.writeText("") }
}

/** Отчёт для POST /api/vpn/report/ — только здоровье узла. */
object Events {
    private val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
    private val lock = Any()

    fun append(node: String?, ok: Boolean, rttMs: Int? = null, error: String? = null, net: String? = null) {
        val o = org.json.JSONObject()
        o.put("node", node); o.put("ok", ok); o.put("rtt_ms", rttMs); o.put("error", error); o.put("net", net)
        o.put("at", iso.format(Date()))
        synchronized(lock) { try { Store.eventsFile.appendText(o.toString() + "\n") } catch (e: Exception) {} }
    }

    /** Забрать накопленное; вернуть (строки, сколько байт прочитано). */
    fun take(): Pair<List<org.json.JSONObject>, Long> = synchronized(lock) {
        val f = Store.eventsFile
        if (!f.exists()) return emptyList<org.json.JSONObject>() to 0L
        val bytes = f.readBytes()
        val list = String(bytes).split('\n').filter { it.isNotBlank() }.mapNotNull { try { org.json.JSONObject(it) } catch (e: Exception) { null } }
        list to bytes.size.toLong()
    }

    fun drop(consumed: Long) = synchronized(lock) {
        val f = Store.eventsFile
        if (!f.exists()) return
        val bytes = f.readBytes()
        if (bytes.size >= consumed) f.writeBytes(bytes.copyOfRange(consumed.toInt(), bytes.size))
    }
}
