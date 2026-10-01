package com.chaos.bandpack.data.font

/**
 * 垂直度量归一化：把任意字体的 hhea / OS/2 度量对齐到固件自带字体的比例。
 *
 * 为什么必须做：手环的行盒与标题位置是按固件自带 `MiSans-Regular` 的度量排死的
 * （参考值从固件资源包里那份 TTF 实读：upm 1000, hhea 1044/-282/0,
 * OS/2 typo 890/-110/326, win 1044/282 —— 行高比 1.326em）。自定义字体行高比不同
 * 就会在固定行盒里错位：霞鹜文楷 1.184 偏小(标题文字贴顶)、花朝粗 1.722 偏大 30%
 * (每行顶部留一大块空白)。对齐比例之后基线落点与系统字体一致。
 *
 * 两个容易漏的点：
 *   - **`fsSelection` 的 USE_TYPO_METRICS 位(0x0080)要清掉**：置位时渲染器改用 typo 那套
 *     度量，行盒算法与系统字体不同；固件的 MiSans 没置这个位。
 *   - upm 不是 1000 的字体要按 `upm/1000` **等比折算**，不能直接写常数。
 */
object Metrics {

    /** 固件 MiSans-Regular 的度量（从固件字体文件实测读出） */
    const val MI_UPM = 1000
    const val MI_ASC = 1044
    const val MI_DESC = -282
    const val MI_GAP = 0
    const val MI_TYPO_ASC = 890
    const val MI_TYPO_DESC = -110
    const val MI_TYPO_GAP = 326
    /** OS/2 fsSelection 里的 USE_TYPO_METRICS 位 */
    const val USE_TYPO_METRICS = 0x0080

    // hhea 里的字段偏移
    private const val HHEA_ASC = 4
    private const val HHEA_DESC = 6
    private const val HHEA_GAP = 8

    // OS/2 里的字段偏移
    private const val OS2_FS_SELECTION = 62
    private const val OS2_TYPO_ASC = 68
    private const val OS2_TYPO_DESC = 70
    private const val OS2_TYPO_GAP = 72
    private const val OS2_WIN_ASC = 74
    private const val OS2_WIN_DESC = 76
    private const val OS2_MIN_LEN = 78

    /** 归一化结果（给界面显示"行高比从多少改到多少"） */
    data class Report(val upm: Int, val ratioBefore: Double, val ratioAfter: Double)

    /**
     * 就地改写立即可用的度量字段。[upm] 是源字体 head.unitsPerEm。
     * [hhea] 必须是可写副本（长度 >= 36）；[os2] 传 null 表示源字体没有 OS/2 表。
     */
    fun apply(hhea: ByteArray, os2: ByteArray?, upm: Int): Report {
        val k = upm.toDouble() / MI_UPM

        val ascBefore = readI16(hhea, HHEA_ASC)
        val descBefore = readI16(hhea, HHEA_DESC)
        val ratioBefore = (ascBefore - descBefore).toDouble() / upm

        writeI16(hhea, HHEA_ASC, scale(MI_ASC, k))
        writeI16(hhea, HHEA_DESC, scale(MI_DESC, k))
        writeI16(hhea, HHEA_GAP, scale(MI_GAP, k))

        if (os2 != null && os2.size >= OS2_MIN_LEN) {
            writeI16(os2, OS2_TYPO_ASC, scale(MI_TYPO_ASC, k))
            writeI16(os2, OS2_TYPO_DESC, scale(MI_TYPO_DESC, k))
            writeI16(os2, OS2_TYPO_GAP, scale(MI_TYPO_GAP, k))
            writeI16(os2, OS2_WIN_ASC, scale(MI_ASC, k))
            writeI16(os2, OS2_WIN_DESC, scale(-MI_DESC, k))
            val sel = readU16(os2, OS2_FS_SELECTION)
            writeU16(os2, OS2_FS_SELECTION, sel and USE_TYPO_METRICS.inv())
        }

        val ratioAfter = (scale(MI_ASC, k) - scale(MI_DESC, k)).toDouble() / upm
        return Report(upm, ratioBefore, ratioAfter)
    }

    /** 四舍五入到最近的整数（度量字段是 FWORD，负数也要正确取整） */
    private fun scale(v: Int, k: Double): Int = Math.round(v * k).toInt()

    private fun readU16(b: ByteArray, o: Int): Int = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)

    private fun readI16(b: ByteArray, o: Int): Int = readU16(b, o).toShort().toInt()

    private fun writeU16(b: ByteArray, o: Int, v: Int) {
        b[o] = ((v ushr 8) and 0xFF).toByte()
        b[o + 1] = (v and 0xFF).toByte()
    }

    private fun writeI16(b: ByteArray, o: Int, v: Int) = writeU16(b, o, v and 0xFFFF)
}
