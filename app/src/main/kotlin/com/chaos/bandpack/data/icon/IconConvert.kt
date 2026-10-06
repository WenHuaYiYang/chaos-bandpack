package com.chaos.bandpack.data.icon

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import com.chaos.bandpack.data.DeviceTarget

/**
 * 任意图片 -> 手环桌面图标（112x112，BGRA，50188 字节）。
 *
 * 几何完全照 PC 侧 `scripts/gen_delta_icons.py`，两端口径必须一致：
 * 外接方框按 alpha > [ALPHA_HIT] 取，方框内 alpha > [ALPHA_PLATE] 的比例就是"底板覆盖率"；
 * 覆盖率过低说明是透明底裸图形（贴上桌面会比系统图标小一圈），直接拒绝并说明原因。
 * 配平方式是**外沿齐平**——所有底板的外接方框统一缩到内容框 [IconSpec.CONTENT]，
 * 不是面积相等。这是看过对照图后定的，也符合"只等比缩放、不补底不切圆角"的纪律。
 *
 * 与 PC 侧唯一的有意差异：缩放走**预乘 alpha**（先乘 alpha 再插值，最后除回来）。
 * PIL 是四个通道各自独立插值的，透明像素的 RGB 会渗进边缘形成暗边；预乘能消掉这个
 * 暗边。两者在本仓库那批带底板的图上差别只在圆角处几个像素，但用户随手选的图
 * （带阴影、带羽化）差别就明显了，所以这里选更正确的那个。
 */
object IconConvert {

    /** 认定"这里有内容"的 alpha 门（与 PC 侧取同一个值） */
    const val ALPHA_HIT = 24

    /** 认定"这里是实心底板"的 alpha 门 */
    const val ALPHA_PLATE = 200

    /** 低于此覆盖率判为透明底裸图形 */
    const val PLATE_MIN_COVERAGE = 0.55

    private const val LANCZOS_A = 3.0

    data class Report(
        val coverage: Double,
        val srcBoxSide: Int,
        val scaled: Int,
    )

    /** 源图全透明 */
    class Blank : Exception("这张图整幅都是透明的，没有可用的内容")

    /** 透明底裸图形：贴到桌面会比系统图标小一圈 */
    class NoPlate(val coverage: Double) : Exception(
        "这张图没有底板（内容只占方框的 %.0f%%），贴到桌面会比系统图标小一圈。"
            .format(coverage * 100) + "请换一张自带底色的图。"
    )

    /**
     * [src] 为 ARGB_8888 的像素（`Bitmap.getPixels` 的格式），行优先，长度按 w*h 算。
     * 返回图标字节流与统计。源图尺寸没有硬性上限，但超过约 2000px 时解码端应先降采样，
     * 否则缩放这一步的内存与耗时都不划算。
     */
    fun convert(src: IntArray, w: Int, h: Int, slot: IconSpec.Slot = IconSpec.DESKTOP.first()): Pair<ByteArray, Report> {
        if (slot.group != IconSpec.Group.DESKTOP) return convertSystem(src, w, h, slot)
        require(w > 0 && h > 0 && src.size >= w * h) { "像素数组与尺寸不匹配" }

        // 1. 外接方框（alpha > ALPHA_HIT）
        var x0 = w
        var x1 = -1
        var y0 = h
        var y1 = -1
        for (y in 0 until h) {
            val row = y * w
            for (x in 0 until w) {
                if ((src[row + x] ushr 24) > ALPHA_HIT) {
                    if (x < x0) x0 = x
                    if (x > x1) x1 = x
                    if (y < y0) y0 = y
                    if (y > y1) y1 = y
                }
            }
        }
        if (x1 < 0) throw Blank()

        // 取正方形外接框，长边贴齐画幅时向内收，避免裁到图外
        var side = max(x1 - x0, y1 - y0) + 1
        side = min(side, min(w, h))
        val cx = (x0 + x1 + 1) / 2
        val cy = (y0 + y1 + 1) / 2
        val bx = max(0, min(cx - side / 2, w - side))
        val by = max(0, min(cy - side / 2, h - side))

        // 2. 底板覆盖率：方框内 alpha > ALPHA_PLATE 的比例
        var opaque = 0
        for (y in by until by + side) {
            val row = y * w
            for (x in bx until bx + side) {
                if ((src[row + x] ushr 24) > ALPHA_PLATE) opaque++
            }
        }
        val coverage = opaque.toDouble() / (side * side)
        if (coverage <= PLATE_MIN_COVERAGE) throw NoPlate(coverage)

        // 3. 只缩放，不重画：方框 -> 内容框
        val fitted = scaleBox(src, w, bx, by, side, slot.content)

        // 4. 居中贴到画布，透明边自然成为桌面间距
        val canvas = IntArray(slot.width * slot.height)
        val off = (slot.width - slot.content) / 2
        for (y in 0 until slot.content) {
            val srcRow = y * slot.content
            val dstRow = (y + off) * slot.width + off
            System.arraycopy(fitted, srcRow, canvas, dstRow, slot.content)
        }

        return encode(canvas, slot) to Report(coverage, side, slot.content)
    }

    private fun convertSystem(src: IntArray, w: Int, h: Int, slot: IconSpec.Slot): Pair<ByteArray, Report> {
        require(w > 0 && h > 0 && src.size >= w * h) { "像素数组与尺寸不匹配" }
        var x0 = w; var y0 = h; var x1 = -1; var y1 = -1
        for (y in 0 until h) for (x in 0 until w) if (src[y * w + x] ushr 24 != 0) {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        if (x1 < 0) throw Blank()
        val side = max(x1 - x0 + 1, y1 - y0 + 1)
        val square = IntArray(side * side)
        val dx = (side - (x1 - x0 + 1)) / 2
        val dy = (side - (y1 - y0 + 1)) / 2
        for (y in y0..y1) System.arraycopy(src, y * w + x0, square, (y - y0 + dy) * side + dx, x1 - x0 + 1)
        val scaled = scaleBox(square, side, 0, 0, side, slot.content)
        val coverage = square.count { it ushr 24 > ALPHA_PLATE }.toDouble() / square.size
        val canvas = IntArray(slot.width * slot.height)
        val ox = (slot.width - slot.content) / 2; val oy = (slot.height - slot.content) / 2
        for (y in 0 until slot.content) System.arraycopy(scaled, y * slot.content, canvas, (y + oy) * slot.width + ox, slot.content)
        return encode(canvas, slot) to Report(coverage, side, slot.content)
    }

    private fun encode(pixels: IntArray, slot: IconSpec.Slot): ByteArray =
        if (slot.device == DeviceTarget.NINE_PRO) LvglIconCodec.bgra8(pixels, slot.width, slot.height)
        else LvglIconCodec.bgra(pixels, slot.width, slot.height)

    internal fun resizeSquare(pixels: IntArray, side: Int, to: Int): IntArray = scaleBox(pixels, side, 0, 0, side, to)

    // ===== 缩放 =====

    /**
     * 从 [src] 里取出 [side]x[side] 的方框（左上角 [bx],[by]），等比缩放到 [dst]x[dst]。
     * Lanczos-3，可分离（先横后竖），预乘 alpha。
     */
    private fun scaleBox(
        src: IntArray, srcW: Int, bx: Int, by: Int, side: Int, dst: Int,
    ): IntArray {
        if (side == dst) {
            val out = IntArray(dst * dst)
            for (y in 0 until dst) {
                System.arraycopy(src, (by + y) * srcW + bx, out, y * dst, dst)
            }
            return out
        }

        val k = weights(side, dst)

        // 横pass：预乘成 4 个浮点通道(r,g,b 已乘 alpha, a 原样)
        val horiz = FloatArray(dst * side * 4)
        for (y in 0 until side) {
            val row = (by + y) * srcW + bx
            for (x in 0 until dst) {
                var r = 0.0
                var g = 0.0
                var b = 0.0
                var a = 0.0
                val base = x * k.n
                for (j in 0 until k.n) {
                    val w = k.wgt[base + j].toDouble()
                    if (w == 0.0) continue
                    val p = src[row + k.idx[base + j]]
                    val pa = (p ushr 24) and 0xFF
                    val f = w * pa
                    r += ((p ushr 16) and 0xFF) * f
                    g += ((p ushr 8) and 0xFF) * f
                    b += (p and 0xFF) * f
                    a += f
                }
                val o = (y * dst + x) * 4
                horiz[o] = r.toFloat()
                horiz[o + 1] = g.toFloat()
                horiz[o + 2] = b.toFloat()
                horiz[o + 3] = a.toFloat()
            }
        }

        // 竖pass
        val out = IntArray(dst * dst)
        for (x in 0 until dst) {
            for (y in 0 until dst) {
                var r = 0.0
                var g = 0.0
                var b = 0.0
                var a = 0.0
                val base = y * k.n
                for (j in 0 until k.n) {
                    val w = k.wgt[base + j].toDouble()
                    if (w == 0.0) continue
                    val o = (k.idx[base + j] * dst + x) * 4
                    r += horiz[o] * w
                    g += horiz[o + 1] * w
                    b += horiz[o + 2] * w
                    a += horiz[o + 3] * w
                }
                // 除回来：r/g/b 累加时已经乘过 alpha(0..255)，直接除以 alpha 累加值
                // 就得到 alpha 加权平均色，再取整成 0..255
                val inv = if (a > 1e-6) 1.0 / a else 0.0
                out[y * dst + x] = (clamp255(a) shl 24) or
                    (clamp255(r * inv) shl 16) or
                    (clamp255(g * inv) shl 8) or
                    clamp255(b * inv)
            }
        }
        return out
    }

    private fun clamp255(v: Double): Int = when {
        v <= 0.0 -> 0
        v >= 255.0 -> 255
        else -> (v + 0.5).toInt()
    }

    /** 一维重采样权重表：dst 个输出点，每个固定取 [n] 个源点（不足的补 0 权重） */
    private class Weights(val idx: IntArray, val wgt: FloatArray, val n: Int)

    /**
     * 标准抗锯齿重采样：输出点 ox 对应源坐标 c = (ox+0.5)*scale-0.5，
     * 核宽随缩放比放大 —— 下采样时它是低通滤波，不放大就会采样不足出现摩尔纹。
     *
     * 权重按"权重和"归一化；越界的源点按边缘像素钳制（相当于复制边界），
     * 归一化用的是钳制前的原始权重和，所以边缘不会变暗。
     */
    private fun weights(size: Int, dst: Int): Weights {
        val scale = size.toDouble() / dst
        val filterScale = max(1.0, scale)
        val support = LANCZOS_A * filterScale
        val n = floor(2 * support).toInt() + 3
        val idx = IntArray(dst * n)
        val wgt = FloatArray(dst * n)
        for (ox in 0 until dst) {
            val c = (ox + 0.5) * scale - 0.5
            val lo = ceil(c - support).toInt()
            val hi = floor(c + support).toInt()
            var sum = 0.0
            var j = 0
            for (i in lo..hi) {
                if (j >= n) break
                val w = lanczos((i - c) / filterScale)
                idx[ox * n + j] = i.coerceIn(0, size - 1)
                wgt[ox * n + j] = w.toFloat()
                sum += w
                j++
            }
            if (sum != 0.0 && sum != 1.0) {
                val inv = 1.0 / sum
                for (q in 0 until j) wgt[ox * n + q] = (wgt[ox * n + q] * inv).toFloat()
            }
        }
        return Weights(idx, wgt, n)
    }

    /** Lanczos-3 核 */
    private fun lanczos(x: Double): Double {
        if (x == 0.0) return 1.0
        val ax = abs(x)
        if (ax >= LANCZOS_A) return 0.0
        val px = PI * x
        return LANCZOS_A * sin(px) * sin(px / LANCZOS_A) / (px * px)
    }

    // ===== 打包 =====

    /** ARGB -> 固件要的 BGRA 字节流（前面加 12 字节头） */
    private fun pack(argb: IntArray): ByteArray {
        val out = ByteArray(IconSpec.OUT_BYTES)
        System.arraycopy(IconSpec.HEADER, 0, out, 0, IconSpec.HEADER.size)
        var o = IconSpec.HEADER.size
        for (p in argb) {
            out[o] = (p and 0xFF).toByte()          // B
            out[o + 1] = ((p ushr 8) and 0xFF).toByte()   // G
            out[o + 2] = ((p ushr 16) and 0xFF).toByte()  // R
            out[o + 3] = ((p ushr 24) and 0xFF).toByte()  // A
            o += 4
        }
        return out
    }
}
