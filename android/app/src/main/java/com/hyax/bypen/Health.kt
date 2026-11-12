// Проверка связи через сам туннель: SOCKS5 к локальному входу Xray → HTTP на страницу «204».
package com.hyax.bypen

import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

object Health {
    data class Result(val ok: Boolean, val ms: Int, val error: String?)

    private val targets = listOf(
        "connectivitycheck.gstatic.com" to "/generate_204",
        "cp.cloudflare.com" to "/",
        "www.google.com" to "/generate_204",
    )

    private fun readFully(input: InputStream, n: Int): ByteArray {
        val buf = ByteArray(n); var off = 0
        while (off < n) { val r = input.read(buf, off, n - off); if (r < 0) throw Exception("соединение закрыто"); off += r }
        return buf
    }

    fun probe(socksPort: Int, attempt: Int, timeoutMs: Int = 8000): Result {
        val (host, path) = targets[attempt % targets.size]
        val t0 = System.currentTimeMillis()
        try {
            Socket().use { s ->
                s.soTimeout = timeoutMs
                s.connect(InetSocketAddress("127.0.0.1", socksPort), 3000)
                val out = s.getOutputStream(); val inp = s.getInputStream()
                out.write(byteArrayOf(5, 1, 0)); out.flush()
                val m = readFully(inp, 2)
                if (m[1] != 0.toByte()) return Result(false, 0, "socks: метод отвергнут")
                val h = host.toByteArray()
                out.write(byteArrayOf(5, 1, 0, 3, h.size.toByte()) + h + byteArrayOf(0, 80)); out.flush()
                val head = readFully(inp, 4)
                if (head[1] != 0.toByte()) return Result(false, 0, "socks: отказ ${head[1]} ($host)")
                when (head[3].toInt()) { 1 -> readFully(inp, 6); 4 -> readFully(inp, 18); else -> { val l = readFully(inp, 1)[0].toInt() and 0xff; readFully(inp, l + 2) } }
                out.write("GET $path HTTP/1.1\r\nHost: $host\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n".toByteArray()); out.flush()
                val buf = ByteArray(256)
                val r = inp.read(buf)
                val line = if (r > 0) String(buf, 0, r) else ""
                val code = if (line.startsWith("HTTP/1.") && line.length >= 12) line.substring(9, 12).toIntOrNull() else null
                val ms = (System.currentTimeMillis() - t0).toInt()
                return if (code != null && code < 500) Result(true, ms, null) else Result(false, ms, "http: ${line.take(40)}")
            }
        } catch (e: Exception) {
            return Result(false, (System.currentTimeMillis() - t0).toInt(), "${e.javaClass.simpleName}: ${e.message} ($host)")
        }
    }
}
