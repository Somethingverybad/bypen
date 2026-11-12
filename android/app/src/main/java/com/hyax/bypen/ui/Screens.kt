package com.hyax.bypen.ui

import android.content.Intent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hyax.bypen.Api
import com.hyax.bypen.AppModel
import com.hyax.bypen.State
import com.hyax.bypen.TunnelLog
import com.hyax.bypen.TunnelState
import com.hyax.bypen.UpdateState
import com.hyax.bypen.Updater
import com.hyax.bypen.VpnNode
import kotlinx.coroutines.delay

// MARK: вход

@Composable
fun LoginScreen(model: AppModel, t: Theme) {
    var u by remember { mutableStateOf("") }
    var p by remember { mutableStateOf("") }
    GlassBackground(t, false) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("WYX", color = t.text, fontSize = 52.sp, fontWeight = FontWeight.Black, letterSpacing = (-2).sp)
            Text("сеть", color = t.muted, fontSize = 18.sp)
            Spacer(Modifier.height(24.dp))
            Column(Modifier.fillMaxWidth().glassCard(t, 24).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                val colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = t.text, unfocusedTextColor = t.text, cursorColor = t.primary,
                    focusedBorderColor = t.primary, unfocusedBorderColor = t.border,
                    focusedContainerColor = t.surface.copy(alpha = 0.6f), unfocusedContainerColor = t.surface.copy(alpha = 0.6f),
                    focusedPlaceholderColor = t.muted, unfocusedPlaceholderColor = t.muted,
                )
                OutlinedTextField(u, { u = it }, Modifier.fillMaxWidth(), placeholder = { Text("Ник или почта") }, singleLine = true, colors = colors, shape = RoundedCornerShape(12.dp))
                OutlinedTextField(p, { p = it }, Modifier.fillMaxWidth(), placeholder = { Text("Пароль") }, singleLine = true, colors = colors, shape = RoundedCornerShape(12.dp),
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                model.error?.let { Text(it, color = t.destructive, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                Button(onClick = { model.login(u, p) }, enabled = u.isNotBlank() && p.isNotBlank() && !model.busy, modifier = Modifier.fillMaxWidth().height(50.dp),
                    shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.buttonColors(containerColor = t.primary, contentColor = t.primaryForeground, disabledContainerColor = t.primary.copy(alpha = 0.5f), disabledContentColor = t.primaryForeground.copy(alpha = 0.7f))) {
                    if (model.busy) CircularProgressIndicator(Modifier.size(18.dp), color = t.primaryForeground, strokeWidth = 2.dp)
                    else Text("Войти", fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(16.dp))
            Text("Аккаунт тот же, что в мессенджере. Доступ к сети выдаётся отдельно.", color = t.muted, fontSize = 13.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(32.dp))
            Text("Бупень ${Api.version}", color = t.muted.copy(alpha = 0.6f), fontSize = 11.sp)
        }
    }
}

// MARK: главный

private enum class Phase { OFF, BUSY, CHECKING, ON, TROUBLE }

@Composable
fun MainScreen(model: AppModel, t: Theme, activity: MainActivity, onLog: () -> Unit, onSettings: () -> Unit) {
    val st = model.status
    val phase = when (st.state) {
        State.STOPPED -> Phase.OFF
        State.STARTING, State.SWITCHING -> Phase.BUSY
        State.ERROR -> Phase.TROUBLE
        State.CONNECTED -> if (st.failures > 0) Phase.TROUBLE else if (st.lastProbeMs == null) Phase.CHECKING else Phase.ON
    }
    val title = when (phase) {
        Phase.OFF -> "Подключить"; Phase.BUSY -> if (st.state == State.SWITCHING) "Меняю узел…" else "Подключаю…"
        Phase.CHECKING -> "Проверяю…"; Phase.ON -> "Защищено"; Phase.TROUBLE -> "Нет ответа"
    }
    val glow = when (phase) { Phase.OFF -> Color.Transparent; Phase.BUSY, Phase.CHECKING -> t.accent.copy(alpha = 0.35f); Phase.ON -> t.accent; Phase.TROUBLE -> t.destructive }
    val on = phase == Phase.ON
    val working = phase == Phase.BUSY || phase == Phase.CHECKING

    val anim = rememberInfiniteTransition(label = "pulse")
    val breathe by anim.animateFloat(0.96f, 1.08f, infiniteRepeatable(tween(2600), RepeatMode.Reverse), label = "b")
    val ring by anim.animateFloat(0.95f, 1.35f, infiniteRepeatable(tween(1800)), label = "r")
    val glowAlpha by animateFloatAsState(if (phase == Phase.OFF) 0f else 0.55f, tween(500), label = "ga")

    GlassBackground(t, on) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 20.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                GlassIcon(t, Icons.Filled.Description, onLog)
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("WYX", color = t.text, fontSize = 22.sp, fontWeight = FontWeight.Black, letterSpacing = (-1).sp)
                    Text("сеть", color = t.muted, fontSize = 12.sp)
                }
                Spacer(Modifier.weight(1f))
                GlassIcon(t, Icons.Filled.Settings, onSettings)
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.align(Alignment.CenterHorizontally).size(290.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.size(250.dp).scale(if (on) breathe else 1f).blur(40.dp).background(glow.copy(alpha = glow.alpha * glowAlpha), CircleShape))
                if (working) Box(Modifier.size(250.dp).scale(ring).border1(t.accent.copy(alpha = (1.35f - ring) * 0.8f)))
                Box(Modifier.size(236.dp)
                    .background(if (on) Brush.linearGradient(listOf(t.accent, t.primaryDeep)) else Brush.linearGradient(listOf(Color.White.copy(alpha = if (t.dark) 0.14f else 0.7f), Color.White.copy(alpha = 0.02f))), CircleShape)
                    .background(t.surface.copy(alpha = if (on) 0f else 0.35f), CircleShape)
                    .border1(Color.White.copy(alpha = if (t.dark) 0.45f else 0.9f))
                    .clickable(enabled = phase != Phase.BUSY) { if (TunnelState.running) model.disconnect() else activity.connect() },
                    contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(if (on) Icons.Filled.Shield else if (phase == Phase.TROUBLE) Icons.Filled.Warning else Icons.Filled.PowerSettingsNew, null,
                            Modifier.size(54.dp), tint = if (on) t.primaryForeground else t.text)
                        Spacer(Modifier.height(10.dp))
                        Text(title, color = if (on) t.primaryForeground else t.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            StatusCard(model, t, phase, onLog)
            UpdateCard(model, t)
            Spacer(Modifier.height(16.dp))
        }
    }
}

private fun Modifier.border1(color: Color) = this.border(1.dp, color, CircleShape)

@Composable
private fun GlassIcon(t: Theme, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).background(t.surface.copy(alpha = 0.5f), CircleShape).border1(Color.White.copy(alpha = if (t.dark) 0.16f else 0.7f)).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(20.dp), tint = t.text.copy(alpha = 0.85f))
    }
}

@Composable
private fun StatusCard(model: AppModel, t: Theme, phase: Phase, onLog: () -> Unit) {
    val st = model.status
    val color = when (phase) { Phase.ON -> t.success; Phase.TROUBLE -> t.destructive; Phase.OFF -> t.muted; else -> t.warning }
    val text = when (phase) {
        Phase.ON -> "Трафик идёт через сеть WYX"; Phase.TROUBLE -> "Узел не отвечает, ищу другой"
        Phase.CHECKING -> "Туннель поднят, проверяю связь"; Phase.BUSY -> "Секунду…"; Phase.OFF -> "Не подключено"
    }
    Column(Modifier.fillMaxWidth().glassCard(t).clickable(onClick = onLog).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(9.dp).background(color, CircleShape))
            Text(text, color = t.text, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        }
        Row(Modifier.fillMaxWidth()) {
            if (TunnelState.running) {
                Metric(t, "Узел", st.nodeName ?: "—", Modifier.weight(1f))
                Metric(t, "Задержка", st.lastProbeMs?.let { "$it мс" } ?: "…", Modifier.weight(1f))
                Metric(t, "Трафик", "↑${bytes(st.up)} ↓${bytes(st.down)}", Modifier.weight(1f))
            } else {
                Metric(t, "Аккаунт", model.username?.let { "@$it" } ?: "—", Modifier.weight(1f))
                Metric(t, "Узлов", model.profile?.let { "${it.nodes.count { n -> n.ok }} из ${it.nodes.size}" } ?: "—", Modifier.weight(1f))
                Metric(t, "Выбор", model.settings.preferredNode?.let { id -> model.profile?.nodes?.firstOrNull { it.id == id }?.name } ?: "авто", Modifier.weight(1f))
            }
        }
        if (TunnelState.running && st.failures > 0 && st.lastError != null) Text(st.lastError, color = t.destructive, fontSize = 12.sp, maxLines = 2)
        model.profileNote?.let { Warn(t, it) }
        model.error?.let { Warn(t, it) }
    }
}

@Composable
private fun UpdateCard(model: AppModel, t: Theme) {
    val ctx = LocalContext.current
    val u = model.update
    if (u is UpdateState.None) return
    Column(Modifier.fillMaxWidth().padding(top = 12.dp).glassCard(t).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when (u) {
            is UpdateState.Available -> {
                Text("Есть обновление ${u.info.versionName}", color = t.text, fontWeight = FontWeight.Medium)
                if (u.info.notes.isNotBlank()) Text(u.info.notes, color = t.muted, fontSize = 13.sp)
                Button({ model.downloadUpdate(u.info) }, colors = ButtonDefaults.buttonColors(containerColor = t.primary, contentColor = t.primaryForeground)) { Text("Скачать") }
            }
            is UpdateState.Downloading -> { Text("Скачиваю ${u.info.versionName}…", color = t.text); LinearProgressIndicator(progress = { u.progress }, Modifier.fillMaxWidth(), color = t.primary) }
            is UpdateState.Ready -> {
                Text("Обновление ${u.info.versionName} скачано", color = t.text, fontWeight = FontWeight.Medium)
                Button({ Updater.install(ctx, u.file) }, colors = ButtonDefaults.buttonColors(containerColor = t.primary, contentColor = t.primaryForeground)) { Text("Установить") }
            }
            is UpdateState.Failed -> Warn(t, u.message)
            else -> {}
        }
    }
}

@Composable
private fun Metric(t: Theme, label: String, value: String, modifier: Modifier) {
    Column(modifier) {
        Text(label, color = t.muted, fontSize = 11.sp)
        Text(value, color = t.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
private fun Warn(t: Theme, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Warning, null, Modifier.size(14.dp), tint = t.warning)
        Text(text, color = t.muted, fontSize = 12.sp)
    }
}

fun bytes(b: Long): String = when {
    b >= 1 shl 30 -> "%.1f ГБ".format(b / 1073741824.0)
    b >= 1 shl 20 -> "%.1f МБ".format(b / 1048576.0)
    else -> "${b / 1024} КБ"
}

// MARK: журнал

@Composable
fun LogScreen(t: Theme, onBack: () -> Unit) {
    val ctx = LocalContext.current
    var text by remember { mutableStateOf(TunnelLog.read()) }
    var xray by remember { mutableStateOf(TunnelLog.readXray()) }
    LaunchedEffect(Unit) { while (true) { delay(2000); text = TunnelLog.read(); xray = TunnelLog.readXray() } }
    GlassBackground(t, false) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = t.text) }
                Text("Журнал", color = t.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                IconButton({ ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "$text\n\n$xray"), "Журнал")) }) { Icon(Icons.Filled.Share, null, tint = t.text) }
                IconButton({ TunnelLog.clear(); text = ""; xray = "" }) { Icon(Icons.Filled.Delete, null, tint = t.destructive) }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
                Text(text.ifEmpty { "Пока пусто." }, color = t.text, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                if (xray.isNotEmpty()) {
                    Spacer(Modifier.height(12.dp)); Text("— ядро Xray —", color = t.muted, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text(xray, color = t.text, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }
}

// MARK: настройки

@Composable
fun SettingsScreen(model: AppModel, t: Theme, activity: MainActivity, onBack: () -> Unit) {
    val s = model.settings
    GlassBackground(t, false) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = t.text) }
                Text("Настройки", color = t.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                IconButton({ model.refresh() }) { Icon(Icons.Filled.Refresh, null, tint = t.text) }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Section(t, "Оформление") {
                    Choice(t, "Мята тёмная", s.appearance == "dark") { model.updateSettings(s.copy(appearance = "dark")) }
                    Choice(t, "Мята светлая", s.appearance == "light") { model.updateSettings(s.copy(appearance = "light")) }
                }
                Section(t, "Переключение") {
                    Toggle(t, "Переключать узел, если не отвечает", s.autoSwitch) { model.updateSettings(s.copy(autoSwitch = it)) }
                    Toggle(t, "Менять узел в простое", s.rotateIdle) { model.updateSettings(s.copy(rotateIdle = it)) }
                    if (s.rotateIdle) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(30 to "30 мин", 60 to "1 ч", 120 to "2 ч", 240 to "4 ч").forEach { (m, l) -> Chip(t, l, s.rotateMinutes == m) { model.updateSettings(s.copy(rotateMinutes = m)) } }
                    }
                    Text("В простое (меньше 300 КБ за 10 минут) трафик уводится на другой живой узел.", color = t.muted, fontSize = 12.sp)
                }
                Section(t, "Узел") {
                    Choice(t, "Автоматически", s.preferredNode == null) { model.updateSettings(s.copy(preferredNode = null)) }
                    model.profile?.nodes?.forEach { n -> NodeRow(t, n, s.preferredNode == n.id, model.status.nodeId == n.id && TunnelState.running) { model.select(n) { activity.connect(n.id) } } }
                    Text("Выбранный узел становится первым; если он не отвечает, приложение всё равно уйдёт на другой.", color = t.muted, fontSize = 12.sp)
                }
                Section(t, "Аккаунт") {
                    KV(t, "Пользователь", model.username?.let { "@$it" } ?: "—")
                    model.profile?.user?.uuid?.let { KV(t, "Ключ доступа", it.take(8) + "…") }
                    Text("Выйти", color = t.destructive, modifier = Modifier.clickable { model.logout(); onBack() }.padding(vertical = 8.dp))
                }
                Section(t, "О приложении") {
                    KV(t, "Версия", Api.version)
                    KV(t, "Ядро Xray", model.status.xrayVersion ?: "—")
                    KV(t, "Сервер", Api.base.removePrefix("https://").substringBefore("/"))
                    KV(t, "Подпись профиля", "проверяется")
                    Text("Проверить обновления", color = t.primary, modifier = Modifier.clickable { model.onResume() }.padding(vertical = 8.dp))
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun Section(t: Theme, title: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().glassCard(t).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title.uppercase(), color = t.muted, fontSize = 11.sp, letterSpacing = 1.sp)
        content()
    }
}

@Composable
private fun Toggle(t: Theme, label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = t.text, modifier = Modifier.weight(1f))
        Switch(value, onChange)
    }
}

@Composable
private fun Choice(t: Theme, label: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = t.text, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, null, tint = t.primary)
    }
}

@Composable
private fun Chip(t: Theme, label: String, selected: Boolean, onClick: () -> Unit) {
    Text(label, color = if (selected) t.primaryForeground else t.text, fontSize = 13.sp,
        modifier = Modifier.background(if (selected) t.primary else t.surface2, RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp))
}

@Composable
private fun NodeRow(t: Theme, n: VpnNode, preferred: Boolean, current: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(9.dp).background(if (n.ok) t.success else t.destructive, CircleShape))
        Column(Modifier.weight(1f)) {
            Text(n.name, color = t.text)
            Text("${if (n.isReality) "Reality" else "XHTTP"} · ${if (n.ok) (n.rttMs?.let { "$it мс" } ?: "жив") else "не отвечает из Москвы"}", color = t.muted, fontSize = 12.sp)
        }
        if (current) Icon(Icons.Filled.Shield, null, tint = t.success, modifier = Modifier.size(18.dp))
        else if (preferred) Icon(Icons.Filled.Check, null, tint = t.primary, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun KV(t: Theme, k: String, v: String) {
    Row(Modifier.fillMaxWidth()) { Text(k, color = t.muted, modifier = Modifier.weight(1f)); Text(v, color = t.text) }
}
