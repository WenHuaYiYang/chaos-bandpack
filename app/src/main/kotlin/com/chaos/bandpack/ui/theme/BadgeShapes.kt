package com.chaos.bandpack.ui.theme

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * 圆角正多边形 —— M3 Expressive 那套"饼干/花形"徽标的本地实现。
 *
 * 为什么不直接用 material3 的 MaterialShapes: alpha 轨里只暴露了 `RoundedPolygon`
 * 数据, 没有现成的 `toShape()`; 为一个装饰形状去接 `androidx.graphics.shapes` 的
 * Path 转换不划算。这里按"顶点 + 二次贝塞尔倒角"自己画, 几何简单、可控。
 *
 * [sides] 边数(饼干常见 6/9, 花形用 4), [round] 倒角占内切圆的比例(0.2 尖一些, 0.5 更圆润)。
 */
class RoundedPolygonShape(
    private val sides: Int,
    private val round: Float = 0.35f,
) : Shape {

    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val r = min(size.width, size.height) / 2f
        val cx = size.width / 2f
        val cy = size.height / 2f
        val step = (2.0 * PI / sides).toFloat()
        val verts = List(sides) { i ->
            val a = (-PI / 2 + i * step).toFloat()
            Offset(cx + r * cos(a), cy + r * sin(a))
        }
        // 沿两条边各收进来的比例: 由倒角半径换算, 夹住不让相邻倒角打架
        val inset = (round * step).coerceIn(0.06f, 0.45f)
        val path = Path()
        for (i in verts.indices) {
            val p = verts[i]
            val prev = verts[(i - 1 + sides) % sides]
            val next = verts[(i + 1) % sides]
            val a = Offset(p.x + (prev.x - p.x) * inset, p.y + (prev.y - p.y) * inset)
            val b = Offset(p.x + (next.x - p.x) * inset, p.y + (next.y - p.y) * inset)
            if (i == 0) path.moveTo(a.x, a.y) else path.lineTo(a.x, a.y)
            path.quadraticTo(p.x, p.y, b.x, b.y)
        }
        path.close()
        return Outline.Generic(path)
    }
}

object BadgeShapes {
    /** 九边饼干: 徽标主形状 */
    val Cookie = RoundedPolygonShape(sides = 9, round = 0.30f)

    /** 斜切六边形: 与品牌图标的六边形外框同源 */
    val Hex = RoundedPolygonShape(sides = 6, round = 0.18f)
}
