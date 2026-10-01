package com.chaos.bandpack.data.font

/**
 * sfnt(TrueType) 只读解析。只做子集化必需的那几件事：表目录、loca、cmap、
 * head/maxp/hhea/hmtx，以及复合字形的分量表。
 *
 * 全程大端；越界一律当作"文件坏了"抛 [SfntError]，不返回半截数据 ——
 * 子集化是"要么出一份能用的字体，要么明确失败"，不允许产出半成品。
 */
class SfntError(message: String) : Exception(message)

/** 大端读字节数组 */
internal class Be(val b: ByteArray) {
    fun u8(o: Int): Int {
        if (o < 0 || o >= b.size) throw SfntError("读越界 @$o")
        return b[o].toInt() and 0xFF
    }

    fun u16(o: Int): Int = (u8(o) shl 8) or u8(o + 1)
    fun i16(o: Int): Int = u16(o).toShort().toInt()
    fun u32(o: Int): Long = (u16(o).toLong() shl 16) or u16(o + 2).toLong()
    fun tag(o: Int): String = String(b, o, 4, Charsets.US_ASCII)
}

class SfntTable(val tag: String, val offset: Int, val length: Int, val checksum: Long)

class Sfnt(val bytes: ByteArray) {
    val tables: Map<String, SfntTable>
    val numTables: Int

    init {
        val r = Be(bytes)
        if (bytes.size < 12) throw SfntError("文件太短")
        val ver = r.u32(0)
        // 0x00010000 是 TrueType, 'true'/'typ1' 也算; 'OTTO' 是 CFF 轮廓, 我们不做
        if (ver == 0x4F54544FL) throw SfntError("这是 CFF(OTTO) 字体，本应用只做 TrueType 轮廓")
        if (ver != 0x00010000L && ver != 0x74727565L && ver != 0x74797031L) {
            throw SfntError("不是 TrueType 字体（魔数 0x%08X）".format(ver))
        }
        val n = r.u16(4)
        if (n <= 0 || n > 512) throw SfntError("表目录条数异常: $n")
        val m = HashMap<String, SfntTable>(n * 2)
        for (i in 0 until n) {
            val p = 12 + i * 16
            val tag = r.tag(p)
            val off = r.u32(p + 8).toInt()
            val len = r.u32(p + 12).toInt()
            if (off < 0 || len < 0 || off + len > bytes.size) {
                throw SfntError("表 $tag 越界($off+$len > ${bytes.size})")
            }
            m[tag] = SfntTable(tag, off, len, r.u32(p + 4))
        }
        tables = m
        numTables = n
    }

    fun need(tag: String): SfntTable = tables[tag] ?: throw SfntError("缺表 $tag")

    fun has(tag: String): Boolean = tables.containsKey(tag)

    fun slice(t: SfntTable): ByteArray = bytes.copyOfRange(t.offset, t.offset + t.length)

    /** head 的两个字段：unitsPerEm 与 indexToLocFormat */
    fun headInfo(): Pair<Int, Int> {
        val h = slice(need("head"))
        val r = Be(h)
        return r.u16(18) to r.i16(50)
    }

    fun numGlyphs(): Int = Be(slice(need("maxp"))).u16(4)

    fun numHMetrics(): Int = Be(slice(need("hhea"))).u16(34)

    /**
     * loca -> 字形数据在 glyf 表里的偏移（长度 numGlyphs+1）。
     * indexToLocFormat: 0 表示短格式(u16, 值 ×2), 1 表示长格式(u32)。
     */
    fun locaOffsets(): IntArray {
        val n = numGlyphs()
        val (_, fmt) = headInfo()
        val l = slice(need("loca"))
        val r = Be(l)
        val out = IntArray(n + 1)
        for (i in 0..n) {
            out[i] = if (fmt == 0) r.u16(i * 2) * 2 else r.u32(i * 4).toInt()
        }
        return out
    }

    /**
     * cmap -> 码点映射（只收 BMP，全部目标字符都在 BMP）。
     * 优先级 (3,10) 格式 12 > (3,1) 格式 4 > (0,*) —— 与 fontTools getBestCmap 同序。
     */
    fun cmap(): Map<Int, Int> {
        val c = slice(need("cmap"))
        val r = Be(c)
        val n = r.u16(2)
        var best = -1
        var bestRank = -1
        for (i in 0 until n) {
            val p = 4 + i * 8
            val plat = r.u16(p)
            val enc = r.u16(p + 2)
            val off = r.u32(p + 4).toInt()
            if (off < 0 || off + 2 > c.size) continue
            val fmt = r.u16(off)
            val rank = when {
                plat == 3 && enc == 10 && fmt == 12 -> 4
                plat == 3 && enc == 1 && fmt == 4 -> 3
                plat == 0 && fmt == 12 -> 2
                plat == 0 && fmt == 4 -> 1
                else -> -1
            }
            if (rank > bestRank) {
                bestRank = rank
                best = off
            }
        }
        if (best < 0) throw SfntError("cmap 里没有可用的 Unicode 子表")
        return when (r.u16(best)) {
            4 -> cmapFormat4(c, best)
            12 -> cmapFormat12(c, best)
            else -> throw SfntError("不支持的 cmap 格式 ${r.u16(best)}")
        }
    }

    private fun cmapFormat4(c: ByteArray, o: Int): Map<Int, Int> {
        val r = Be(c)
        val segX2 = r.u16(o + 6)
        val seg = segX2 / 2
        val endBase = o + 14
        val startBase = endBase + segX2 + 2
        val deltaBase = startBase + segX2
        val rangeBase = deltaBase + segX2
        val out = HashMap<Int, Int>(8192)
        for (i in 0 until seg) {
            val end = r.u16(endBase + i * 2)
            val start = r.u16(startBase + i * 2)
            if (start > end || start == 0xFFFF) continue
            val delta = r.u16(deltaBase + i * 2)
            val ro = r.u16(rangeBase + i * 2)
            for (ch in start..end) {
                if (ch > 0xFFFF) break
                val gid = if (ro == 0) {
                    (ch + delta) and 0xFFFF
                } else {
                    // 地址 = &idRangeOffset[i] + ro + 2*(ch - start)
                    val at = rangeBase + i * 2 + ro + 2 * (ch - start)
                    if (at + 1 >= c.size) continue
                    val g = r.u16(at)
                    if (g == 0) 0 else (g + delta) and 0xFFFF
                }
                if (gid != 0) out[ch] = gid
            }
        }
        return out
    }

    private fun cmapFormat12(c: ByteArray, o: Int): Map<Int, Int> {
        val r = Be(c)
        val groups = r.u32(o + 12).toInt()
        val out = HashMap<Int, Int>(8192)
        for (i in 0 until groups) {
            val p = o + 16 + i * 12
            val start = r.u32(p)
            val end = r.u32(p + 4)
            val gid0 = r.u32(p + 8)
            var ch = start
            while (ch <= end) {
                if (ch > 0xFFFFL) break
                out[ch.toInt()] = (gid0 + (ch - start)).toInt()
                ch++
            }
        }
        return out
    }

    /** 字形数据（原始字节，含复合字形的分量表与指令） */
    fun glyph(glyf: ByteArray, offsets: IntArray, gid: Int): ByteArray =
        if (offsets[gid] >= offsets[gid + 1]) ByteArray(0)
        else glyf.copyOfRange(offsets[gid], offsets[gid + 1])
}

// ===== 复合字形 =====

private const val ARG_1_AND_2_ARE_WORDS = 0x0001
private const val WE_HAVE_A_SCALE = 0x0008
private const val MORE_COMPONENTS = 0x0020
private const val WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
private const val WE_HAVE_A_TWO_BY_TWO = 0x0080
private const val WE_HAVE_INSTRUCTIONS = 0x0100

/** 复合字形引用的分量 gid（非复合返回空表） */
fun compositeComponents(g: ByteArray): List<Int> {
    if (g.size < 10) return emptyList()
    val r = Be(g)
    if (r.i16(0) >= 0) return emptyList()
    val out = ArrayList<Int>(4)
    var o = 10
    while (true) {
        if (o + 4 > g.size) throw SfntError("复合字形分量表越界")
        val flags = r.u16(o)
        out.add(r.u16(o + 2))
        o += 4
        o += if (flags and ARG_1_AND_2_ARE_WORDS != 0) 4 else 2
        o += when {
            flags and WE_HAVE_A_SCALE != 0 -> 2
            flags and WE_HAVE_AN_X_AND_Y_SCALE != 0 -> 4
            flags and WE_HAVE_A_TWO_BY_TWO != 0 -> 8
            else -> 0
        }
        if (flags and MORE_COMPONENTS == 0) {
            if (flags and WE_HAVE_INSTRUCTIONS != 0 && o + 2 <= g.size) {
                val n = Be(g).u16(o)
                o += 2 + n
            }
            break
        }
    }
    if (o > g.size) throw SfntError("复合字形越界")
    return out
}

/**
 * 复合字形重写：分量表里的 glyphIndex 是**必须重编号**的字段（新字体里字序号全变了）。
 * 其余字节原样保留 —— 缩放、偏移、指令都不受影响。
 */
fun rewriteComposite(g: ByteArray, remap: (Int) -> Int): ByteArray {
    if (g.size < 10) return g
    val r = Be(g)
    if (r.i16(0) >= 0) return g
    val out = g.copyOf()
    var o = 10
    while (true) {
        if (o + 4 > out.size) throw SfntError("复合字形分量表越界")
        val flags = r.u16(o)
        val gid = r.u16(o + 2)
        val newGid = remap(gid)
        out[o + 2] = ((newGid ushr 8) and 0xFF).toByte()
        out[o + 3] = (newGid and 0xFF).toByte()
        o += 4
        o += if (flags and ARG_1_AND_2_ARE_WORDS != 0) 4 else 2
        o += when {
            flags and WE_HAVE_A_SCALE != 0 -> 2
            flags and WE_HAVE_AN_X_AND_Y_SCALE != 0 -> 4
            flags and WE_HAVE_A_TWO_BY_TWO != 0 -> 8
            else -> 0
        }
        if (flags and MORE_COMPONENTS == 0) break
    }
    return out
}
