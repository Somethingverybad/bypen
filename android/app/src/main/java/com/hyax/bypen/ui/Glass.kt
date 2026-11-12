// Объём и «стекло»: фон с плывущими пятнами света, полупрозрачные карточки с тонкой гранью.
package com.hyax.bypen.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun GlassBackground(t: Theme, active: Boolean, content: @Composable () -> Unit) {
    val anim = rememberInfiniteTransition(label = "drift")
    val drift by anim.animateFloat(0f, 1f, infiniteRepeatable(tween(9000, easing = LinearEasing), RepeatMode.Reverse), label = "d")
    val lime = t.accent.copy(alpha = if (active) 0.30f else 0.14f)
    val teal = Color(0xFF2F5B53).copy(alpha = if (t.dark) 0.9f else 0.25f)
    Box(Modifier.fillMaxSize().background(t.background).drawBehind {
        val w = size.width; val h = size.height
        drawCircle(Brush.radialGradient(listOf(lime, Color.Transparent)), radius = w * 0.75f, center = Offset(w * (0.2f - 0.15f * drift), h * (0.05f + 0.08f * drift)))
        drawCircle(Brush.radialGradient(listOf(teal, Color.Transparent)), radius = w * 0.8f, center = Offset(w * (0.85f + 0.1f * drift), h * (0.9f - 0.08f * drift)))
        if (active) drawCircle(Brush.radialGradient(listOf(t.accent.copy(alpha = 0.12f), Color.Transparent)), radius = w * 0.9f, center = Offset(w / 2, h * 0.45f))
    }) { content() }
}

fun Modifier.glassCard(t: Theme, radius: Int = 20): Modifier {
    val shape = RoundedCornerShape(radius.dp)
    return this.clip(shape)
        .background(Brush.verticalGradient(listOf(t.surface.copy(alpha = if (t.dark) 0.62f else 0.85f), t.surface.copy(alpha = if (t.dark) 0.45f else 0.7f))), shape)
        .border(1.dp, Brush.linearGradient(listOf(Color.White.copy(alpha = if (t.dark) 0.22f else 0.9f), Color.White.copy(alpha = if (t.dark) 0.04f else 0.3f))), shape)
}
