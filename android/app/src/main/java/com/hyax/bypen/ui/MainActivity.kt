package com.hyax.bypen.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.hyax.bypen.AppModel
import com.hyax.bypen.TunnelLog

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    private var pendingNode: String? = null

    private val vpnPermission = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == RESULT_OK) model.connect(pendingNode) else { model.error = "Без разрешения VPN не поднять"; TunnelLog.log("разрешение VPN отклонено") }
    }
    private val notifPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    /** Подключение: сначала системное разрешение на VPN (один раз), потом служба. */
    fun connect(nodeId: String? = null) {
        pendingNode = nodeId
        val intent = VpnService.prepare(this)
        if (intent != null) vpnPermission.launch(intent) else model.connect(nodeId)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        model.bootstrap()
        setContent { Root(model, this) }
    }

    override fun onResume() { super.onResume(); model.onResume() }
}

enum class Screen { MAIN, LOG, SETTINGS }

@Composable
fun Root(model: AppModel, activity: MainActivity) {
    val t = Theme.named(model.settings.appearance)
    var screen by remember { mutableStateOf(Screen.MAIN) }
    BypenMaterial(t) {
        if (!model.loggedIn) LoginScreen(model, t)
        else when (screen) {
            Screen.MAIN -> MainScreen(model, t, activity, onLog = { screen = Screen.LOG }, onSettings = { screen = Screen.SETTINGS })
            Screen.LOG -> LogScreen(t, onBack = { screen = Screen.MAIN })
            Screen.SETTINGS -> SettingsScreen(model, t, activity, onBack = { screen = Screen.MAIN })
        }
    }
}
