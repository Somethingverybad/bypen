// Фон, карточки и символы по макету Figma «vopoen»: «круги на воде» (оливковое пятно вверху,
// бирюзовое внизу справа), карточки с градиентом и тонкой рамкой, символы кнопки — линиями.
package com.hyax.bypen.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.unit.dp

@Composable
fun GlassBackground(t: Theme, active: Boolean, content: @Composable () -> Unit) {
    val anim = rememberInfiniteTransition(label = "drift")
    val drift by anim.animateFloat(0f, 1f, infiniteRepeatable(tween(11000, easing = LinearEasing), RepeatMode.Reverse), label = "d")
    val olive = Color(0xFF2E471C).copy(alpha = 0.69f)
    val teal = Color(0xFF489D8E).copy(alpha = 0.33f)
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(t.background, t.backgroundEnd))).drawBehind {
        // Координаты из макета (кадр 1177×2559): оливковое — центр (316, 428), r ≈ 0.45 w; бирюзовое — центр (844, 2199), r ≈ 0.41 w.
        // Размытие σ 283 px даёт мягкий край — радиальный градиент на радиусе ×1.6.
        val w = size.width; val h = size.height
        if (t.dark) {
            val c = Offset(w * (0.268f + 0.03f * drift), h * (0.167f + 0.013f * drift))
            drawCircle(Brush.radialGradient(listOf(olive, olive.copy(alpha = olive.alpha * 0.5f), Color.Transparent), center = c, radius = w * 0.72f), radius = w * 0.72f, center = c)
        }
        val tc = Offset(w * (0.717f - 0.03f * drift), h * (0.859f - 0.014f * drift))
        drawCircle(Brush.radialGradient(listOf(teal, teal.copy(alpha = teal.alpha * 0.5f), Color.Transparent), center = tc, radius = w * 0.66f), radius = w * 0.66f, center = tc)
        if (active) drawCircle(Brush.radialGradient(listOf(t.accent.copy(alpha = 0.12f), Color.Transparent), center = Offset(w / 2, h * 0.48f), radius = w * 0.9f),
            radius = w * 0.9f, center = Offset(w / 2, h * 0.48f))
    }) { content() }
}

/** Карточка статуса: градиент 41°, рамка 1 dp, радиус 20. */
fun Modifier.glassCard(t: Theme, radius: Int = 20): Modifier {
    val shape = RoundedCornerShape(radius.dp)
    return this.shadow(if (t.dark) 0.dp else 12.dp, shape, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f))
        .clip(shape)
        .background(Brush.linearGradient(listOf(t.cardStart, t.cardEnd), start = Offset(0f, Float.POSITIVE_INFINITY), end = Offset(Float.POSITIVE_INFINITY, 0f)), shape)
        .border(1.dp, t.cardBorder, shape)
}

/** Карточка настроек: тёмный градиент с лаймовой рамкой 30 % (светлая — белая с тенью). */
fun Modifier.settingsCard(t: Theme, radius: Int = 20): Modifier {
    val shape = RoundedCornerShape(radius.dp)
    return this.shadow(12.dp, shape, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f))
        .clip(shape)
        .background(Brush.verticalGradient(listOf(t.settingsCardStart, t.settingsCardEnd)), shape)
        .border(0.7.dp, t.settingsCardBorder, shape)
}

enum class ButtonSymbol { POWER, HALF_SHIELD, CHECK_SHIELD, WARN_SHIELD }

private fun shieldPath(r: Rect): Path = Path().apply {
    val w = r.width; val h = r.height; val x = r.left; val y = r.top
    moveTo(x + w * 0.5f, y)
    lineTo(x + w * 0.95f, y + h * 0.17f)
    quadraticTo(x + w, y + h * 0.19f, x + w, y + h * 0.27f)
    lineTo(x + w, y + h * 0.46f)
    cubicTo(x + w, y + h * 0.78f, x + w * 0.78f, y + h * 0.92f, x + w * 0.5f, y + h)
    cubicTo(x + w * 0.22f, y + h * 0.92f, x, y + h * 0.78f, x, y + h * 0.46f)
    lineTo(x, y + h * 0.27f)
    quadraticTo(x, y + h * 0.19f, x + w * 0.05f, y + h * 0.17f)
    close()
}

/** Символы большой кнопки из макета: питание, щит наполовину, щит с галочкой, щит с «!». */
@Composable
fun BigButtonSymbol(kind: ButtonSymbol, t: Theme, modifier: Modifier = Modifier) {
    Canvas(modifier.size(60.dp, 70.dp)) {
        val sw = 6.dp.toPx()
        val stroke = Stroke(sw, cap = StrokeCap.Round, join = StrokeJoin.Round)
        val sh = Rect(Offset((size.width - 56.dp.toPx()) / 2, (size.height - 68.dp.toPx()) / 2), Size(56.dp.toPx(), 68.dp.toPx()))
        when (kind) {
            ButtonSymbol.POWER -> {
                val d = 46.dp.toPx(); val c = Offset(size.width / 2, size.height / 2 + 4.dp.toPx())
                drawArc(t.buttonIdleSymbol, -60f, 300f, false, Offset(c.x - d / 2, c.y - d / 2), Size(d, d), style = stroke)
                drawLine(t.buttonIdleSymbol, Offset(size.width / 2, 6.dp.toPx()), Offset(size.width / 2, size.height / 2 + 2.dp.toPx()), sw, StrokeCap.Round)
            }
            ButtonSymbol.HALF_SHIELD -> {
                val p = shieldPath(sh)
                clipRect(right = size.width / 2) { drawPath(p, t.buttonIdleSymbol.copy(alpha = 0.75f)) }
                drawPath(p, t.buttonIdleSymbol, style = stroke)
            }
            ButtonSymbol.CHECK_SHIELD -> {
                val p = shieldPath(sh)
                drawPath(p, t.onSymbol); drawPath(p, t.onSymbol, style = stroke)
                val cx = size.width / 2; val cy = size.height / 2 - 2.dp.toPx()
                val path = Path().apply { moveTo(cx - 11.5f.dp.toPx(), cy + 0.5f.dp.toPx()); lineTo(cx - 4f.dp.toPx(), cy + 8.dp.toPx()); lineTo(cx + 11.5f.dp.toPx(), cy - 8.dp.toPx()) }
                drawPath(path, t.accent, style = stroke)
            }
            ButtonSymbol.WARN_SHIELD -> {
                drawPath(shieldPath(sh), t.destructive, style = stroke)
                val cx = size.width / 2
                drawLine(t.destructive, Offset(cx, size.height * 0.3f), Offset(cx, size.height * 0.55f), sw, StrokeCap.Round)
                drawCircle(t.destructive, sw * 0.6f, Offset(cx, size.height * 0.68f))
            }
        }
    }
}

/** Галочка выбора из макета. */
@Composable
fun CheckMark(t: Theme) {
    Canvas(Modifier.size(18.dp, 13.dp)) {
        val p = Path().apply { moveTo(0f, size.height * 0.55f); lineTo(size.width * 0.33f, size.height); lineTo(size.width, 0f) }
        drawPath(p, if (t.dark) t.accent else t.text, style = Stroke(1.4f.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}
