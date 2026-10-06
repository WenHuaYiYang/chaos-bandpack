package com.chaos.bandpack.data.project

/** 只读取字符串、整数和表字面量，不求值 Lua。 */
internal class LuaLiteral(private val text: String, start: Int = 0) {
    private var at = start
    private var nodes = 0
    private fun space() { while (at < text.length && text[at].isWhitespace()) at++ }
    fun value(depth: Int = 0): Any {
        require(depth <= 6 && ++nodes <= 3000) { "投递清单嵌套过深或过大" }
        space(); require(at < text.length)
        return when (text[at]) {
            '"', '\'' -> string()
            '{' -> {
                at++; val map = linkedMapOf<String, Any>(); val list = mutableListOf<Any>()
                space()
                while (at < text.length && text[at] != '}') {
                    val begin = at
                    while (at < text.length && (text[at].isLetterOrDigit() || text[at] == '_')) at++
                    val name = text.substring(begin, at); space()
                    if (name.isNotEmpty() && at < text.length && text[at] == '=') {
                        at++; require(name !in map) { "清单字段重复" }; map[name] = value(depth + 1)
                    } else { at = begin; list.add(value(depth + 1)) }
                    space(); if (at < text.length && text[at] in ",;") { at++; space() } else break
                }
                require(at < text.length && text[at++] == '}') { "不是有效的清单字面量" }
                require(map.isEmpty() || list.isEmpty()) { "清单表类型混杂" }
                if (map.isNotEmpty()) map else list
            }
            in '0'..'9' -> {
                val begin = at
                while (at < text.length && text[at] in '0'..'9') at++
                text.substring(begin, at).toInt()
            }
            else -> error("清单包含不能读取的表达式")
        }
    }

    private fun string(): String {
        val quote = text[at++]; val out = StringBuilder()
        while (at < text.length) {
            val ch = text[at++]
            if (ch == quote) return out.toString().also { require(it.length <= 256) }
            if (ch != '\\') { out.append(ch); continue }
            require(at < text.length)
            when (val next = text[at++]) {
                '\\', '"', '\'' -> out.append(next)
                'n' -> out.append('\n')
                'r' -> out.append('\r')
                't' -> out.append('\t')
                in '0'..'9' -> {
                    var number = "$next"
                    repeat(2) { if (at < text.length && text[at] in '0'..'9') number += text[at++] }
                    val byte = number.toInt(); require(byte <= 255); out.append(byte.toChar())
                }
                else -> error("清单字符串转义不支持")
            }
        }
        error("清单字符串未结束")
    }
}
