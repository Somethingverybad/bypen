// Темы «Мята» из мессенджера WYX (sux-chat-app/src/themes/builtin.ts): тёмная по умолчанию.
package com.hyax.bypen.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

data class Theme(
    val dark: Boolean,
    val background: Color, val surface: Color, val surface2: Color, val border: Color,
    val text: Color, val muted: Color,
    val primary: Color, val primaryForeground: Color, val primaryDeep: Color, val accent: Color,
    val destructive: Color, val success: Color, val warning: Color,
) {
    companion object {
        val mintDark = Theme(
            true, Color(0xFF222B27), Color(0xFF2C3832), Color(0xFF37453D), Color(0xFF4C5F3A),
            Color.White, Color(0xFF9AA59E),
            Color(0xFFC7F964), Color(0xFF2F5B53), Color(0xFF9FCB45), Color(0xFFC7F964),
            Color(0xFFFF6B5E), Color(0xFF6FCF7B), Color(0xFFFFB10A),
        )
        val mintLight = Theme(
            false, Color(0xFFF4F8F1), Color.White, Color(0xFFEEF4EA), Color(0xFFE1E8DC),
            Color(0xFF23463F), Color(0xFF6F7A74),
            Color(0xFF2F5B53), Color.White, Color(0xFF24473F), Color(0xFFC7F964),
            Color(0xFFD64545), Color(0xFF3E8E41), Color(0xFFB8860B),
        )
        fun named(id: String) = if (id == "light") mintLight else mintDark
    }
}

@Composable
fun BypenMaterial(t: Theme, content: @Composable () -> Unit) {
    val scheme = if (t.dark) darkColorScheme(
        primary = t.primary, onPrimary = t.primaryForeground, background = t.background, onBackground = t.text,
        surface = t.surface, onSurface = t.text, surfaceVariant = t.surface2, onSurfaceVariant = t.muted, outline = t.border, error = t.destructive,
    ) else lightColorScheme(
        primary = t.primary, onPrimary = t.primaryForeground, background = t.background, onBackground = t.text,
        surface = t.surface, onSurface = t.text, surfaceVariant = t.surface2, onSurfaceVariant = t.muted, outline = t.border, error = t.destructive,
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
