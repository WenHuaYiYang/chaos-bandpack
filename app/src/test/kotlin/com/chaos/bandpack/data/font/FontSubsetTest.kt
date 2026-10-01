package com.chaos.bandpack.data.font

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/**
 * 字体子集化的 JVM 侧校验。
 *
 * 源字体不在本机时整条测试跳过（[assumeTrue]）—— 25MB 的字体不该进仓库，
 * 换机器跑就跳过，不算失败。
 *
 * 除了"产出能不能用"，这里还独立复核两件最容易写错、又最难在真机上发现的事：
 * 1) head.checkSumAdjustment —— 直接按整文件重算，必须回到 0xB1B0AFBA；
 * 2) 复合字形的分量 gid —— 必须落在新字体的字序号范围内（漏改会画出乱七八糟的偏旁）。
 *
 * 产出会写到 `app/build/font-check/`，PC 侧再用 fontTools 交叉验一遍
 * （两端实现互为对照，单靠自读自写会一起错）。
 */
class FontSubsetTest {

    private fun srcFile(): File = File(
        System.getProperty("chaos.font.src")
            ?: File(System.getProperty("user.home"), "Downloads/LXGWWenKai-Regular.ttf").path
    )

    @Test
    fun `硬要求字符集只含汉字与ASCII`() {
        // 口径锚点: GB2312 全表 6763 字。数字对不上说明取字范围写错了。
        // 单独一条测试、不依赖源字体存在 —— 之前这两行断言写在要读字体的测试里，
        // 本机没有字体时被 assumeTrue 整条跳过，Android 上混进私用区的事就没被测出来。
        assertEquals("GB2312 字符集大小与 PC 侧脚本不一致", 6763, Charset.gb2312.size)
        assertEquals("硬要求字符数应为 GB2312 + 95 个可打印 ASCII", 6858, Charset.required.size)
        // 真机崩点: Android 的 GB2312/GBK 把区 16..87 的 5 个空位(D7FA..D7FE)映射成
        // GB18030 私用区 U+E810..U+E814, 还能原样编回去 -> 混进"汉字硬要求"，
        // 于是任何第三方中文字体都被判"缺 5 个必需字符"。
        assertTrue("GB2312 里混进了非汉字码点: " +
                Charset.gb2312.filter { it !in 0x4E00..0x9FFF }.take(5),
            Charset.gb2312.all { it in 0x4E00..0x9FFF })
        assertTrue("硬要求里混进了私用区", Charset.required.none { it in 0xE000..0xF8FF })
    }

    @Test
    fun `子集化霞鹜文楷并自校验`() {
        val src = srcFile()
        assumeTrue("源字体不在本机，跳过: ${src.path}", src.isFile)

        val srcBytes = src.readBytes()
        val (out, rep) = FontSubset.subset(srcBytes)

        val dst = File(
            System.getProperty("chaos.font.out")
                ?: File("build/font-check/lxgw-wenkai-band.ttf").path
        )
        dst.parentFile?.mkdirs()
        dst.writeBytes(out)

        println("源 ${rep.srcBytes / 1024} KB -> 产出 ${rep.outBytes / 1024} KB, " +
            "字形 ${rep.srcGlyphs} -> ${rep.outGlyphs}, cmap ${rep.cmapChars} 字")
        println("保留表: ${rep.keptTables.joinToString(" ")}")
        println("丢弃表: ${rep.droppedTables.joinToString(" ")}")
        rep.notes.forEach { println("注: $it") }
        println("产出: ${dst.absolutePath}")

        assertTrue("产出没能覆盖硬要求字符", rep.cmapChars >= Charset.required.size)
        assertTrue("产出字形数异常: 既没带上标点也没带汉字", rep.outGlyphs in 6000..9000)

        // ---- 独立复核产出 ----
        val f = Sfnt(out)

        // 1. 表目录偏移 4 字节对齐(规范要求)
        f.tables.forEach { (tag, t) ->
            assertEquals("表 $tag 偏移未 4 字节对齐", 0, t.offset % 4)
        }

        // 2. head.checkSumAdjustment: 整文件按大端 u32 求和必须回到魔数
        val sum = (0 until out.size step 4).sumOf { i ->
            (0 until 4).fold(0L) { acc, k ->
                (acc shl 8) or (if (i + k < out.size) out[i + k].toLong() and 0xFF else 0L)
            }
        } and 0xFFFFFFFFL
        assertEquals("head.checkSumAdjustment 不正确, 整文件校验和不为魔数",
            0xB1B0AFBAL, sum)

        // 3. cmap 覆盖: 源字体有、我们想要的字符, 产出里必须都能查到非 0 字形。
        //    硬要求(GB2312+ASCII)再单独全量验一遍 —— 这是"能不能用"的分界线。
        val s0 = Sfnt(srcBytes)
        val srcCmap = s0.cmap()
        val cmap = f.cmap()
        val n = f.numGlyphs()
        val dead = Charset.target(Charset.Kind.SIMPLIFIED)
            .filter { it in srcCmap && (cmap[it] ?: 0) !in 1 until n }
        assertEquals("产出字体缺字符", emptyList<Int>(), dead)
        for (c in Charset.required) {
            assertTrue("必需字符 U+%04X 没有字形".format(c), (cmap[c] ?: 0) in 1 until n)
        }

        // 4. loca 单调不减, 且末项就是 glyf 表长度(已 4 字节对齐)
        val loca = f.locaOffsets()
        for (i in 0 until n) {
            assertTrue("loca 第 $i 项回退", loca[i] <= loca[i + 1])
        }
        assertEquals("loca 末项与 glyf 长度不符", f.need("glyf").length, loca[n])

        // 5. 逐字形可解析, 复合字形的分量 gid 必须在新范围内
        val glyf = f.slice(f.need("glyf"))
        var composites = 0
        for (gid in 0 until n) {
            val g = f.glyph(glyf, loca, gid)
            if (g.isEmpty()) continue
            if (g[0].toInt() >= 0) continue
            composites++
            val comps = compositeComponents(g)
            assertTrue("复合字形 $gid 没有分量", comps.isNotEmpty())
            for (c in comps) {
                assertTrue("复合字形 $gid 的分量 $c 越界(共 $n 个字形)", c in 0 until n)
            }
        }
        println("复合字形 $composites 个, 分量 gid 全部在范围内")

        // 6. hmtx 与 hhea 的自洽
        assertEquals("hhea.numberOfHMetrics 应为新字形数", n, f.numHMetrics())
        assertEquals("hmtx 长度应为 4 * 字形数", n * 4, f.need("hmtx").length)

        // 7. post 必须降到 3.0(不存字形名, 否则新字序号配旧名字)
        val post = f.slice(f.need("post"))
        assertEquals("post 未降到 3.0", 0x00030000L,
            (0 until 4).fold(0L) { a, k -> (a shl 8) or (post[k].toLong() and 0xFF) })

        // 8. .notdef 必须原样留在 0 号(gid 顺序被重排过, 很容易被挤到别处),
        //    且没有任何字符指向它 —— 指过去就等于显示成空白框。
        //    产出里的字形尾部会补 4 字节对齐的 0, 比对只比内容, 填充单独确认。
        val g0s = s0.glyph(s0.slice(s0.need("glyf")), s0.locaOffsets(), 0)
        val g0o = f.glyph(glyf, loca, 0)
        assertTrue(".notdef 被截短了", g0o.size >= g0s.size)
        assertTrue(".notdef 没被原样保留", g0o.copyOfRange(0, g0s.size).contentEquals(g0s))
        assertTrue(".notdef 的对齐填充不是 0",
            g0o.copyOfRange(g0s.size, g0o.size).all { it == 0.toByte() })
        assertEquals("有字符指到了 .notdef(0 号)", emptyMap<Int, Int>(), cmap.filterValues { it == 0 })
    }

    @Test
    fun `CFF 字体被明确拒绝`() {
        // OTTO 魔数 + 合法表目录, 不必是真字体 —— 只要在解析开头就被挡住
        val b = ByteArray(64)
        b[0] = 'O'.code.toByte(); b[1] = 'T'.code.toByte()
        b[2] = 'T'.code.toByte(); b[3] = 'O'.code.toByte()
        b[4] = 0; b[5] = 1
        val e = runCatching { Sfnt(b) }.exceptionOrNull()
        assertTrue("OTTO 应被拒绝", e is SfntError)
        assertTrue("拒绝理由应说明只做 TrueType 轮廓", e!!.message!!.contains("TrueType"))
    }

    // ===== 5. 垂直度量归一化 =====

    private fun be16(b: ByteArray, o: Int) = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)
    private fun beI16(b: ByteArray, o: Int) = be16(b, o).toShort().toInt()

    @Test
    fun `度量归一化把行高比对齐到系统字体`() {
        val src = srcFile()
        assumeTrue("源字体不在本机，跳过: ${src.path}", src.isFile)
        val srcBytes = src.readBytes()
        val (out, rep) = FontSubset.subset(srcBytes, FontSubset.Options(normalizeMetrics = true))

        val f = Sfnt(out)
        val upm = f.headInfo().first
        val k = upm.toDouble() / Metrics.MI_UPM

        // head 是 1:1 搬运的, upm 不该变
        assertEquals("upm 被改了", Sfnt(srcBytes).headInfo().first, upm)

        val hhea = f.slice(f.need("hhea"))
        assertEquals("hhea.ascent 未归一化", Math.round(Metrics.MI_ASC * k).toInt(), beI16(hhea, 4))
        assertEquals("hhea.descent 未归一化", Math.round(Metrics.MI_DESC * k).toInt(), beI16(hhea, 6))
        assertEquals("hhea.lineGap 未归零", 0, beI16(hhea, 8))

        val os2 = f.slice(f.need("OS/2"))
        assertEquals("OS/2 typoAscender 未归一化", Math.round(Metrics.MI_TYPO_ASC * k).toInt(), beI16(os2, 68))
        assertEquals("OS/2 typoDescender 未归一化", Math.round(Metrics.MI_TYPO_DESC * k).toInt(), beI16(os2, 70))
        assertEquals("OS/2 typoLineGap 未归一化", Math.round(Metrics.MI_TYPO_GAP * k).toInt(), beI16(os2, 72))
        assertEquals("OS/2 winAscent 未归一化", Math.round(Metrics.MI_ASC * k).toInt(), be16(os2, 74))
        assertEquals("OS/2 winDescent 未归一化", Math.round(-Metrics.MI_DESC * k).toInt(), be16(os2, 76))
        assertEquals("USE_TYPO_METRICS 位没清掉", 0,
            be16(os2, 62) and Metrics.USE_TYPO_METRICS)

        // 关掉开关时必须一个字段都不动(用户可选项, 不选就是原样)
        val (raw, repRaw) = FontSubset.subset(srcBytes, FontSubset.Options(normalizeMetrics = false))
        assertEquals("关归一化时不该有度量报告", null, repRaw.metrics)
        val hheaRaw = Sfnt(raw).slice(Sfnt(raw).need("hhea"))
        assertEquals("关归一化时 hhea.ascent 被改了",
            beI16(Sfnt(srcBytes).slice(Sfnt(srcBytes).need("hhea")), 4), beI16(hheaRaw, 4))
    }

    // ===== 6. 繁体字集 =====

    @Test
    fun `繁体字集规模与取字范围正确`() {
        // Big5 常用 5401 + 次常用 7652 = 13053(去重后按 Android 解码器的实际结果)
        val n = Charset.big5.size
        assertTrue("Big5 字号异常: $n", n in 12500..13300)
        assertTrue("繁体集里混进了非汉字", Charset.big5.all { it in 0x4E00..0x9FFF })
        assertTrue("繁体集里混进了私用区", Charset.big5.none { it in 0xE000..0xF8FF })
        // 抽查几个常见繁体字必须在
        for (s in listOf("們", "為", "國", "學", "臺", "龍")) {
            assertTrue("繁体集缺 $s", s[0].code in Charset.big5)
        }
        // 两档的规模关系
        val simp = Charset.target(Charset.Kind.SIMPLIFIED)
        val trad = Charset.target(Charset.Kind.WITH_TRADITIONAL)
        assertTrue("保留繁体档没有变大", trad.size > simp.size)
        assertTrue("繁体档规模异常: ${trad.size}", trad.size > 15000)
    }

    @Test
    fun `保留繁体档产出里真的有繁体字形`() {
        val src = srcFile()
        assumeTrue("源字体不在本机，跳过: ${src.path}", src.isFile)
        val srcBytes = src.readBytes()
        val (out, rep) = FontSubset.subset(srcBytes, FontSubset.Options(Charset.Kind.WITH_TRADITIONAL))
        val f = Sfnt(out)
        val cmap = f.cmap()
        val n = f.numGlyphs()
        val sample = listOf("們", "為", "國", "學")
        for (s in sample) {
            val c = s[0].code
            assertTrue("$s 在源字体里本来就该有", c in Sfnt(srcBytes).cmap())
            assertTrue("保留繁体档产出里缺 $s", (cmap[c] ?: 0) in 1 until n)
        }
        // 精简档不该带繁体(证明两档真的不同, 不是开关没接上)
        val (simp, _) = FontSubset.subset(srcBytes, FontSubset.Options(Charset.Kind.SIMPLIFIED))
        val simpCmap = Sfnt(simp).cmap()
        assertTrue("精简档里也带了繁体, 说明档位没生效", (simpCmap["們"[0].code] ?: 0) == 0)
        println("繁体覆盖: 源字体里 ${rep.traditional} 个 Big5 字, 产出 ${rep.outGlyphs} 字形")
    }
}
