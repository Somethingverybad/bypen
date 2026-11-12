// Состояние приложения: вход, профиль узлов (проверенный подписью), туннель, отчёты, обновления.
package com.hyax.bypen

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class AppModel : ViewModel() {
    var loggedIn by mutableStateOf(Api.isLoggedIn)
    var username by mutableStateOf(Api.username)
    var profile by mutableStateOf(VpnProfile.loadSaved())
    var profileNote by mutableStateOf<String?>(null)
    var settings by mutableStateOf(TunnelSettings.load())
    var status by mutableStateOf(TunnelState.status.value)
    var update by mutableStateOf<UpdateState>(UpdateState.None)
    var busy by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    private var lastProfileFetch = 0L
    private var lastProfileError: Pair<String?, Long> = null to 0L

    /** Одна и та же ошибка профиля чаще раза в минуту в журнал не пишется (шум при каждом открытии). */
    private fun noteProfileError(msg: String?) {
        error = msg
        val (prev, at) = lastProfileError
        if (msg != prev || System.currentTimeMillis() - at > 60_000) TunnelLog.log("профиль не обновлён: $msg")
        lastProfileError = msg to System.currentTimeMillis()
    }

    init {
        viewModelScope.launch { TunnelState.status.collect { status = it } }
        viewModelScope.launch { Updater.state.collect { update = it } }
    }

    fun bootstrap() = viewModelScope.launch {
        if (!loggedIn) return@launch
        refreshProfile(false); uploadEvents(); Updater.check()
    }

    fun updateSettings(s: TunnelSettings) { settings = s; s.save() }

    fun login(u: String, p: String) = viewModelScope.launch {
        busy = true; error = null
        try {
            Api.login(u.trim(), p)
            username = Api.username; loggedIn = true
            TunnelLog.log("вход: $u")
            refreshProfile(true)
        } catch (e: Exception) { error = e.message } finally { busy = false }
    }

    fun logout() {
        if (TunnelState.running) BypenVpnService.send(Store.ctx, BypenVpnService.ACTION_STOP)
        Api.logout(); Store.profileFile.delete()
        profile = null; loggedIn = false; username = null
        TunnelLog.log("выход")
    }

    suspend fun refreshProfile(force: Boolean) {
        if (!loggedIn) return
        val p = profile
        if (!force && p != null && System.currentTimeMillis() - lastProfileFetch < p.ttl * 1000L) return
        try {
            val s = Api.fetchProfile()
            val warning = Signature.verify(s.payload, s.sig, s.pub)
            val decoded = VpnProfile.decode(s.payload)
            Store.profileFile.writeText(s.payload)
            profile = decoded; profileNote = warning; lastProfileFetch = System.currentTimeMillis(); error = null
            TunnelLog.log("профиль обновлён: узлов ${decoded.nodes.size}, живых ${decoded.nodes.count { it.ok }}" + (warning?.let { "; $it" } ?: ""))
        } catch (e: ApiError) {
            if (e.unauthorized) logout()
            noteProfileError(e.message)
        } catch (e: Exception) {
            noteProfileError(e.message)
        }
    }

    fun refresh() = viewModelScope.launch { refreshProfile(true) }

    /** Запуск службы; разрешение на VPN запрашивает Activity до вызова. */
    fun connect(nodeId: String? = null) = viewModelScope.launch {
        error = null
        if (profile == null) refreshProfile(true)
        val p = profile
        if (p == null || p.nodes.isEmpty()) { if (error == null) error = "Нет узлов — доступ к сети WYX не выдан?"; return@launch }
        TunnelLog.log("подключение" + (nodeId?.let { " к $it" } ?: ""))
        BypenVpnService.send(Store.ctx, BypenVpnService.ACTION_START, nodeId ?: settings.preferredNode)
    }

    fun disconnect() { TunnelLog.log("отключение по кнопке"); BypenVpnService.send(Store.ctx, BypenVpnService.ACTION_STOP) }

    fun select(node: VpnNode, onNeedConnect: () -> Unit) {
        updateSettings(settings.copy(preferredNode = node.id))
        if (TunnelState.running) BypenVpnService.send(Store.ctx, BypenVpnService.ACTION_SWITCH, node.id) else onNeedConnect()
    }

    suspend fun uploadEvents() {
        if (!loggedIn) return
        val (events, consumed) = Events.take()
        if (events.isEmpty()) { if (consumed > 0) Events.drop(consumed); return }
        try {
            var sent = 0
            events.chunked(200).forEach { sent += Api.report(it) }
            Events.drop(consumed)
            TunnelLog.log("отчёты отправлены: $sent")
        } catch (e: Exception) { TunnelLog.log("отчёты не отправлены: ${e.message}") }
    }

    fun onResume() = viewModelScope.launch { if (loggedIn) { refreshProfile(false); uploadEvents(); Updater.check() } }

    fun downloadUpdate(info: UpdateInfo) = viewModelScope.launch { Updater.download(info) }
}
