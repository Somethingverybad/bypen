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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
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
    var withPassword by remember { mutableStateOf(false) }
    val ctx = LocalContext.current
    val canSubmit = u.isNotBlank() && (!withPassword || p.isNotBlank())
    val submit = { if (canSubmit && !model.busy) { if (withPassword) model.login(u, p) else model.loginViaWYX(u) } }
    GlassBackground(t, false) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("WYX", color = t.text, fontSize = 48.sp, fontWeight = FontWeight.SemiBold)
            Text("сеть", color = t.subtitle, fontSize = 17.sp)
            Spacer(Modifier.height(24.dp))
            val bot = model.awaitingBot
            Column(Modifier.fillMaxWidth().settingsCard(t, 24).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                if (bot != null) {
                    Icon(Icons.AutoMirrored.Filled.Send, null, tint = t.accent, modifier = Modifier.size(34.dp))
                    Text("Подтвердите вход в WYX", color = t.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    Text("Бот «$bot» прислал вам сообщение. Нажмите в нём «Да, это я».", color = t.subtitle, fontSize = 15.sp, textAlign = TextAlign.Center)
                    CircularProgressIndicator(Modifier.size(22.dp), color = t.accent, strokeWidth = 2.dp)
                    PrimaryButton(t, "Открыть WYX", enabled = true, busy = false) {
                        val i = ctx.packageManager.getLaunchIntentForPackage(Api.WYX_PACKAGE)
                            ?: Intent(Intent.ACTION_VIEW, android.net.Uri.parse(Api.WYX_DOWNLOADS))
                        try { ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
                    }
                    Text("Отмена", color = t.muted, fontSize = 15.sp, modifier = Modifier.clickable { model.cancelBotLogin() }.padding(6.dp))
                } else {
                    val colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = t.text, unfocusedTextColor = t.text, cursorColor = if (t.dark) t.accent else t.primary,
                        focusedBorderColor = if (t.dark) t.accent else t.primary, unfocusedBorderColor = if (t.dark) t.settingsCardBorder else t.divider,
                        focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                        focusedPlaceholderColor = t.muted, unfocusedPlaceholderColor = t.muted,
                    )
                    OutlinedTextField(u, { u = it }, Modifier.fillMaxWidth(), placeholder = { Text("Ник в WYX") }, singleLine = true, colors = colors, shape = RoundedCornerShape(16.dp),
                        keyboardOptions = KeyboardOptions(imeAction = if (withPassword) ImeAction.Next else ImeAction.Go),
                        keyboardActions = KeyboardActions(onGo = { submit() }))
                    if (withPassword) {
                        OutlinedTextField(p, { p = it }, Modifier.fillMaxWidth(), placeholder = { Text("Пароль") }, singleLine = true, colors = colors, shape = RoundedCornerShape(16.dp),
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
                            keyboardActions = KeyboardActions(onGo = { submit() }))
                    }
                    model.error?.let { Text(it, color = t.destructive, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                    PrimaryButton(t, if (withPassword) "Войти" else "Войти через WYX", enabled = canSubmit && !model.busy, busy = model.busy) { submit() }
                    if (!withPassword) {
                        Text("Бот «Бупень» пришлёт в WYX запрос на вход — подтвердите его там.", color = t.muted, fontSize = 13.sp, textAlign = TextAlign.Center)
                    }
                }
            }
            if (bot == null) {
                Spacer(Modifier.height(16.dp))
                Text("Нет аккаунта WYX", color = t.accent, fontSize = 15.sp, fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable {
                        try { ctx.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(Api.WYX_DOWNLOADS)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
                    }.padding(6.dp))
                Text(if (withPassword) "Войти через WYX" else "Войти паролем", color = t.muted, fontSize = 13.sp,
                    modifier = Modifier.clickable { withPassword = !withPassword; model.error = null }.padding(6.dp))
            }
            Spacer(Modifier.height(32.dp))
            Text("Бупень ${Api.version}", color = t.muted.copy(alpha = 0.6f), fontSize = 11.sp)
        }
    }
}

@Composable
private fun PrimaryButton(t: Theme, title: String, enabled: Boolean, busy: Boolean, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth().height(50.dp),
        shape = RoundedCornerShape(16.dp), colors = ButtonDefaults.buttonColors(containerColor = if (t.dark) t.accent else t.primary, contentColor = if (t.dark) t.primaryForeground else Color.White,
            disabledContainerColor = (if (t.dark) t.accent else t.primary).copy(alpha = 0.5f), disabledContentColor = (if (t.dark) t.primaryForeground else Color.White).copy(alpha = 0.7f))) {
        if (busy) CircularProgressIndicator(Modifier.size(18.dp), color = t.primaryForeground, strokeWidth = 2.dp)
        else Text(title, fontWeight = FontWeight.SemiBold)
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
    val glow = when (phase) {
        Phase.OFF -> Color.Transparent
        Phase.BUSY, Phase.CHECKING -> t.accent.copy(alpha = if (t.dark) 0.48f else 0.7f)
        Phase.ON -> t.accent.copy(alpha = if (t.dark) 0.6f else 0.8f)
        Phase.TROUBLE -> t.destructive
    }
    val on = phase == Phase.ON
    val working = phase == Phase.BUSY || phase == Phase.CHECKING

    val anim = rememberInfiniteTransition(label = "pulse")
    val breathe by anim.animateFloat(0.97f, 1.05f, infiniteRepeatable(tween(2600), RepeatMode.Reverse), label = "b")
    val ring by anim.animateFloat(0.95f, 1.35f, infiniteRepeatable(tween(1800)), label = "r")
    val glowAlpha by animateFloatAsState(if (phase == Phase.OFF) 0f else 1f, tween(500), label = "ga")

    GlassBackground(t, on) {
        Column(Modifier.fillMaxSize().systemBarsPadding().padding(horizontal = 20.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                HeaderButton(t, Icons.Filled.Description, onLog)
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("WYX", color = t.text, fontSize = 27.sp, fontWeight = FontWeight.SemiBold)
                    Text("сеть", color = t.subtitle, fontSize = 12.sp)
                }
                Spacer(Modifier.weight(1f))
                HeaderButton(t, Icons.Filled.Settings, onSettings)
            }
            Spacer(Modifier.weight(1f))
            val disc = 227.dp
            Box(Modifier.align(Alignment.CenterHorizontally).size(320.dp), contentAlignment = Alignment.Center) {
                // свечение: защищено — широкое лаймовое, проверка — слабее
                Box(Modifier.size(disc + 40.dp).scale(if (on) breathe else 1f).blur(if (on) 60.dp else 36.dp)
                    .background(glow.copy(alpha = glow.alpha * glowAlpha), CircleShape))
                // кольца «на воде» при проверке
                if (working) {
                    Box(Modifier.size(disc).scale(ring).border1(t.accent.copy(alpha = (1.35f - ring) * 0.6f)))
                    Box(Modifier.size(disc).scale(ring * 1.08f).border1(t.accent.copy(alpha = (1.35f - ring) * 0.4f)))
                }
                // градиент по диагонали (в макете 144°): защищено — лайм (тёмная) или лайм→бирюза (светлая)
                val k = if (working && t.dark) 0.85f else 1f
                val discBrush = if (on) Brush.linearGradient(listOf(t.buttonOnStart, t.buttonOnEnd))
                    else Brush.linearGradient(listOf(t.buttonIdleStart.copy(alpha = t.buttonIdleStart.alpha * k), t.buttonIdleEnd.copy(alpha = t.buttonIdleEnd.alpha * k)))
                Box(Modifier.size(disc)
                    .background(discBrush, CircleShape)
                    .border1(if (on) Color.Transparent else t.buttonIdleBorder)
                    .clickable(enabled = phase != Phase.BUSY) { if (TunnelState.running) model.disconnect() else activity.connect() },
                    contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(top = 10.dp)) {
                        BigButtonSymbol(
                            when (phase) { Phase.ON -> ButtonSymbol.CHECK_SHIELD; Phase.TROUBLE -> ButtonSymbol.WARN_SHIELD; Phase.OFF -> ButtonSymbol.POWER; else -> ButtonSymbol.HALF_SHIELD },
                            t)
                        Spacer(Modifier.height(14.dp))
                        Text(title, color = if (on) t.onSymbol else t.buttonIdleSymbol, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
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
private fun HeaderButton(t: Theme, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(Modifier.size(40.dp)
        .shadow(if (t.dark) 10.dp else 8.dp, CircleShape, ambientColor = if (t.dark) t.accent else Color.Black, spotColor = if (t.dark) t.accent else Color.Black)
        .background(t.headerButton, CircleShape).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(20.dp), tint = t.headerSymbol)
    }
}

@Composable
private fun StatusCard(model: AppModel, t: Theme, phase: Phase, onLog: () -> Unit) {
    val st = model.status
    val color = when (phase) { Phase.ON -> t.dotOk; Phase.TROUBLE -> t.dotBad; Phase.OFF -> t.dotIdle; else -> t.dotBusy }
    val text = when (phase) {
        Phase.ON -> "Трафик идёт через сеть WYX"; Phase.TROUBLE -> "Узел не отвечает, ищу другой"
        Phase.CHECKING -> "Туннель поднят, проверяю связь"; Phase.BUSY -> "Секунду…"; Phase.OFF -> "Не подключено"
    }
    Column(Modifier.fillMaxWidth().glassCard(t).clickable(onClick = onLog).padding(horizontal = 18.dp, vertical = 17.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
            Box(Modifier.size(9.dp).shadow(4.dp, CircleShape, ambientColor = color, spotColor = color).background(color, CircleShape))
            Text(text, color = t.text, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
        // колонки по долям ширины, как в макете
        Row(Modifier.fillMaxWidth()) {
            if (TunnelState.running) {
                Metric(t, "Узел", st.nodeName ?: "—", Modifier.weight(0.41f))
                Metric(t, "Задержка", st.lastProbeMs?.let { "$it мс" } ?: "…", Modifier.weight(0.28f))
                Metric(t, "Трафик", "↑${bytes(st.up)} ↓${bytes(st.down)}", Modifier.weight(0.31f))
            } else {
                Metric(t, "Аккаунт", model.username?.let { "@$it" } ?: "—", Modifier.weight(0.41f))
                Metric(t, "Узлов", model.profile?.let { "${it.nodes.count { n -> n.ok }} из ${it.nodes.size}" } ?: "—", Modifier.weight(0.37f))
                Metric(t, "Выбор", model.settings.preferredNode?.let { id -> model.profile?.nodes?.firstOrNull { it.id == id }?.name } ?: "авто", Modifier.weight(0.22f))
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
    Column(Modifier.fillMaxWidth().padding(top = 12.dp).settingsCard(t).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when (u) {
            is UpdateState.Available -> {
                Text("Есть обновление ${u.info.versionName}", color = t.text, fontWeight = FontWeight.Medium)
                if (u.info.notes.isNotBlank()) Text(u.info.notes, color = t.muted, fontSize = 13.sp)
                Button({ model.downloadUpdate(u.info) }, colors = ButtonDefaults.buttonColors(containerColor = if (t.dark) t.accent else t.primary, contentColor = t.primaryForeground)) { Text("Скачать") }
            }
            is UpdateState.Downloading -> { Text("Скачиваю ${u.info.versionName}…", color = t.text); LinearProgressIndicator(progress = { u.progress }, Modifier.fillMaxWidth(), color = t.primary) }
            is UpdateState.Ready -> {
                Text("Обновление ${u.info.versionName} скачано", color = t.text, fontWeight = FontWeight.Medium)
                Button({ Updater.install(ctx, u.file) }, colors = ButtonDefaults.buttonColors(containerColor = if (t.dark) t.accent else t.primary, contentColor = t.primaryForeground)) { Text("Установить") }
            }
            is UpdateState.Failed -> Warn(t, u.message)
            else -> {}
        }
    }
}

@Composable
private fun Metric(t: Theme, label: String, value: String, modifier: Modifier) {
    Column(modifier.padding(end = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, color = t.muted, fontSize = 12.sp)
        Text(value, color = t.text, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
    var themeMenu by remember { mutableStateOf(false) }
    GlassBackground(t, false) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = t.muted) }
                    Spacer(Modifier.weight(1f))
                    IconButton({ model.refresh() }) { Icon(Icons.Filled.Refresh, null, tint = t.muted) }
                }
                Text("Настройки", color = t.text, fontSize = 18.sp, fontWeight = FontWeight.Medium)
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 17.dp)) {
                Section(t, "Оформление") {
                    Box {
                        SRow(t, "Тема", onClick = { themeMenu = true }) {
                            Text(if (s.appearance == "light") "Мята светлая" else "Мята тёмная", color = if (t.dark) t.accent else t.text, fontSize = 14.sp)
                            Icon(Icons.Filled.KeyboardArrowDown, null, Modifier.size(18.dp), tint = t.muted)
                        }
                        DropdownMenu(themeMenu, { themeMenu = false }) {
                            DropdownMenuItem({ Text("Мята тёмная") }, { themeMenu = false; model.updateSettings(s.copy(appearance = "dark")) })
                            DropdownMenuItem({ Text("Мята светлая") }, { themeMenu = false; model.updateSettings(s.copy(appearance = "light")) })
                        }
                    }
                }
                Section(t, "Переключение", "В простое (меньше 300 КБ за 10 минут) трафик уводится на другой живой узел, чтобы не идти всё время в одну точку") {
                    SRow(t, "Переключать узел, если не отвечает", onClick = { model.updateSettings(s.copy(autoSwitch = !s.autoSwitch)) }) { MintToggle(t, s.autoSwitch) }
                    SDivider(t)
                    SRow(t, "Менять узел в простое", onClick = { model.updateSettings(s.copy(rotateIdle = !s.rotateIdle)) }) { MintToggle(t, s.rotateIdle) }
                    if (s.rotateIdle) {
                        SDivider(t)
                        Row(Modifier.padding(horizontal = 18.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(30 to "30 мин", 60 to "1 ч", 120 to "2 ч", 240 to "4 ч").forEach { (m, l) -> Chip(t, l, s.rotateMinutes == m) { model.updateSettings(s.copy(rotateMinutes = m)) } }
                        }
                    }
                }
                DirectSection(model, t)
                Section(t, "Узел", "Выбранный узел становится первым; если он не отвечает, приложение всё равно уйдёт на другой") {
                    SRow(t, "Автоматически", onClick = { model.updateSettings(s.copy(preferredNode = null)) }) { if (s.preferredNode == null) CheckMark(t) }
                    model.profile?.nodes?.forEach { n ->
                        SDivider(t)
                        NodeRow(t, n, s.preferredNode == n.id, model.status.nodeId == n.id && TunnelState.running) { model.select(n) { activity.connect(n.id) } }
                    }
                }
                Section(t, "Аккаунт") {
                    SRow(t, "Пользователь") { Text(model.username?.let { "@$it" } ?: "—", color = t.muted, fontSize = 14.sp) }
                    model.profile?.user?.uuid?.let { SDivider(t); SRow(t, "Ключ доступа") { Text(it.take(8) + "…", color = t.muted, fontSize = 14.sp) } }
                    SDivider(t)
                    SRow(t, "Выйти", color = t.destructive, onClick = { model.logout(); onBack() }) {}
                }
                Section(t, "О приложении") {
                    SRow(t, "Версия") { Text(Api.version, color = t.muted, fontSize = 14.sp) }
                    SDivider(t)
                    SRow(t, "Ядро Xray") { Text(model.status.xrayVersion ?: "—", color = t.muted, fontSize = 14.sp) }
                    SDivider(t)
                    SRow(t, "Сервер") { Text(Api.base.removePrefix("https://").substringBefore("/"), color = t.muted, fontSize = 14.sp) }
                    SDivider(t)
                    SRow(t, "Проверить обновления", color = if (t.dark) t.accent else t.text, onClick = { model.onResume() }) {}
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun Section(t: Theme, title: String, footnote: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = 26.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = t.text, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        Column(Modifier.fillMaxWidth().settingsCard(t)) { content() }
        footnote?.let { Text(it, color = t.footnote, fontSize = 12.sp) }
    }
}

@Composable
private fun SRow(t: Theme, title: String, color: Color = t.text, onClick: (() -> Unit)? = null, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).heightIn(min = 44.dp).padding(horizontal = 18.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = color, fontSize = 14.sp, modifier = Modifier.weight(1f))
        trailing()
    }
}

/** «Напрямую, мимо VPN»: российские сайты (список сети WYX) и свои адреса. Хранится в профиле
 *  WYX — одно на все устройства; после сохранения VPN переподключается. */
@Composable
private fun DirectSection(model: AppModel, t: Theme) {
    var entry by remember { mutableStateOf("") }
    var askShare by remember { mutableStateOf(false) }
    var shareTo by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { model.loadDirect() }
    val d = model.direct
    val ru = d?.ru ?: true
    val n = d?.ruCount ?: 0
    val note = buildString {
        model.directError?.let { append(it).append("\n") }
        model.directNote?.let { append(it).append("\n") }
        append("Российские — зоны .ru, .su, .рф")
        if (n > 4) append(" и ещё ${n - 4} адресов из списка сети WYX")
        append(". Свои: example.com — вместе с поддоменами, .ru — вся зона, =example.com — только этот адрес. Хранится в аккаунте WYX — действует на всех устройствах.")
    }
    Section(t, "Напрямую, мимо VPN", note) {
        SRow(t, "Российские сайты", onClick = { if (!model.directSaving) model.saveDirect(ru = !ru) }) { MintToggle(t, ru) }
        d?.custom?.forEach { e ->
            SDivider(t)
            SRow(t, directLabel(e)) {
                Icon(Icons.Filled.Close, "Убрать", Modifier.size(20.dp).clickable { model.saveDirect(custom = d.custom - e) }, tint = t.muted)
            }
        }
        SDivider(t)
        Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            val add = { val e = entry.trim(); if (e.isNotEmpty() && !model.directSaving) model.saveDirect(custom = (d?.custom ?: emptyList()) + e) { ok -> if (ok) entry = "" } }
            androidx.compose.foundation.text.BasicTextField(entry, { entry = it }, Modifier.weight(1f).padding(vertical = 12.dp), singleLine = true,
                textStyle = androidx.compose.ui.text.TextStyle(color = t.text, fontSize = 14.sp),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(if (t.dark) t.accent else t.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }),
                decorationBox = { inner -> if (entry.isEmpty()) Text("example.com, .ru или =точный.адрес", color = t.muted, fontSize = 14.sp); inner() })
            if (model.directSaving) CircularProgressIndicator(Modifier.size(18.dp), color = t.accent, strokeWidth = 2.dp)
            else IconButton(onClick = { add() }, enabled = entry.isNotBlank()) { Icon(Icons.Filled.Add, "Добавить", tint = if (t.dark) t.accent else t.text) }
        }
        SDivider(t)
        SRow(t, "Поделиться по логину WYX", color = if (t.dark) t.accent else t.text, onClick = { shareTo = ""; askShare = true }) {
            Icon(Icons.AutoMirrored.Filled.Send, null, Modifier.size(18.dp), tint = t.muted)
        }
    }
    if (askShare) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { askShare = false },
            title = { Text("Поделиться настройками") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Бот «Бупень» пришлёт человеку ваши настройки — он сам решит, принять ли их.", fontSize = 14.sp)
                    OutlinedTextField(shareTo, { shareTo = it }, placeholder = { Text("Ник в WYX") }, singleLine = true)
                }
            },
            confirmButton = { androidx.compose.material3.TextButton({ askShare = false; model.shareDirect(shareTo) }, enabled = shareTo.isNotBlank()) { Text("Отправить") } },
            dismissButton = { androidx.compose.material3.TextButton({ askShare = false }) { Text("Отмена") } },
        )
    }
}

/** «full:x» → «= x», зона без точки → «.ru», домен — как есть. */
private fun directLabel(e: String) = when {
    e.startsWith("full:") -> "= " + e.removePrefix("full:")
    e.contains('.') -> e
    else -> ".$e"
}

@Composable
private fun SDivider(t: Theme) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 10.dp).height(0.7.dp).background(t.divider))
}

/** Тумблер из макета: капсула 49×30, лайм с тёмным кружком (вкл.) или графит (выкл.). */
@Composable
private fun MintToggle(t: Theme, on: Boolean) {
    val x by animateFloatAsState(if (on) 1f else 0f, tween(200), label = "tg")
    Box(Modifier.size(49.dp, 30.dp).background(if (on) t.toggleOn else t.toggleOff, CircleShape).padding(2.3.dp)) {
        Box(Modifier.offset(x = (19.dp * x)).size(25.4.dp).background(t.toggleKnob, CircleShape))
    }
}

@Composable
private fun Chip(t: Theme, label: String, selected: Boolean, onClick: () -> Unit) {
    Text(label, color = if (selected) t.primaryForeground else t.text, fontSize = 13.sp,
        modifier = Modifier.background(if (selected) (if (t.dark) t.accent else t.toggleOn) else t.toggleOff.copy(alpha = 0.4f), RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp))
}

@Composable
private fun NodeRow(t: Theme, n: VpnNode, preferred: Boolean, current: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
        val dot = if (n.ok) t.dotOk else t.dotBad
        Box(Modifier.size(9.dp).shadow(4.dp, CircleShape, ambientColor = dot, spotColor = dot).background(dot, CircleShape))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(n.name, color = t.text, fontSize = 14.sp)
            Text("${if (n.isReality) "Reality" else "XHTTP"} • ${if (n.ok) (n.rttMs?.let { "$it мс" } ?: "жив") else "не отвечает из Москвы"}", color = t.muted, fontSize = 12.sp)
        }
        if (current) Icon(Icons.Filled.Shield, null, tint = t.dotOk, modifier = Modifier.size(16.dp))
        else if (preferred) CheckMark(t)
    }
}
