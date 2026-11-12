// Конфигурация Xray для одного узла: socks-вход для tun2socks и VLESS-выход
// (Reality или XHTTP). Без geoip/geosite — файлов данных нет, частные сети явно.
package com.hyax.bypen

import org.json.JSONArray
import org.json.JSONObject

object XrayConfig {
    const val SOCKS_PORT = 10808

    private val privateNets = listOf(
        "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16",
        "100.64.0.0/10", "224.0.0.0/4", "fc00::/7", "fe80::/10", "ff00::/8",
    )

    private fun obj(vararg pairs: Pair<String, Any?>) = JSONObject().apply { pairs.forEach { (k, v) -> put(k, v) } }
    private fun arr(vararg items: Any?) = JSONArray().apply { items.forEach { put(it) } }

    fun build(node: VpnNode, uuid: String): String {
        val user = obj("id" to uuid, "encryption" to "none")
        if (!node.flow.isNullOrEmpty()) user.put("flow", node.flow)
        val stream = if (node.isReality) obj(
            "network" to "tcp", "security" to "reality",
            "realitySettings" to obj(
                "serverName" to node.sni, "fingerprint" to (node.fp ?: "chrome"),
                "publicKey" to (node.pbk ?: ""), "shortId" to (node.sid ?: ""), "spiderX" to "/",
            ),
        ) else obj(
            "network" to "xhttp", "security" to "tls",
            "tlsSettings" to obj("serverName" to node.sni, "alpn" to JSONArray(node.alpn ?: listOf("h2")), "fingerprint" to (node.fp ?: "chrome")),
            "xhttpSettings" to obj("host" to node.host, "path" to (node.path ?: "/"), "mode" to (node.mode ?: "auto")),
        )
        stream.put("sockopt", obj("tcpKeepAliveInterval" to 30))

        return obj(
            "log" to obj("loglevel" to "warning", "error" to Store.xrayLogFile.absolutePath),
            "inbounds" to arr(obj(
                "tag" to "socks", "listen" to "127.0.0.1", "port" to SOCKS_PORT, "protocol" to "socks",
                "settings" to obj("auth" to "noauth", "udp" to true),
                "sniffing" to obj("enabled" to true, "destOverride" to arr("http", "tls", "quic"), "routeOnly" to false),
            )),
            "outbounds" to arr(
                obj(
                    "tag" to "proxy", "protocol" to "vless",
                    "settings" to obj("vnext" to arr(obj("address" to node.dialAddress, "port" to node.port, "users" to arr(user)))),
                    "streamSettings" to stream,
                ),
                obj("tag" to "direct", "protocol" to "freedom"),
                obj("tag" to "block", "protocol" to "blackhole"),
            ),
            "routing" to obj(
                "domainStrategy" to "AsIs",
                "rules" to arr(
                    obj("type" to "field", "ip" to JSONArray(privateNets), "outboundTag" to "direct"),
                    obj("type" to "field", "network" to "tcp,udp", "outboundTag" to "proxy"),
                ),
            ),
        ).toString()
    }

    const val TUN_MTU = 1500

    val tun2socksYAML = """
        tunnel:
          mtu: $TUN_MTU
          ipv4: 198.18.0.1
          ipv6: 'fd00:7779:7878::2'
        socks5:
          port: $SOCKS_PORT
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 24576
          tcp-buffer-size: 4096
          max-session-count: 1024
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stderr
          log-level: warn
          limit-nofile: 65535
    """.trimIndent()
}
