// Профиль «Сети WYX» — GET /api/vpn/profile/ (hyax backend/chat/vpn.py): строка JSON,
// подписанная Ed25519, хранится как есть в profile.json.
package com.hyax.bypen

import org.json.JSONObject

data class VpnNode(
    val id: String, val name: String, val kind: String, val host: String, val port: Int, val sni: String,
    val ips: List<String>, val weight: Int, val ok: Boolean, val rttMs: Int?,
    val pbk: String?, val sid: String?, val fp: String?, val flow: String?,
    val path: String?, val mode: String?, val alpn: List<String>?,
) {
    val dialAddress get() = ips.firstOrNull() ?: host
    val isReality get() = kind == "reality"

    companion object {
        fun from(o: JSONObject) = VpnNode(
            id = o.getString("id"), name = o.getString("name"), kind = o.getString("kind"),
            host = o.getString("host"), port = o.getInt("port"), sni = o.optString("sni", o.getString("host")),
            ips = o.optJSONArray("ips")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
            weight = o.optInt("weight", 10), ok = o.optBoolean("ok", false),
            rttMs = if (o.isNull("rtt_ms")) null else o.optInt("rtt_ms"),
            pbk = o.optString("pbk", null), sid = o.optString("sid", null), fp = o.optString("fp", null),
            flow = o.optString("flow", null), path = o.optString("path", null), mode = o.optString("mode", null),
            alpn = o.optJSONArray("alpn")?.let { a -> (0 until a.length()).map { a.getString(it) } },
        )
    }
}

data class VpnUser(val id: String, val username: String, val uuid: String, val email: String)

data class VpnProfile(val issuedAt: String, val ttl: Int, val user: VpnUser, val nodes: List<VpnNode>) {
    /** Порядок попыток: выбранный вручную первым, дальше как отдал сервер (живые первыми). */
    fun order(preferred: String?): List<VpnNode> {
        val i = nodes.indexOfFirst { it.id == preferred }
        if (i < 0) return nodes
        return listOf(nodes[i]) + nodes.filterIndexed { j, _ -> j != i }
    }

    companion object {
        fun decode(text: String): VpnProfile {
            val o = JSONObject(text)
            val u = o.getJSONObject("user")
            val arr = o.getJSONArray("nodes")
            return VpnProfile(
                issuedAt = o.optString("issued_at"), ttl = o.optInt("ttl", 300),
                user = VpnUser(u.getString("id"), u.getString("username"), u.getString("uuid"), u.optString("email")),
                nodes = (0 until arr.length()).map { VpnNode.from(arr.getJSONObject(it)) },
            )
        }

        fun loadSaved(): VpnProfile? = try {
            if (Store.profileFile.exists()) decode(Store.profileFile.readText()) else null
        } catch (e: Exception) { null }
    }
}
