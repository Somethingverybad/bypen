// Состояние туннеля для экрана: служба пишет, интерфейс наблюдает.
package com.hyax.bypen

import kotlinx.coroutines.flow.MutableStateFlow

enum class State { STOPPED, STARTING, CONNECTED, SWITCHING, ERROR }

data class TunnelStatus(
    val state: State = State.STOPPED,
    val nodeId: String? = null,
    val nodeName: String? = null,
    val since: Long? = null,
    val up: Long = 0,
    val down: Long = 0,
    val lastProbeMs: Int? = null,
    val failures: Int = 0,
    val switches: Int = 0,
    val lastError: String? = null,
    val xrayVersion: String? = null,
)

object TunnelState {
    val status = MutableStateFlow(TunnelStatus())
    val running get() = status.value.state != State.STOPPED
}
