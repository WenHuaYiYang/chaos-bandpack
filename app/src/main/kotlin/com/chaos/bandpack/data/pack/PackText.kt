package com.chaos.bandpack.data.pack

/**
 * 手环侧那些"按字节算"的字符串上限。
 *
 * 为什么需要一个 helper: 容器里的短名/显示名都是定长字节区, 中文一个字占 3 字节、
 * emoji 一个占 4 字节, 而输入框习惯按**字符**限长 —— 两边口径不一致时, 用户能填进来
 * 的名字恰恰是打不出去的那批(典型: 四字以上的中文短名)。所以输入侧就按字节截断,
 * 让"能填进来的"和"能导出的"是同一批。
 */

/** 按 UTF-8 字节上限截断, 且不劈开字符(emoji 是代理对, 按 char 切会切出半个乱码) */
internal fun String.truncateBytes(maxBytes: Int): String {
    if (this.toByteArray(Charsets.UTF_8).size <= maxBytes) return this
    val sb = StringBuilder()
    var used = 0
    var i = 0
    while (i < length) {
        val cp = codePointAt(i)
        val len = when {
            cp < 0x80 -> 1
            cp < 0x800 -> 2
            cp < 0x10000 -> 3
            else -> 4
        }
        if (used + len > maxBytes) break
        sb.appendCodePoint(cp)
        used += len
        i += Character.charCount(cp)
    }
    return sb.toString()
}
