package com.chaos.bandpack.data.markdown

/**
 * 一小把够用的 Markdown 解析器。
 *
 * 为什么自己写: 这一份只用来渲染**我们自己的**许可与声明文本(`assets/legal/`),
 * 链条短、格式可控, 引一个第三方渲染库要连带接一份它的许可与体积, 不划算。
 * 而且第三方许可正文一个字符都不能改(见 LicensesDialog 的说明), 渲染失败必须
 * 退成原文 —— 自己写才能把这个回退做实。
 *
 * 支持: 标题 / 无序与有序列表(带缩进) / 引用 / 围栏代码块 / 分隔线 / 表格 /
 * 行内强调与行内码 / 链接。**不支持** HTML 标签、脚注、图像: 它们都会按原样显示,
 * 不尝试解析((面对许可文本, 漏标点比擅自解释更安全)。
 *
 * 纯 Kotlin, 不碰 android.*, 所以能跑在桌面 JVM 的单测里。
 */

/** 一块 Markdown */
sealed class MdBlock {
    data class Heading(val level: Int, val inlines: List<MdInline>) : MdBlock()
    data class Paragraph(val inlines: List<MdInline>) : MdBlock()
    data class ListBlock(val ordered: Boolean, val startAt: Int, val items: List<ListItem>) : MdBlock()
    /** 引用块: 内部按空行分成若干段 */
    data class Quote(val paragraphs: List<List<MdInline>>) : MdBlock()
    data class CodeBlock(val lang: String, val code: String) : MdBlock()
    data class Table(val header: List<List<MdInline>>, val rows: List<List<List<MdInline>>>) : MdBlock()
    object Divider : MdBlock()
}

/** 列表项: [text] 保留原始 Markdown 文本, [depth] 是缩进层级(0 起) */
data class ListItem(val text: String, val depth: Int)

/** 一段行内内容 */
sealed class MdInline {
    data class Text(val text: String) : MdInline()
    data class Strong(val children: List<MdInline>) : MdInline()
    data class Emphasis(val children: List<MdInline>) : MdInline()
    data class CodeSpan(val code: String) : MdInline()
    data class Link(val children: List<MdInline>, val url: String) : MdInline()
}

private val UL = Regex("^(\\s*)[-*+]\\s+(.*)$")
private val OL = Regex("^(\\s*)(\\d+)[.)]\\s+(.*)$")
private val FENCE = Regex("^\\s*```+\\s*(\\S*)\\s*$")
private val HEADING = Regex("^(#{1,6})\\s+(.*)$")
private val DIVIDER = Regex("^\\s*(-{3,}|\\*{3,}|_{3,})\\s*$")
private val TABLE_SEP = Regex("^[\\s:\\-|]+$")
private val SAFE_URL = Regex("^https?://\\S+$", RegexOption.IGNORE_CASE)

/** 只放行 http/https: 许可文本里只有指向许可正文的链接, 别的协议一律不当链接 */
fun isSafeUrl(url: String): Boolean = SAFE_URL.matches(url)

fun parseMarkdown(src: String): List<MdBlock> {
    val lines = src.replace("\r\n", "\n").replace('\r', '\n').split('\n')
    val out = ArrayList<MdBlock>()
    var i = 0
    while (i < lines.size) {
        val line = lines[i]
        if (line.isBlank()) {
            i++
            continue
        }

        // 围栏代码块: 里面的东西一个字符都不动
        val fence = FENCE.matchEntire(line)
        if (fence != null) {
            val lang = fence.groupValues[1]
            val body = ArrayList<String>()
            i++
            while (i < lines.size && FENCE.matchEntire(lines[i]) == null) {
                body.add(lines[i])
                i++
            }
            i++ // 收尾那一行 fence
            out += MdBlock.CodeBlock(lang, body.joinToString("\n").trimEnd('\n'))
            continue
        }

        if (DIVIDER.matches(line)) {
            out += MdBlock.Divider
            i++
            continue
        }

        val heading = HEADING.matchEntire(line)
        if (heading != null) {
            out += MdBlock.Heading(heading.groupValues[1].length, parseInlines(heading.groupValues[2]))
            i++
            continue
        }

        if (line.trimStart().startsWith(">")) {
            val body = ArrayList<String>()
            while (i < lines.size && lines[i].trimStart().startsWith(">")) {
                body.add(lines[i].trimStart().removePrefix(">").trim())
                i++
            }
            out += MdBlock.Quote(splitParagraphs(body))
            continue
        }

        // 表格: 表头下面必须紧跟一行 |---|---|
        if (line.contains('|') && i + 1 < lines.size && isTableSep(lines[i + 1])) {
            val header = splitCells(line)
            i += 2
            val rows = ArrayList<List<String>>()
            while (i < lines.size && lines[i].contains('|') && lines[i].isNotBlank()) {
                rows.add(splitCells(lines[i]))
                i++
            }
            out += MdBlock.Table(
                header.map { parseInlines(it) },
                rows.map { row -> row.map { parseInlines(it) } },
            )
            continue
        }

        val listBlock = readList(lines, i)
        if (listBlock != null) {
            out += listBlock.first
            i = listBlock.second
            continue
        }

        // 段落: 一直吃到空行或下一个块的开头
        val para = ArrayList<String>()
        while (i < lines.size && lines[i].isNotBlank() && !startsBlock(lines[i])) {
            para.add(lines[i])
            i++
        }
        out += MdBlock.Paragraph(parseInlines(joinSoft(para)))
    }
    return out
}

/** 读一个列表(同一缩进层), 返回块与消费到的行号 */
private fun readList(lines: List<String>, from: Int): Pair<MdBlock.ListBlock, Int>? {
    val firstOl = OL.matchEntire(lines[from])
    val firstUl = UL.matchEntire(lines[from])
    val ordered = firstOl != null
    if (firstOl == null && firstUl == null) return null
    val m = firstOl ?: firstUl!!
    val startAt = if (ordered) m.groupValues[2].toIntOrNull() ?: 1 else 1
    val baseIndent = m.groupValues[1].length

    val items = ArrayList<ListItem>()
    var i = from
    while (i < lines.size) {
        val cur = (if (ordered) OL else UL).matchEntire(lines[i])
        if (cur != null) {
            val indent = cur.groupValues[1].length
            // 缩进比首项少 => 列表已经结束
            if (indent < baseIndent) break
            val textIdx = if (ordered) 3 else 2
            items += ListItem(cur.groupValues[textIdx].trim(), (indent - baseIndent) / 2)
            i++
            continue
        }
        if (lines[i].isBlank()) {
            // 列表项之间允许一个空行; 空行之后不再是列表就收尾
            val next = lines.getOrNull(i + 1)
            if (next == null || next.isBlank() || startsBlock(next)) break
            if ((OL.matchEntire(next) ?: UL.matchEntire(next)) == null && !next.startsWith("  ")) break
            i++
            continue
        }
        // 缩进的续行接上一项
        if (lines[i].startsWith("  ") && items.isNotEmpty()) {
            val last = items[items.lastIndex]
            items[items.lastIndex] = ListItem(joinSoft(listOf(last.text, lines[i].trim())), last.depth)
            i++
            continue
        }
        break
    }
    return MdBlock.ListBlock(ordered, startAt, items) to i
}

private fun startsBlock(line: String): Boolean =
    FENCE.matchEntire(line) != null ||
        DIVIDER.matches(line) ||
        HEADING.matchEntire(line) != null ||
        line.trimStart().startsWith(">") ||
        OL.matchEntire(line) != null ||
        UL.matchEntire(line) != null

private fun isTableSep(line: String): Boolean =
    line.contains('-') && line.contains('|') && TABLE_SEP.matches(line.trim())

private fun splitCells(line: String): List<String> {
    val s = line.trim()
    val core = if (s.startsWith("|")) s.drop(1) else s
    return core.split(Regex("(?<!\\\\)\\|")).map { it.trim().replace("\\|", "|") }
        .let { if (it.size > 1 && it.last().isEmpty()) it.dropLast(1) else it }
}

/**
 * 段落里的软换行怎么处理: 中英文(Iso这首歌)不含空格。所以行尾是 ASCII 词、下一行
 * 开头也是 ASCII 词时才补一个空格, 其余情况直接相接 —— 中文换行连起来才是对的。
 */
private fun joinSoft(lines: List<String>): String {
    if (lines.size == 1) return lines[0]
    val sb = StringBuilder()
    lines.forEachIndexed { idx, line ->
        if (idx > 0) {
            val prevEnd = lines[idx - 1].lastOrNull()
            val nextStart = line.firstOrNull()
            if (isAsciiWord(prevEnd) && isAsciiWord(nextStart)) sb.append(' ')
        }
        sb.append(line)
    }
    return sb.toString()
}

private fun isAsciiWord(c: Char?): Boolean =
    c != null && (c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9')

private fun splitParagraphs(lines: List<String>): List<List<MdInline>> {
    val out = ArrayList<List<MdInline>>()
    val buf = ArrayList<String>()
    fun flush() {
        if (buf.isNotEmpty()) {
            out += parseInlines(joinSoft(buf))
            buf.clear()
        }
    }
    for (l in lines) {
        if (l.isBlank()) flush() else buf.add(l)
    }
    flush()
    return out
}

/**
 * 行内解析。优先级: 转义 > 行内码 > 链接 > 强调。
 * 强调符号只认 `*`(不认 `_`): 许可文本里大量 `mi_sans` 这类标识符, 认 `_` 会把它们劈开。
 */
fun parseInlines(src: String): List<MdInline> {
    val out = ArrayList<MdInline>()
    val buf = StringBuilder()
    fun flush() {
        if (buf.isNotEmpty()) {
            out += MdInline.Text(buf.toString())
            buf.setLength(0)
        }
    }

    var i = 0
    while (i < src.length) {
        when (val c = src[i]) {
            '\\' -> {
                if (i + 1 < src.length) buf.append(src[i + 1])
                i += 2
            }
            '`' -> {
                val end = src.indexOf('`', i + 1)
                if (end > i + 1) {
                    flush()
                    out += MdInline.CodeSpan(src.substring(i + 1, end))
                    i = end + 1
                } else {
                    buf.append(c)
                    i++
                }
            }
            '[' -> {
                val labelEnd = src.indexOf(']', i)
                val link = if (labelEnd > i && src.getOrNull(labelEnd + 1) == '(') {
                    val urlEnd = src.indexOf(')', labelEnd + 2)
                    if (urlEnd > labelEnd) {
                        val url = src.substring(labelEnd + 2, urlEnd).trim()
                        if (isSafeUrl(url)) Pair(src.substring(i + 1, labelEnd), url) else null
                    } else {
                        null
                    }
                } else {
                    null
                }
                if (link == null) {
                    buf.append(c)
                    i++
                } else {
                    flush()
                    out += MdInline.Link(parseInlines(link.first), link.second)
                    i = src.indexOf(')', labelEnd + 2) + 1
                }
            }
            '*' -> {
                val marker = if (src.startsWith("**", i)) "**" else "*"
                val end = src.indexOf(marker, i + marker.length)
                val inner = if (end > i + marker.length) src.substring(i + marker.length, end) else null
                // 内部不许有.code newline, 也不能是全空白 —— 否则 Thm roundTrip 会把 `a ** b` 这种吃掉
                if (inner != null && inner.isNotBlank() && '\n' !in inner) {
                    flush()
                    val children = parseInlines(inner)
                    out += if (marker.length == 2) MdInline.Strong(children) else MdInline.Emphasis(children)
                    i = end + marker.length
                } else {
                    buf.append(c)
                    i++
                }
            }
            else -> {
                buf.append(c)
                i++
            }
        }
    }
    flush()
    return out
}
