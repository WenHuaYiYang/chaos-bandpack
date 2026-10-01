package com.chaos.bandpack.data.pack

/**
 * 表盘标题的宽度口径。
 *
 * 手环上那行标题是 40 号字、整屏居中(屏宽 390px 上下), 实测"字体投递 花朝粗"
 * (7 个汉字 + 1 个空格 = 16 半角)正好占满一行而不折行/不截断 —— 这就是上限的来历。
 * 超过这个宽度, 手环上会折成两行或直接截断, 所以界面上必须提前提醒。
 */
object TitleText {

    /** 一行能放的半角字符数(全角算 2) */
    const val MAX_HALF = 16

    /** 标题宽度(半角为单位) */
    fun width(s: String): Int {
        var w = 0
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            w += if (isWide(cp)) 2 else 1
            i += Character.charCount(cp)
        }
        return w
    }

    /** 超宽返回提示文案, 合法返回 null */
    fun validate(s: String): String? {
        val t = s.trim()
        if (t.isEmpty()) return "标题不能为空"
        val w = width(t)
        if (w > MAX_HALF) {
            return "标题太宽: 当前 $w 个半角, 手环上最多 $MAX_HALF 个半角(一个汉字算 2 个)," +
                "超出的部分会折行或被截断"
        }
        return null
    }

    /**
     * 是否按全角算宽。取的是 Unicode East Asian Width 里我们真会遇到的几段
     * (CJK 汉字/假名/谚文/全角标点与全角字母), 不追求 EAW 全表。
     */
    private fun isWide(cp: Int): Boolean = when (cp) {
        in 0x1100..0x115F -> true      // 谚文字母
        in 0x2E80..0x303E -> true      // CJK 部首/标点
        in 0x3041..0x33FF -> true      // 假名/注音/CJK 兼容
        in 0x3400..0x4DBF -> true      // CJK 扩展 A
        in 0x4E00..0x9FFF -> true      // CJK 统一汉字
        in 0xA000..0xA4CF -> true      // 彝文
        in 0xAC00..0xD7A3 -> true      // 谚文音节
        in 0xF900..0xFAFF -> true      // CJK 兼容汉字
        in 0xFE10..0xFE19 -> true      // 竖排标点
        in 0xFE30..0xFE6F -> true      // CJK 兼容形式
        in 0xFF00..0xFF60 -> true      // 全角形式
        in 0xFFE0..0xFFE6 -> true      // 全角符号
        else -> false
    }
}
