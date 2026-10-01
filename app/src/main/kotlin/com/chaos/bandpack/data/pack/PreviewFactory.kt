package com.chaos.bandpack.data.pack

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

/**
 * 预览块工厂 —— 与 PC 侧 `scripts/gen_preview.py` 同口径的 Kotlin 实现。
 *
 * 每个投递包的预览块 = **各自表盘运行界面的 1:1 复刻**(真实表盘容器的惯例,
 * 参考 archive/watchface_qiyan_bw.bin): 布局/颜色/圆角全部取自各自 Lua 的真实参数
 * (installer: chaos_installer.lua / font: font_pack.lua / icon: icon_pack.lua)。
 *
 * 文字字体**必须用 MiSans**: assets/fonts/MiSans-Regular-subset.ttf 是 MiSans-Regular 的
 * GB2312+ASCII 子集(1.6MB)。MiSans 是小米的免费商用字体, 内嵌使用需在软件中注明
 * 使用了 MiSans 字体 —— 见 THIRD_PARTY_NOTICES.md 与应用内"开源许可"页,
 * 覆盖预览的全部固定文案与任意中文/ASCII 短名; 加载失败回退系统 sans-serif。
 *
 * 编码: 256 色调色板(BGRA) + 小米 RLE, 与固件解压函数(0x0CA91EC4)逐条对齐 ——
 * 格式细节见 PC 侧 gen_preview.py: 外层 12B(cf=0x10 厂商格式, flags=0x04 压缩
 * 分支, w, h, 数据长), 数据区 = 魔数 0x5AA521E0 + u32(低 4 位单元字节数 m=1,
 * bits4..27 解压总长 T=1024+w*h) + RLE 流(控制字节<0x80 重复 m 字节,
 * >=0x80 字面拷贝 (c&0x7F)*m 字节), 解压输出 1024B 调色板 + w*h 索引。
 *
 * 两条踩过的红线(PC 侧同款, 不得回退):
 *   1. 可见像素一律**不透明**(预合成观感), 只留页面圆角外 a<VIS_MIN 透明 ——
 *      半透明 ramp 阶梯会在多圆角对象上产生黑晕;
 *   2. 可见像素直接量化位图的预乘 RGB, **禁止再做 rgb*a/255**(二次预乘会把
 *      边缘压成黑点/白点)。
 */
object PreviewFactory {
    const val W = 336
    const val H = 480
    private const val RADIUS = 48f          // 贴屏圆角: 从真实表盘容器逐像素拟合
    private const val MAGIC = 0x5AA521E0
    private val PAGE = intArrayOf(0x1C, 0x1C, 0x1E)          // 页底 #1C1C1E
    private val BRAND_BLUE = intArrayOf(0x2A, 0x82, 0xE4)
    private val BRAND_YELLOW = intArrayOf(0xFF, 0xC3, 0x00)

    @Volatile
    private var cachedTypeface: Typeface? = null

    enum class BtnStyle { PRIMARY, DANGER }

    // ===== 三套界面的入口(文案与各自 Lua 一致) =====

    fun installerBlob(assets: AssetManager? = null): ByteArray = buildBlob(
        assets, title = "Chaos 安装器", status = "准备就绪",
        buttons = listOf("运行" to BtnStyle.PRIMARY, "清除重置" to BtnStyle.DANGER),
    )

    fun fontBlob(assets: AssetManager? = null, title: String): ByteArray = buildBlob(
        assets, title = title, status = "已加载",
        buttons = listOf("投递字体" to BtnStyle.PRIMARY),
    )

    fun iconBlob(assets: AssetManager? = null, title: String, short: String): ByteArray = buildBlob(
        assets, title = title, status = "$short 已加载",
        buttons = listOf("投递图标" to BtnStyle.PRIMARY),
    )

    fun buildBlob(
        assets: AssetManager? = null, title: String, status: String,
        buttons: List<Pair<String, BtnStyle>>,
    ): ByteArray {
        val img = draw(assets, title, status, buttons)
        val (indices, palette) = quantize(img)
        val blob = encode(indices, palette)
        // roundtrip 自校验: 解码器镜像固件逻辑, 索引必须逐像素还原
        val (_, _, px) = decodeBlock(blob)
        require(px.contentEquals(indices)) { "预览块 roundtrip 失败" }
        return blob
    }

    // ===== 绘制(android.graphics, 自带抗锯齿) =====

    private fun miSans(assets: AssetManager?): Typeface {
        cachedTypeface?.let { return it }
        val tf = try {
            // assets 里是 MiSans-Regular 的 GB2312+ASCII 子集(任意中文短名不缺字)
            assets?.let { Typeface.createFromAsset(it, "fonts/MiSans-Regular-subset.ttf") }
                ?: Typeface.SANS_SERIF
        } catch (_: Exception) {
            Typeface.SANS_SERIF
        }
        cachedTypeface = tf
        return tf
    }

    private fun draw(
        assets: AssetManager?, title: String, status: String,
        buttons: List<Pair<String, BtnStyle>>,
    ): Bitmap {
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val tf = miSans(assets)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 1f
        }

        fun rgb(r: Int, g: Int, b: Int) = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

        fun card(cx: Float, cy: Float, w: Float, h: Float, bg: Int, line: Int) {
            fill.color = bg
            c.drawRoundRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, 24f, 24f, fill)
            if (line != bg) {
                stroke.color = line
                c.drawRoundRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, 24f, 24f, stroke)
            }
        }

        fun text(s: String, cx: Float, cy: Float, size: Float, color: Int) {
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color; this.textSize = size; this.textAlign = Paint.Align.CENTER
            }
            // 显式 p.typeface —— 裸写 typeface 会被解析成外层同名函数引用(赋值报 val)
            p.typeface = tf
            val fm = p.fontMetrics
            c.drawText(s, cx, cy - (fm.ascent + fm.descent) / 2f, p)
        }

        // 页面底(圆角 = 贴屏口径)
        fill.color = rgb(PAGE[0], PAGE[1], PAGE[2])
        c.drawRoundRect(0f, 0f, W.toFloat(), H.toFloat(), RADIUS, RADIUS, fill)

        // 标题(align CENTER, y_ofs=-170) + 状态卡片(y_ofs=-20) + 卡内状态文字
        text(title, 168f, 240f - 170f, 40f, rgb(0xF2, 0xF2, 0xF2))
        card(168f, 240f - 20f, 304f, 150f, rgb(0x2C, 0x2C, 0x2E), rgb(0x3C, 0x3C, 0x3E))
        text(status, 168f, 240f - 20f, 22f, rgb(0xB3, 0xB3, 0xB3))

        // 按钮: 单个 y=+110, 两个 y=+110/+186(与各自 Lua 的 align 一致)
        val ys = if (buttons.size == 1) floatArrayOf(110f) else floatArrayOf(110f, 186f)
        buttons.forEachIndexed { i, (btnText, style) ->
            val yOfs = ys[i]
            if (style == BtnStyle.PRIMARY) {
                card(168f, 240f + yOfs, 304f, 64f, rgb(0x25, 0x63, 0xEB), rgb(0x25, 0x63, 0xEB))
                text(btnText, 168f, 240f + yOfs, 24f, rgb(0xF2, 0xF2, 0xF2))
            } else {  // danger: 页底与红按 15% 混, 红字
                val red = intArrayOf(0xFF, 0x45, 0x3A)
                val mix = IntArray(3) { j -> PAGE[j] + ((red[j] - PAGE[j]) * 0.15f).toInt() }
                card(168f, 240f + yOfs, 304f, 64f, rgb(mix[0], mix[1], mix[2]), rgb(mix[0], mix[1], mix[2]))
                text(btnText, 168f, 240f + yOfs, 24f, rgb(0xFF, 0x45, 0x3A))
            }
        }
        return bmp
    }

    // ===== 量化: 预乘 RGB 直接入 5bit 网格桶(高频代表色), 可见门限 16 =====

    private fun qkey(r: Int, g: Int, b: Int) = ((r shr 3) shl 12) or ((g shr 3) shl 6) or (b shr 3)

    private fun quantize(bmp: Bitmap): Pair<ByteArray, List<IntArray>> {
        val px = IntArray(W * H)
        bmp.getPixels(px, 0, W, 0, 0, W, H)
        val visMin = 16
        val counts = HashMap<Int, Int>()
        val repr = HashMap<Int, IntArray>()
        for (p in px) {
            val a = (p ushr 24) and 0xFF
            if (a < visMin) continue                 // 页面圆角外 → 透明
            val r = (p ushr 16) and 0xFF
            val g = (p ushr 8) and 0xFF
            val b = p and 0xFF
            val k = qkey(r, g, b)
            counts[k] = (counts[k] ?: 0) + 1
            if (k !in repr) repr[k] = intArrayOf(r, g, b)
        }
        val colors = ArrayList<IntArray>()
        counts.entries.sortedByDescending { it.value }.forEach { colors.add(repr[it.key]!!) }
        for (c in listOf(PAGE, BRAND_BLUE, BRAND_YELLOW))
            if (colors.none { it.contentEquals(c) }) colors.add(c)
        val palette = ArrayList<IntArray>()
        palette.add(intArrayOf(0, 0, 0, 0))          // 条目 0 = 透明(页面圆角外)
        for (c in colors) palette.add(intArrayOf(c[2], c[1], c[0], 255))  // B,G,R,A
        require(palette.size <= 256) { "调色板超出 256 色: ${palette.size}" }
        val palIndex = HashMap<Int, Int>()
        colors.forEachIndexed { i, c -> palIndex[qkey(c[0], c[1], c[2])] = i + 1 }
        val indices = ByteArray(W * H)
        for (i in px.indices) {
            val a = (px[i] ushr 24) and 0xFF
            if (a < visMin) continue                 // 透明(ByteArray 初值即 0)
            val r = (px[i] ushr 16) and 0xFF
            val g = (px[i] ushr 8) and 0xFF
            val b = px[i] and 0xFF
            indices[i] = palIndex[qkey(r, g, b)]!!.toByte()
        }
        return indices to palette
    }

    // ===== 编码(与 PC 侧 encode 逐字节同构) =====

    private fun rleEncode(data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        var i = 0
        val n = data.size
        while (i < n) {
            var j = i
            while (j < n && data[j] == data[i]) j++
            var run = j - i
            if (run >= 3) {
                while (run > 0) {
                    val cnt = min(run, 127)
                    out.write(cnt); out.write(data[i].toInt())
                    run -= cnt; i += cnt
                }
            } else {
                var k = i
                while (k < n && k - i < 127) {
                    if (k + 2 < n && data[k] == data[k + 1] && data[k] == data[k + 2]) break
                    k++
                }
                out.write(0x80 or (k - i)); out.write(data, i, k - i)
                i = k
            }
        }
        return out.toByteArray()
    }

    private fun encode(indices: ByteArray, palette: List<IntArray>): ByteArray {
        val total = 1024 + indices.size
        val palBytes = ByteArray(1024)
        var off = 0
        for (c in palette) {
            palBytes[off] = c[0].toByte(); palBytes[off + 1] = c[1].toByte()
            palBytes[off + 2] = c[2].toByte(); palBytes[off + 3] = c[3].toByte()
            off += 4
        }
        val meta = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN)
        meta.putInt(MAGIC)
        meta.putInt(1 or (total shl 4))              // 低 4 位 m=1, bits4..27 解压总长
        val stream = meta.array() + rleEncode(palBytes + indices)
        val head = ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
        head.put(0x10.toByte())                      // cf = 厂商自定义格式
        head.put(0x04.toByte())                      // flags: bits2..4 = 1 → 小米 RLE 压缩分支
        head.putShort(0)
        head.putShort(W.toShort()); head.putShort(H.toShort())
        head.putInt(stream.size)
        return head.array() + stream
    }

    // ===== 解码(镜像固件 0x0CA91EC4, roundtrip 自校验用) =====

    private fun decodeBlock(blob: ByteArray): Triple<Int, Int, ByteArray> {
        require((blob[1].toInt() and 0xFF) == 0x04 && ((blob[1].toInt() shr 2) and 7) == 1) {
            "不是小米 RLE 压缩分支"
        }
        val w = ((blob[4].toInt() and 0xFF) or ((blob[5].toInt() and 0xFF) shl 8))
        val h = ((blob[6].toInt() and 0xFF) or ((blob[7].toInt() and 0xFF) shl 8))
        val dlen = ByteBuffer.wrap(blob, 8, 4).order(ByteOrder.LITTLE_ENDIAN).int
        val data = blob.copyOfRange(12, 12 + dlen)
        val bb = ByteBuffer.wrap(data, 0, 8).order(ByteOrder.LITTLE_ENDIAN)
        require(bb.int == MAGIC) { "预览数据魔数不符" }
        val w1 = ByteBuffer.wrap(data, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
        val m = w1 and 0xF
        val total = (w1 ushr 4) and 0xFFFFFF
        require(m == 1 && total == 1024 + w * h) { "解压总长与规格不符: $total" }
        val out = ByteArray(total)
        var oi = 0
        var i = 8
        while (oi < total) {
            val cmd = data[i].toInt() and 0xFF
            i++
            if (cmd < 0x80) {
                if (cmd > 0) {
                    for (r in 0 until cmd) out[oi + r] = data[i]
                }
                oi += cmd; i += m
            } else {
                val k = (cmd and 0x7F) * m
                System.arraycopy(data, i, out, oi, k)
                oi += k; i += k
            }
        }
        require(oi == total && i == data.size) { "RLE 流长度不符: oi=$oi i=$i" }
        return Triple(w, h, out)
    }
}
