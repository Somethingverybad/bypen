// Палитра из макета Figma «vopoen» (16.11.2026): тёмная «Мята» по умолчанию, светлая — в настройках.
package com.hyax.bypen.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

data class Theme(
    val dark: Boolean,
    val background: Color, val backgroundEnd: Color,
    val text: Color, val muted: Color, val subtitle: Color, val footnote: Color,
    val primary: Color, val primaryForeground: Color, val accent: Color,
    val destructive: Color, val warning: Color,
    val headerButton: Color, val headerSymbol: Color,
    val cardStart: Color, val cardEnd: Color, val cardBorder: Color,
    val settingsCardStart: Color, val settingsCardEnd: Color, val settingsCardBorder: Color,
    val divider: Color, val toggleOn: Color, val toggleOff: Color, val toggleKnob: Color,
    val dotIdle: Color, val dotOk: Color, val dotBad: Color, val dotBusy: Color,
    val buttonIdleStart: Color, val buttonIdleEnd: Color, val buttonIdleBorder: Color, val buttonIdleSymbol: Color,
    val buttonOnStart: Color, val buttonOnEnd: Color,
) {
    /** Символ и подпись на диске «защищено» — #2F5B53 в обеих темах. */
    val onSymbol: Color get() = Color(0xFF2F5B53)
    // совместимость со старыми местами
    val surface: Color get() = settingsCardStart
    val surface2: Color get() = settingsCardEnd
    val border: Color get() = settingsCardBorder
    val success: Color get() = dotOk

    companion object {
        private val lime = Color(0xFFC7F964)
        private val deep = Color(0xFF2F5B53)
        val mintDark = Theme(
            dark = true,
            background = Color(0xFF222B27), backgroundEnd = Color(0xFF222B27),
            text = Color.White, muted = Color(0xFFBDBDBD), subtitle = Color(0xFFBDBDBD), footnote = Color(0xFFBDBDBD),
            primary = lime, primaryForeground = deep, accent = lime,
            destructive = Color(0xFFC65A52), warning = Color(0xFFFBB104),
            headerButton = lime, headerSymbol = deep,
            cardStart = Color(0xB3323D39), cardEnd = Color(0xB33F524E), cardBorder = Color(0xFFC4C4C4),
            settingsCardStart = Color(0xFF222B27), settingsCardEnd = Color(0xFF2D392B), settingsCardBorder = lime.copy(alpha = 0.3f),
            divider = lime.copy(alpha = 0.15f), toggleOn = lime, toggleOff = Color(0xFF5D645C), toggleKnob = Color(0xFF222B27),
            dotIdle = Color(0xFF97A29C), dotOk = Color(0xFF489D8E), dotBad = Color(0xFFC65A52), dotBusy = Color(0xFFFBB104),
            buttonIdleStart = Color(0xFF464D45), buttonIdleEnd = Color(0xFF37403D), buttonIdleBorder = Color(0xFFC4C4C4), buttonIdleSymbol = Color.White,
            buttonOnStart = lime, buttonOnEnd = lime,
        )
        val mintLight = Theme(
            dark = false,
            background = Color.White, backgroundEnd = Color(0xFFE6EFDF),
            text = deep, muted = Color(0xFF878787), subtitle = Color(0xFF9CB2AB), footnote = Color(0xFFA2A2A2),
            primary = deep, primaryForeground = Color.White, accent = lime,
            destructive = Color(0xFFC65A52), warning = Color(0xFFE09A00),
            headerButton = Color.White, headerSymbol = deep,
            cardStart = Color.White, cardEnd = Color(0xFFE4E4E4), cardBorder = Color.White,
            settingsCardStart = Color.White, settingsCardEnd = Color.White, settingsCardBorder = Color.White,
            divider = Color(0xFFD9D9D9), toggleOn = deep, toggleOff = Color(0xFFD9D9D9), toggleKnob = Color.White,
            dotIdle = Color(0xFF97A29C), dotOk = Color(0xFF489D8E), dotBad = Color(0xFFC65A52), dotBusy = Color(0xFFFBB104),
            buttonIdleStart = lime.copy(alpha = 0.61f), buttonIdleEnd = Color(0xFF489D8E).copy(alpha = 0.61f), buttonIdleBorder = Color.Transparent, buttonIdleSymbol = deep,
            buttonOnStart = lime, buttonOnEnd = Color(0xFF489D8E),
        )
        fun named(id: String) = if (id == "light") mintLight else mintDark
    }
}

@Composable
fun BypenMaterial(t: Theme, content: @Composable () -> Unit) {
    val scheme = if (t.dark) darkColorScheme(
        primary = t.accent, onPrimary = t.primaryForeground, background = t.background, onBackground = t.text,
        surface = t.settingsCardStart, onSurface = t.text, surfaceVariant = t.settingsCardEnd, onSurfaceVariant = t.muted, outline = t.settingsCardBorder, error = t.destructive,
    ) else lightColorScheme(
        primary = t.primary, onPrimary = t.primaryForeground, background = t.background, onBackground = t.text,
        surface = Color.White, onSurface = t.text, surfaceVariant = Color(0xFFF2F5F0), onSurfaceVariant = t.muted, outline = t.divider, error = t.destructive,
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
