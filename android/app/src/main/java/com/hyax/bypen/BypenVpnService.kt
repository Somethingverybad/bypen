// Служба VPN «Бупень»: весь трафик телефона → tun → hev-socks5-tunnel → локальный socks
// Xray → VLESS (Reality / XHTTP) на выбранный узел. Логика живости и переключения та же,
// что в расширении iOS: проверка через сам туннель (Health), после старта раз в 3 с,
// потом раз в 20 с; 3 провала подряд (2 до первого успеха) — следующий узел.
package com.hyax.bypen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import hev.htproxy.TProxyService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import libXray.DialerController
import libXray.LibXray

class BypenVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.hyax.bypen.START"
        const val ACTION_STOP = "com.hyax.bypen.STOP"
        const val ACTION_SWITCH = "com.hyax.bypen.SWITCH"
        const val ACTION_PROBE = "com.hyax.bypen.PROBE"
        const val EXTRA_NODE = "node"
        private const val NOTIF_ID = 1
        private const val CHANNEL = "vpn"

        fun send(ctx: Context, action: String, node: String? = null) {
            val i = Intent(ctx, BypenVpnService::class.java).setAction(action)
            if (node != null) i.putExtra(EXTRA_NODE, node)
            if (action == ACTION_START) ctx.startForegroundService(i) else ctx.startService(i)
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val lock = Mutex()
    private var pfd: ParcelFileDescriptor? = null
    private var profile: VpnProfile? = null
    private var settings = TunnelSettings()
    private var order: List<VpnNode> = emptyList()
    private var current: VpnNode? = null
    private var status = TunnelStatus()

    private var generation = 0
    private var stopping = false
    private var probeJob: Job? = null
    private var probeAttempt = 0
    private var failures = 0
    private var okOnThisNode = false
    private var lastOkReport = 0L
    private var lastOkLog = 0L
    private var connectedAt = 0L
    private val failedRecently = HashMap<String, Long>()
    private val samples = ArrayList<Pair<Long, Long>>()
    private var netCallback: ConnectivityManager.NetworkCallback? = null

    private val controller = DialerController { fd -> protect(fd.toInt()) }

    override fun onCreate() {
        super.onCreate()
        TunnelLog.tag = "tun"
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "VPN", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action ?: ACTION_START) {
            ACTION_START -> {
                if (TunnelState.running) return START_NOT_STICKY
                startForeground(NOTIF_ID, notification("Подключаю…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                val node = intent?.getStringExtra(EXTRA_NODE)
                scope.launch { lock.withLock { startTunnel(node) } }
            }
            ACTION_STOP -> scope.launch { lock.withLock { stopTunnel("по кнопке") } }
            ACTION_SWITCH -> scope.launch { lock.withLock { switchNode(intent?.getStringExtra(EXTRA_NODE), "по команде из приложения") } }
            ACTION_PROBE -> scheduleProbe(0)
        }
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        scope.launch { lock.withLock { stopTunnel("отозвано системой") } }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    // MARK: старт / стоп

    private fun startTunnel(preferredFromApp: String?) {
        val ver = XrayCore.version
        TunnelLog.log("старт туннеля, Xray $ver")
        settings = TunnelSettings.load()
        val p = VpnProfile.loadSaved()
        if (p == null || p.nodes.isEmpty()) {
            TunnelLog.log("нет профиля — откройте приложение, чтобы получить список узлов")
            fail("Нет профиля — откройте приложение"); return
        }
        profile = p
        order = p.order(preferredFromApp ?: settings.preferredNode)
        status = TunnelStatus(state = State.STARTING, xrayVersion = ver); publish()

        val fd = try {
            Builder().setSession("Бупень").setMtu(XrayConfig.TUN_MTU)
                .addAddress("198.18.0.1", 24).addAddress("fd00:7779:7878::2", 64)
                .addRoute("0.0.0.0", 0).addRoute("::", 0)
                .addDnsServer("1.1.1.1").addDnsServer("8.8.8.8")
                .addDisallowedApplication(packageName)   // само приложение — мимо туннеля (отчёты и профиль дойдут всегда)
                .setMetered(false).setBlocking(false)
                .establish()
        } catch (e: Exception) { TunnelLog.log("tun не поднялся: ${e.message}"); null }
        if (fd == null) { fail("Система не дала поднять VPN"); return }
        pfd = fd

        LibXray.registerDialerController(controller)
        try { LibXray.setDNS(controller, "1.1.1.1:53") } catch (e: Exception) { TunnelLog.log("setDNS: ${e.message}") }
        val node = startFirstAvailable()
        if (node == null) { fail("Ни один узел не запустился"); return }

        Store.tun2socksFile.writeText(XrayConfig.tun2socksYAML)
        if (!TProxyService.TProxyStartService(Store.tun2socksFile.absolutePath, fd.fd)) {
            TunnelLog.log("tun2socks не запустился"); fail("tun2socks не запустился"); return
        }
        became(node)
        scheduleProbe(1500)
        watchNetwork()
    }

    private fun fail(message: String) {
        TunnelLog.log(message)
        cleanup()
        status = status.copy(state = State.ERROR, lastError = message); publish()
        status = TunnelStatus(state = State.STOPPED, lastError = message); publish()
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }

    private fun stopTunnel(reason: String) {
        if (!TunnelState.running) return
        stopping = true
        TunnelLog.log("остановка туннеля ($reason)")
        cleanup()
        status = TunnelStatus(state = State.STOPPED); publish()
        stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }

    private fun cleanup() {
        probeJob?.cancel()
        netCallback?.let { try { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } catch (e: Exception) {} }
        netCallback = null
        try { TProxyService.TProxyStopService() } catch (e: Throwable) {}
        XrayCore.stop()
        try { LibXray.resetDNS() } catch (e: Throwable) {}
        try { pfd?.close() } catch (e: Exception) {}
        pfd = null
    }

    // MARK: узлы

    private fun startFirstAvailable(): VpnNode? {
        val p = profile ?: return null
        for (node in order) {
            val err = XrayCore.run(XrayConfig.build(node, p.user.uuid))
            if (err != null) {
                TunnelLog.log("узел ${node.name}: ядро не запустилось — $err")
                Events.append(node.id, false, error = "start: ${err.take(150)}", net = netKind())
                XrayCore.stop(); continue
            }
            TunnelLog.log("узел ${node.name} (${node.kind}, ${node.dialAddress}:${node.port}) — ядро запущено")
            return node
        }
        return null
    }

    private fun became(node: VpnNode) {
        current = node
        connectedAt = System.currentTimeMillis()
        okOnThisNode = false; failures = 0; probeAttempt = 0; samples.clear()
        status = status.copy(state = State.CONNECTED, nodeId = node.id, nodeName = node.name, since = connectedAt, failures = 0, lastProbeMs = null)
        publish()
    }

    private fun switchNode(id: String?, reason: String) {
        if (!TunnelState.running) return
        VpnProfile.loadSaved()?.let { profile = it }
        val p = profile ?: return
        settings = TunnelSettings.load()
        val cur = current
        val candidates: List<VpnNode> = if (id != null) {
            p.nodes.filter { it.id == id }.ifEmpty { TunnelLog.log("узла $id нет в профиле"); return }
        } else {
            val now = System.currentTimeMillis()
            p.nodes.filter { it.id != cur?.id }.withIndex().sortedWith(compareBy(
                { failedRecently[it.value.id]?.let { t -> now - t < 600_000 } ?: false },
                { !it.value.ok }, { it.index },
            )).map { it.value }
        }
        if (candidates.isEmpty()) { TunnelLog.log("переключаться некуда: других узлов нет"); return }

        generation++
        probeJob?.cancel()
        status = status.copy(state = State.SWITCHING); publish()
        if (cur != null && !reason.contains("команде") && !reason.contains("ротация")) failedRecently[cur.id] = System.currentTimeMillis()
        XrayCore.stop()
        for (next in candidates) {
            val err = XrayCore.run(XrayConfig.build(next, p.user.uuid))
            if (err != null) { TunnelLog.log("узел ${next.name}: ядро не запустилось — $err"); failedRecently[next.id] = System.currentTimeMillis(); XrayCore.stop(); continue }
            TunnelLog.log("переключение: ${cur?.name ?: "—"} → ${next.name} ($reason)")
            status = status.copy(switches = status.switches + 1)
            became(next)
            scheduleProbe(1500)
            return
        }
        if (cur != null && XrayCore.run(XrayConfig.build(cur, p.user.uuid)) == null) {
            TunnelLog.log("остаёмся на ${cur.name}: другие узлы не запустились"); became(cur)
        } else {
            status = status.copy(state = State.ERROR, lastError = "Ни один узел не запустился"); publish()
        }
        scheduleProbe(5000)
    }

    // MARK: проверка связи

    private fun scheduleProbe(delayMs: Long) {
        if (stopping) return
        probeJob?.cancel()
        probeJob = scope.launch {
            delay(delayMs)
            val node = current ?: return@launch
            val gen = generation
            val r = Health.probe(XrayConfig.SOCKS_PORT, probeAttempt)
            lock.withLock { if (gen == generation && !stopping) handleProbe(r, node) }
        }
    }

    private fun handleProbe(r: Health.Result, node: VpnNode) {
        refreshTraffic()
        val now = System.currentTimeMillis()
        if (r.ok) {
            val first = !okOnThisNode
            okOnThisNode = true; failures = 0; probeAttempt = 0
            failedRecently.remove(node.id)
            status = status.copy(state = State.CONNECTED, lastProbeMs = r.ms, failures = 0, lastError = null)
            if (first || now - lastOkLog > 600_000) {
                TunnelLog.log("связь через ${node.name}: ${r.ms} мс, ↑${fmt(status.up)} ↓${fmt(status.down)}"); lastOkLog = now
            }
            if (first || now - lastOkReport > 300_000) { Events.append(node.id, true, r.ms, net = netKind()); lastOkReport = now }
            publish()
            if (!maybeRotateIdle()) scheduleProbe(20_000)
        } else {
            failures++; probeAttempt++
            status = status.copy(failures = failures, lastError = r.error)
            TunnelLog.log("проверка через ${node.name} не прошла ($failures): ${r.error}")
            val threshold = if (okOnThisNode) 3 else 2
            if (failures >= threshold) {
                Events.append(node.id, false, error = r.error?.take(150), net = netKind())
                if (settings.autoSwitch && (profile?.nodes?.size ?: 0) > 1 && online()) {
                    switchNode(null, "узел не отвечает")
                } else {
                    status = status.copy(state = State.ERROR); publish(); scheduleProbe(10_000)
                }
            } else {
                publish(); scheduleProbe(if (okOnThisNode) 5000 else 3000)
            }
        }
    }

    private fun maybeRotateIdle(): Boolean {
        val p = profile ?: return false; val cur = current ?: return false
        if (!settings.rotateIdle || connectedAt == 0L) return false
        val now = System.currentTimeMillis()
        if (now - connectedAt < settings.rotateMinutes * 60_000L) return false
        val old = samples.firstOrNull { now - it.first >= 600_000 } ?: return false
        val last = samples.last()
        if (last.second - old.second >= 300 * 1024) return false
        if (p.nodes.none { it.id != cur.id && it.ok }) return false
        switchNode(null, "ротация в простое")
        return true
    }

    private fun refreshTraffic() {
        val st = try { TProxyService.TProxyGetStats() } catch (e: Throwable) { null }
        if (st != null && st.size >= 4) {
            status = status.copy(up = st[1], down = st[3])
            samples.add(System.currentTimeMillis() to (st[1] + st[3]))
            if (samples.size > 60) samples.removeAt(0)
        }
    }

    // MARK: сеть и уведомление

    private val cm get() = getSystemService(ConnectivityManager::class.java)

    private fun online(): Boolean = cm.activeNetwork != null

    private fun netKind(): String {
        val caps = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) } ?: return ""
        return if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) "cell" else "wifi"
    }

    private fun watchNetwork() {
        val req = NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { TunnelLog.log("сеть: появилась (${netKind()})"); scheduleProbe(3000) }
            override fun onLost(network: Network) { TunnelLog.log("сеть: пропала") }
        }
        netCallback = cb
        try { cm.registerNetworkCallback(req, cb) } catch (e: Exception) {}
    }

    private fun publish() {
        TunnelState.status.value = status
        if (TunnelState.running) {
            val text = when (status.state) {
                State.CONNECTED -> if (status.lastProbeMs != null) "Защищено · ${status.nodeName}" else "Проверяю связь · ${status.nodeName}"
                State.SWITCHING -> "Меняю узел…"
                State.ERROR -> "Нет ответа от узла"
                else -> "Подключаю…"
            }
            getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification(text))
        }
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, com.hyax.bypen.ui.MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, BypenVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Бупень").setContentText(text).setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Отключить", stop).build())
            .build()
    }

    private fun fmt(b: Long): String = when {
        b >= 1 shl 30 -> "%.1f ГБ".format(b / 1073741824.0)
        b >= 1 shl 20 -> "%.1f МБ".format(b / 1048576.0)
        else -> "${b / 1024} КБ"
    }
}
