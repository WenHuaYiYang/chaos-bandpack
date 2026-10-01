package com.chaos.bandpack.data.font

import java.io.ByteArrayOutputStream

/**
 * 字体子集化（纯 Kotlin，不依赖 fontTools）。
 *
 * 口径与 PC 侧 `scripts/build_font_subset.py` 一致：字形集合取全 GB2312 + ASCII
 * 可打印 + CJK 标点区，产出后**回读校验 GB2312 覆盖率必须 100%**。
 *
 * 与 PC 侧的差异只有一处，是刻意的：**丢弃排版表**（GSUB/GPOS/GDEF 与 AAT 那套）。
 * 理由：手环端渲染的是界面文字，字体由 `ChaosSans-*` 名字独立登记（见字体线定案），
 * 排版表带来的连字/字距对手环界面没有意义，却要按新字序号逐条重写闭包 ——
 * 那正是最容易出错、最难验证的部分。丢掉的表会在报告里逐个列出来，不藏着。
 */
object FontSubset {

    /** 原样搬运的表（都不含字序号引用） */
    private val COPY = listOf("name", "OS/2", "cvt ", "fpgm", "prep", "gasp")

    data class Report(
        val srcBytes: Int,
        val outBytes: Int,
        val srcGlyphs: Int,
        val outGlyphs: Int,
        val cmapChars: Int,
        val gbTotal: Int,
        val charset: Charset.Kind,
        val traditional: Int,
        val metrics: Metrics.Report?,
        val skippedOptional: Int,
        val keptTables: List<String>,
        val droppedTables: List<String>,
        val notes: List<String>,
    )

    /** 打包选项：字集档位 + 是否做垂直度量归一化（两项都是用户在界面上可选的） */
    data class Options(
        val charset: Charset.Kind = Charset.Kind.SIMPLIFIED,
        val normalizeMetrics: Boolean = true,
    )

    /**
     * 源字体缺硬要求字符（汉字或 ASCII），交不出可用字体。[readable] 是可直接
     * 显示给用户的样例，[sample] 给日志。
     */
    class MissingChars(val count: Int, val sample: List<Int>, val readable: String) :
        Exception("源字体缺 $count 个必需字符（汉字/ASCII），例如 $readable")

    fun subset(src: ByteArray, options: Options = Options()): Pair<ByteArray, Report> {
        val sfnt = Sfnt(src)
        val cmap = sfnt.cmap()

        val missN = Charset.missingRequiredCount(cmap)
        if (missN > 0) {
            val sample = Charset.missingRequired(cmap)
            throw MissingChars(missN, sample, renderSample(sample))
        }
        val missOptional = Charset.missingOptionalCount(cmap, options.charset)

        val numGlyphs = sfnt.numGlyphs()
        val locaO = sfnt.locaOffsets()
        val glyf = sfnt.slice(sfnt.need("glyf"))

        // 1. 保留集: gid0(.notdef) + 目标字符 + 复合字形的分量(传递闭包)
        val keep = sortedSetOf(0)
        for (c in Charset.target(options.charset)) {
            val g = cmap[c] ?: continue
            if (g in 0 until numGlyphs) keep.add(g)
        }
        val queue = ArrayDeque(keep.toList())
        while (queue.isNotEmpty()) {
            val gid = queue.removeFirst()
            for (comp in compositeComponents(sfnt.glyph(glyf, locaO, gid))) {
                if (comp in 0 until numGlyphs && keep.add(comp)) queue.add(comp)
            }
        }
        // 排序: .notdef 固定在 0 号(缺字时渲染器回落的那个字形, 规范要求)。
        // 其余的有码点按最小码点升序, 只被复合字形引用的(无码点)排到最后 ——
        // 这样"码点连续且原 gid 连续"的区段在新字体里仍是连续 gid, cmap 段数最少,
        // 段内只用 idDelta, 也不必担心格式 4 的 64KB 长度上限。
        val firstCp = HashMap<Int, Int>(keep.size * 2)
        for ((c, g) in cmap) {
            if (g !in keep) continue
            val p = firstCp[g]
            if (p == null || c < p) firstCp[g] = c
        }
        val rest = keep.filter { it != 0 }
            .sortedWith(compareBy({ firstCp[it] ?: Int.MAX_VALUE }, { it }))
        val list = IntArray(rest.size + 1)
        list[0] = 0
        rest.forEachIndexed { i, g -> list[i + 1] = g }
        val remap = IntArray(numGlyphs) { -1 }
        list.forEachIndexed { i, g -> remap[g] = i }

        // 2. glyf + loca: 逐字形搬运(复合字形只重写分量表里的字序号)
        val glyfOut = ByteArrayOutputStream(glyf.size / 4)
        val offsets = IntArray(list.size + 1)
        for ((i, gid) in list.withIndex()) {
            offsets[i] = glyfOut.size()
            var g = sfnt.glyph(glyf, locaO, gid)
            if (g.isNotEmpty() && Be(g).i16(0) < 0) g = rewriteComposite(g, { remap[it] })
            glyfOut.write(g)
            while (glyfOut.size() % 4 != 0) glyfOut.write(0)
        }
        offsets[list.size] = glyfOut.size()
        val glyfBytes = glyfOut.toByteArray()
        val longLoca = offsets[list.size] > 0x1FFFF

        // 3. loca
        val locaBytes = ByteArray((list.size + 1) * if (longLoca) 4 else 2)
        for (i in offsets.indices) {
            val v = offsets[i]
            if (longLoca) put32(locaBytes, i * 4, v.toLong()) else put16(locaBytes, i * 2, v / 2)
        }

        // 4. hmtx/hhea: 全量长条目(numGlyphs 条), hhea.numberOfHMetrics 跟着改;
        //    垂直度量归一化也落在这一步 —— 它改的正是 hhea 与 OS/2 的同一批字段
        val hmtxBytes = buildHmtx(sfnt, list)
        val hheaBytes = sfnt.slice(sfnt.need("hhea")).let {
            val b = ensure(it, 36)
            put16(b, 34, list.size)
            b
        }
        // OS/2 单独取出来(后面不再走 COPY 的无脑搬运), 因为它可能要被归一化改写
        val os2Bytes = sfnt.tables["OS/2"]?.let { sfnt.slice(it) }
        val metrics = if (options.normalizeMetrics) {
            Metrics.apply(hheaBytes, os2Bytes, sfnt.headInfo().first)
        } else null

        // 5. head: 只改 indexToLocFormat 与 checkSumAdjustment(后者最后算)
        val headBytes = sfnt.slice(sfnt.need("head")).let {
            val b = ensure(it, 54)
            put16(b, 50, if (longLoca) 1 else 0)
            put32(b, 8, 0)
            b
        }

        // 6. maxp: numGlyphs 改成新值, 其余上限字段沿用(是上界, 仍成立)
        val maxpBytes = sfnt.slice(sfnt.need("maxp")).let {
            val b = ensure(it, 32)
            put16(b, 4, list.size)
            b
        }

        // 7. post: 换成 3.0, 只留 32 字节头。字形名是按旧字序号排的, 留着不但错位,
        //    还是几百 KB 的死重(源字体 post 表 450KB, 其中绝大部分是字形名)。
        val postSrc = sfnt.slice(sfnt.need("post"))
        val postBytes = ByteArray(32)
        System.arraycopy(postSrc, 0, postBytes, 0, minOf(32, postSrc.size))
        put32(postBytes, 0, 0x00030000L)

        // 8. cmap: 一张 (3,1) 格式 4 子表, 覆盖全部目标字符
        val cmapBytes = buildCmap4(cmap, remap, list.size)

        val tables = LinkedHashMap<String, ByteArray>()
        tables["head"] = headBytes
        tables["hhea"] = hheaBytes
        tables["maxp"] = maxpBytes
        tables["hmtx"] = hmtxBytes
        tables["loca"] = locaBytes
        tables["glyf"] = glyfBytes
        tables["cmap"] = cmapBytes
        tables["post"] = postBytes
        for (t in COPY) {
            if (t == "OS/2") {
                os2Bytes?.let { tables[t] = it }
                continue
            }
            sfnt.tables[t]?.let { tables[t] = sfnt.slice(it) }
        }

        val dropped = sfnt.tables.keys.filter { it !in tables }.sorted()
        val out = assemble(tables)

        // 9. 回读校验: 用同一份解析器读产出, 覆盖率必须 100%
        val chk = Sfnt(out)
        val chkCmap = chk.cmap()
        val outGlyphs = chk.numGlyphs()
        // 源字体本来就没有的符号区/繁体字不在检查范围内(见 Charset.missingOptionalCount)
        val still = Charset.target(options.charset).count { c -> c in cmap && (chkCmap[c] ?: 0) !in 1 until outGlyphs }
        if (still != 0) throw SfntError("产出字体自检失败: 仍有 $still 个目标字符缺字形")

        val notes = ArrayList<String>(4)
        if (dropped.any { it == "GSUB" || it == "GPOS" || it == "GDEF" }) {
            notes.add("已丢弃排版表(GSUB/GPOS/GDEF): 手环界面文字用不到连字与字距")
        }
        if (longLoca) notes.add("字形偏移超过 128KB，loca 用了长格式")
        if (missOptional > 0) {
            notes.add("源字体缺 $missOptional 个可选字符(符号区/繁体)，已跳过")
        }
        metrics?.let {
            notes.add("垂直度量已按系统字体比例归一化: 行高比 %.3f -> %.3f".format(it.ratioBefore, it.ratioAfter))
        }

        return out to Report(
            srcBytes = src.size,
            outBytes = out.size,
            srcGlyphs = numGlyphs,
            outGlyphs = outGlyphs,
            cmapChars = chkCmap.size,
            gbTotal = Charset.gb2312.size,
            charset = options.charset,
            traditional = Charset.traditionalHits(cmap),
            metrics = metrics,
            skippedOptional = missOptional,
            keptTables = tables.keys.sorted(),
            droppedTables = dropped,
            notes = notes,
        )
    }

    // ---- hmtx ----

    private fun buildHmtx(sfnt: Sfnt, list: IntArray): ByteArray {
        val h = sfnt.slice(sfnt.need("hmtx"))
        val r = Be(h)
        val nhm = sfnt.numHMetrics()
        if (nhm <= 0 || nhm > sfnt.numGlyphs()) {
            throw SfntError("hhea.numberOfHMetrics 异常: $nhm")
        }
        val out = ByteArray(list.size * 4)
        for ((i, gid) in list.withIndex()) {
            val adv: Int
            val lsb: Int
            if (gid < nhm) {
                adv = r.u16(gid * 4)
                lsb = r.i16(gid * 4 + 2)
            } else {
                // 超出的字形没有自己的 advance, 沿用最后一条(OpenType 规定的读法);
                // lsb 在 hmtx 尾部的数组里, 表被截断时按 0 处理
                adv = r.u16((nhm - 1) * 4)
                val at = nhm * 4 + (gid - nhm) * 2
                lsb = if (at + 1 < h.size) r.i16(at) else 0
            }
            put16(out, i * 4, adv)
            put16(out, i * 4 + 2, lsb and 0xFFFF)
        }
        return out
    }

    // ---- cmap format 4 ----

    /**
     * 段按"码点连续且字序号也连续"切分，段内用 idDelta（不写 glyphIdArray）。
     * 目标字符集里连续区段占绝大多数，段数因此很小；零散字符各成一段也不亏。
     */
    private fun buildCmap4(cmap: Map<Int, Int>, remap: IntArray, numGlyphs: Int): ByteArray {
        val codes = cmap.keys.filter { it in 0..0xFFFE && remap[cmap[it]!!] >= 0 }.sorted()
        val segs = ArrayList<IntArray>(512)   // [start, end, delta]
        var i = 0
        while (i < codes.size) {
            val start = codes[i]
            val g0 = remap[cmap[start]!!]
            var end = start
            var j = i + 1
            while (j < codes.size && codes[j] == end + 1 &&
                remap[cmap[codes[j]]!!] == g0 + (codes[j] - start)
            ) {
                end = codes[j]
                j++
            }
            segs.add(intArrayOf(start, end, (g0 - start) and 0xFFFF))
            i = j
        }
        segs.add(intArrayOf(0xFFFF, 0xFFFF, 1))   // 结束段: 0xFFFF 必须映射到 gid 0

        val segCount = segs.size
        val segX2 = segCount * 2
        val len = 16 + segX2 * 4
        if (len > 0xFFFF) throw SfntError("cmap 段数过多($segCount)，超出行格式 4 的长度上限")
        var p2 = 1
        var sel = 0
        while (p2 * 2 <= segCount) {
            p2 *= 2
            sel++
        }
        val sub = ByteArray(len)
        put16(sub, 0, 4)
        put16(sub, 2, len)
        put16(sub, 4, 0)                 // language
        put16(sub, 6, segX2)
        put16(sub, 8, p2 * 2)            // searchRange = 2 * 2^floor(log2(segCount))
        put16(sub, 10, sel)              // entrySelector = floor(log2(segCount))
        put16(sub, 12, segX2 - p2 * 2)   // rangeShift = 2*segCount - searchRange
        val endB = 14
        val startB = endB + segX2 + 2
        val deltaB = startB + segX2
        val rangeB = deltaB + segX2
        for (k in 0 until segCount) {
            val (s, e, d) = Triple(segs[k][0], segs[k][1], segs[k][2])
            put16(sub, endB + k * 2, e)
            put16(sub, startB + k * 2, s)
            put16(sub, deltaB + k * 2, d)
            put16(sub, rangeB + k * 2, 0)
        }

        val out = ByteArray(12 + len)
        put16(out, 0, 0)                 // version
        put16(out, 2, 1)                 // numTables
        put16(out, 4, 3)                 // platform = Windows
        put16(out, 6, 1)                 // encoding = Unicode BMP
        put32(out, 8, 12L)               // 子表偏移
        System.arraycopy(sub, 0, out, 12, len)
        return out
    }

    // ---- sfnt 组装 ----

    private fun assemble(tables: Map<String, ByteArray>): ByteArray {
        val tags = tables.keys.sorted()
        val n = tags.size
        val dirLen = 12 + n * 16
        val total = dirLen + tables.values.sumOf { (it.size + 3) / 4 * 4 }
        val out = ByteArray(total)
        put32(out, 0, 0x00010000L)
        put16(out, 4, n)
        // searchRange 等三个值是给二分查找用的提示, FreeType 不依赖; 按规范给对
        var p2 = 1
        var entrySel = 0
        while (p2 * 2 <= n) {
            p2 *= 2
            entrySel++
        }
        put16(out, 6, p2 * 16)
        put16(out, 8, entrySel)
        put16(out, 10, n * 16 - p2 * 16)

        var off = dirLen
        val headOff: Int
        var headOffV = -1
        for ((i, tag) in tags.withIndex()) {
            val data = tables[tag]!!
            val dp = 12 + i * 16
            for (k in 0 until 4) out[dp + k] = tag[k].code.toByte()
            put32(out, dp + 4, checksum(data))
            put32(out, dp + 8, off.toLong())
            put32(out, dp + 12, data.size.toLong())
            System.arraycopy(data, 0, out, off, data.size)
            if (tag == "head") headOffV = off
            off += (data.size + 3) / 4 * 4
        }
        headOff = headOffV
        if (headOff < 0) throw SfntError("组装时找不到 head")

        // head.checkSumAdjustment = 0xB1B0AFBA - 整文件校验和(此时该字段为 0)
        var sum = 0L
        var i = 0
        while (i < out.size) {
            var v = 0L
            for (k in 0 until 4) v = (v shl 8) or (if (i + k < out.size) (out[i + k].toLong() and 0xFF) else 0L)
            sum = (sum + v) and 0xFFFFFFFFL
            i += 4
        }
        val adj = (0xB1B0AFBAL - sum) and 0xFFFFFFFFL
        put32(out, headOff + 8, adj)
        return out
    }

    private fun checksum(d: ByteArray): Long {
        var sum = 0L
        var i = 0
        while (i < d.size) {
            var v = 0L
            for (k in 0 until 4) v = (v shl 8) or (if (i + k < d.size) (d[i + k].toLong() and 0xFF) else 0L)
            sum = (sum + v) and 0xFFFFFFFFL
            i += 4
        }
        return sum
    }

    /** 缺字样例渲染成人能看的字: 汉字/可打印 ASCII 直接给字形, 其余只给码点 */
    private fun renderSample(cps: List<Int>): String = cps.joinToString("、") { c ->
        if (c in 0x20..0x7E || c in 0x4E00..0x9FFF) "'%c'(U+%04X)".format(c.toChar(), c)
        else "U+%04X".format(c)
    }

    private fun ensure(d: ByteArray, n: Int): ByteArray = if (d.size >= n) d.copyOf() else d.copyOf(n)

    private fun put16(d: ByteArray, o: Int, v: Int) {
        d[o] = ((v ushr 8) and 0xFF).toByte()
        d[o + 1] = (v and 0xFF).toByte()
    }

    private fun put32(d: ByteArray, o: Int, v: Long) {
        d[o] = ((v ushr 24) and 0xFF).toByte()
        d[o + 1] = ((v ushr 16) and 0xFF).toByte()
        d[o + 2] = ((v ushr 8) and 0xFF).toByte()
        d[o + 3] = (v and 0xFF).toByte()
    }
}
