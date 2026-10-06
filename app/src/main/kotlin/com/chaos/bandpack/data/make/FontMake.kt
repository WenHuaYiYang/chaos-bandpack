package com.chaos.bandpack.data.make

import android.content.Context
import android.graphics.Typeface
import com.chaos.bandpack.data.font.FontSubset
import java.io.File

/**
 * 字体处理编排: 源字体 -> (归一化 + 子集化) -> 可预览的产出。
 *
 * 一条纪律: **预览的字体和打进包里的字体必须是同一份字节**。所以这里只做一次子集化,
 * 预览用它、打包也用它 —— 不做"预览用一套、打包另算一套"的事(那等于预览说谎)。
 */
object FontMake {

    class Made(
        val font: ByteArray,
        val report: FontSubset.Report,
        val face: Typeface?,
        val faceFile: File?,
    )

    /**
     * [src] 是源字体字节。跑在后台线程(25MB 字体子集化要几秒)。
     * [cacheDir] 用来落一份临时 ttf 供 [Typeface.createFromFile] 使用。
     */
    fun build(ctx: Context, src: ByteArray, options: FontSubset.Options, preserve: Boolean = false): Made {
        val (out, report) = if (!preserve) FontSubset.subset(src, options) else {
            val font = com.chaos.bandpack.data.font.Sfnt(src)
            val cmap = font.cmap()
            src to FontSubset.Report(src.size, src.size, font.numGlyphs(), font.numGlyphs(), cmap.size,
                com.chaos.bandpack.data.font.Charset.gb2312.size, options.charset,
                com.chaos.bandpack.data.font.Charset.traditionalHits(cmap), null, 0,
                font.tables.keys.sorted(), emptyList(), listOf("保留导入投递包的字体字节，未再次裁剪或归一化"))
        }
        val f = File(ctx.cacheDir, "font_preview.ttf")
        f.writeBytes(out)
        val face = runCatching { Typeface.createFromFile(f) }.getOrNull()
        return Made(out, report, face, f)
    }

    /** 源字体可读性预检(选文件后立刻给反馈, 不等到打包) */
    fun precheck(src: ByteArray): Precheck {
        val sfnt = com.chaos.bandpack.data.font.Sfnt(src)
        val cmap = sfnt.cmap()
        return Precheck(
            glyphs = sfnt.numGlyphs(),
            cmapChars = cmap.size,
            missingRequired = com.chaos.bandpack.data.font.Charset.missingRequiredCount(cmap),
            sample = com.chaos.bandpack.data.font.Charset.missingRequired(cmap),
            traditional = com.chaos.bandpack.data.font.Charset.traditionalHits(cmap),
        )
    }

    class Precheck(
        val glyphs: Int,
        val cmapChars: Int,
        val missingRequired: Int,
        val sample: List<Int>,
        val traditional: Int,
    ) {
        val ok: Boolean get() = missingRequired == 0
        val sampleText: String
            get() = sample.joinToString("、") { "U+%04X".format(it) }
    }
}
