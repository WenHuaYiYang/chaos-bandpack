package com.chaos.bandpack.data.font

import java.nio.charset.Charset as JCharset

/**
 * 子集化要保留的字符集，口径与 PC 侧 `scripts/build_font_subset.py` 完全一致：
 * 全 GB2312（6763 汉字）+ ASCII 可打印 + 若干标点/符号区。
 *
 * 为什么必须是**全** GB2312：一级字 4153 + 二级字 3008，二级字占 44.5%，
 * 只留一级时人名、地名、生僻字直接显示成空白框（真机见过）。
 *
 * GB2312 的取法照抄 Python：按区位扫 2 字节序列再解码，解不出来的跳过。
 * 这里不能用"先把整段字节解码成字符串"—— 非法序列的替换行为两端不一致；
 * 逐序列解码并**回编码校验**，只留真正可往返的那些。
 */
object Charset {

    /** 标点/符号区（闭区间），与 Python 脚本同一张表 */
    private val RANGES = listOf(
        0x00A0 to 0x00FF,   // 拉丁补充
        0x2000 to 0x206F,   // 常用标点
        0x2190 to 0x21FF,   // 箭头
        0x2460 to 0x24FF,   // 带圈数字
        0x25A0 to 0x25FF,   // 几何图形
        0x2600 to 0x26FF,   // 杂项符号
        0x3000 to 0x303F,   // CJK 标点
        0xFE30 to 0xFE4F,   // CJK 兼容形式
        0xFF00 to 0xFFEF,   // 全角字符
    )

    val gb2312: Set<Int> by lazy { buildGb2312() }

    /**
     * 硬要求：缺一个就拒绝这份字体。汉字缺字在界面上就是一个空白框，
     * ASCII 缺了连数字和英文都显示不出来，两者都不接受。
     */
    val required: Set<Int> by lazy {
        val out = HashSet<Int>(8192)
        out.addAll(gb2312)
        for (c in 0x20..0x7E) out.add(c)
        out
    }

    /**
     * 字集档位。精简档是 PC 侧一直用的那套(全 GB2312 + ASCII + 符号区)；
     * 保留繁体档在它之上再加 Big5 常用字 5401 + 次常用字 7652(去重后约 1.3 万字)。
     */
    enum class Kind { SIMPLIFIED, WITH_TRADITIONAL }

    /**
     * 繁体字集：Big5 的两个汉字区。
     *   常用字 0xA440..0xC67E（5401 个）、次常用字 0xC940..0xF9D5（7652 个）；
     *   中间的 0xC6A1..0xC8FE 是符号区，不在汉字范围内，跳过。
     * 与 GB2312 同一套做法：逐序列解码 + 回编码校验，并且**只认 CJK 统一汉字区**
     * —— Android 的 Big5 解码器会把个别空位映射成私用区码点，私用码点混进来就等于
     * 给字体加一条谁都没有的硬要求。
     */
    val big5: Set<Int> by lazy { buildBig5() }

    /** 符号区（尽力而为）：有就留、没有就丢，缺了只在报告里说一声 */
    private val extraSymbols: Set<Int> by lazy {
        val out = HashSet<Int>(1024)
        for ((lo, hi) in RANGES) for (c in lo..hi) out.add(c)
        out
    }

    private val targetCache = HashMap<Kind, Set<Int>>(2)

    /** 子集想要的全部字符（硬要求 + 符号区 [+ 繁体]） */
    fun target(kind: Kind): Set<Int> = targetCache.getOrPut(kind) {
        val out = HashSet<Int>(16384)
        out.addAll(required)
        out.addAll(extraSymbols)
        if (kind == Kind.WITH_TRADITIONAL) out.addAll(big5)
        out
    }

    /** 源字体缺哪些硬要求字符（前 [limit] 个，用于给出可读的失败原因） */
    fun missingRequired(cmap: Map<Int, Int>, limit: Int = 12): List<Int> =
        required.asSequence().filter { it !in cmap }.take(limit).toList()

    fun missingRequiredCount(cmap: Map<Int, Int>): Int = required.count { it !in cmap }

    /**
     * 源字体缺多少个"可选项"字符（只上报，不拒绝）。
     * 保留繁体档下把繁体字的缺口也计进来 —— 字体缺繁体字形是常态
     * （很多简体字库压根不做繁体），必须是"少几个就少几个"，不能拒绝整份字体。
     */
    fun missingOptionalCount(cmap: Map<Int, Int>, kind: Kind): Int {
        var n = extraSymbols.count { it !in cmap }
        if (kind == Kind.WITH_TRADITIONAL) n += big5.count { it !in cmap }
        return n
    }

    /** 繁体字集里源字体有多少个字（给界面显示"繁体保留了多少"） */
    fun traditionalHits(cmap: Map<Int, Int>): Int = big5.count { it in cmap }

    private fun buildBig5(): Set<Int> {
        val cs = runCatching { JCharset.forName("Big5") }
            .recoverCatching { JCharset.forName("x-windows-950") }
            .getOrNull() ?: return emptySet()
        val out = HashSet<Int>(14000)
        val buf = ByteArray(2)
        for ((hiLo, hiHi) in listOf(0xA4 to 0xC6, 0xC9 to 0xF9)) {
            for (hi in hiLo..hiHi) {
                for (lo in 0x40..0xFE) {
                    // Big5 尾字节的低 7 位是主体: 0x40..0x7E 与 0xA1..0xFE
                    if (lo == 0x7F || (lo in 0x80..0xA0)) continue
                    buf[0] = hi.toByte()
                    buf[1] = lo.toByte()
                    val s = String(buf, cs)
                    if (s.length != 1) continue
                    val c = s[0]
                    if (c.code !in 0x4E00..0x9FFF) continue
                    if (!s.toByteArray(cs).contentEquals(buf)) continue
                    out.add(c.code)
                }
            }
        }
        return out
    }

    private fun buildGb2312(): Set<Int> {
        // Android 的 ICU 认 "GB2312"; 个别精简 ROM 只挂了 GBK —— 两者都比标准 GB2312 宽,
        // 所以不能只靠回编码校验(见下面那道汉字区门)。
        val cs = runCatching { JCharset.forName("GB2312") }
            .recoverCatching { JCharset.forName("GBK") }
            .getOrNull() ?: return emptySet()
        val out = HashSet<Int>(8192)
        val buf = ByteArray(2)
        for (hi in 0xB0..0xF7) {
            for (lo in 0xA1..0xFE) {
                buf[0] = hi.toByte()
                buf[1] = lo.toByte()
                val s = String(buf, cs)
                if (s.length != 1) continue
                val c = s[0]
                if (c == '\uFFFD') continue
                if (!s.toByteArray(cs).contentEquals(buf)) continue
                // 根因(真机: 报"这份字体缺 5 个必需字符, 例如 U+E810..U+E814"):
                // 区 16..87 按标准**只有汉字**, 但 GB2312 在这 72x94 = 6768 个位置里留了
                // 5 个空位(D7FA..D7FE), 而 Android 的 GB2312/GBK 解码器把它们当 GB18030
                // 私用区映射成 U+E810..U+E814 —— 私用区还能原样编回那 5 组字节,
                // 于是回编码校验照样放行, 5 个私用码点混进"汉字硬要求"里。
                // 任何第三方中文字体都不含小米私用字形 => 谁都过不了这道门。
                // 只认汉字区就把这个平台差异钉死: 6763 个, 一个不多。
                if (c.code !in 0x4E00..0x9FFF) continue
                out.add(c.code)
            }
        }
        return out
    }
}
