package com.chaos.bandpack.data.pack

import java.io.ByteArrayOutputStream

/**
 * 图标包容器(CIPK)—— 手环侧 `icon_pack.lua` 按这个格式解包, 两侧必须逐字节一致:
 *
 *   [4 字节 ASCII 'CIPK'][u32 张数]
 *   张数 次: [u32 数据长度][u8 名字长度][名字][数据]
 *
 * 名字形如 `<stem>.bin`(ASCII, `^[A-Za-z0-9_]+\.bin$`, 24 字节以内)；手环只认
 * 内核桌面表与系统资源重定向表中的 stem。
 */
object Cipk {

    val MAGIC = byteArrayOf('C'.code.toByte(), 'I'.code.toByte(), 'P'.code.toByte(), 'K'.code.toByte())
    const val NAME_MAX = 24
    const val ICON_LEN_MAX = 0x80000          // 单张上限 512KB(与 Lua 侧的门一致)
    const val COUNT_MAX = 64

    private val NAME_RE = Regex("^[A-Za-z0-9_]+\\.bin$")

    class CipkError(message: String) : Exception(message)

    /** 一张图标: stem(不带扩展名) + 按槽位规格转换的图标 bin */
    class Icon(val stem: String, val data: ByteArray) {
        val fileName: String get() = "$stem.bin"
    }

    fun build(icons: List<Icon>): ByteArray {
        if (icons.isEmpty()) throw CipkError("一张图标都没有, 打不出包")
        if (icons.size > COUNT_MAX) throw CipkError("图标张数超过上限 $COUNT_MAX")
        val seen = HashSet<String>()
        val out = ByteArrayOutputStream(icons.size * 50188)
        out.write(MAGIC)
        out.write(u32(icons.size))
        for (i in icons) {
            val nb = i.fileName.toByteArray(Charsets.US_ASCII)
            if (nb.size > NAME_MAX) throw CipkError("图标文件名太长: ${i.fileName}")
            if (!NAME_RE.matches(i.fileName)) throw CipkError("图标文件名不合规: ${i.fileName}")
            if (!seen.add(i.stem)) throw CipkError("图标重复: ${i.stem}")
            if (i.data.isEmpty() || i.data.size > ICON_LEN_MAX) {
                throw CipkError("${i.fileName} 长度 ${i.data.size} 超出单张上限 $ICON_LEN_MAX")
            }
            out.write(u32(i.data.size))
            out.write(nb.size)
            out.write(nb)
            out.write(i.data)
        }
        return out.toByteArray()
    }

    /** 解回来(自检与测试用)。任何越界/坏长度直接抛。 */
    fun parse(blob: ByteArray): List<Pair<String, ByteArray>> {
        if (blob.size < 8 || !blob.copyOfRange(0, 4).contentEquals(MAGIC)) throw CipkError("CIPK 魔数不符")
        val count = ShellWriter.readU32(blob, 4)
        if (count < 1 || count > COUNT_MAX) throw CipkError("张数非法: $count")
        val out = ArrayList<Pair<String, ByteArray>>(count)
        var pos = 8
        repeat(count) { idx ->
            if (pos + 5 > blob.size) throw CipkError("第 ${idx + 1} 张长度头越界")
            val len = ShellWriter.readU32(blob, pos)
            val nl = blob[pos + 4].toInt() and 0xFF
            pos += 5
            if (nl < 1 || nl > NAME_MAX) throw CipkError("第 ${idx + 1} 张名字长度非法: $nl")
            if (pos + nl > blob.size) throw CipkError("第 ${idx + 1} 张名字越界")
            val name = String(blob, pos, nl, Charsets.US_ASCII)
            if (!NAME_RE.matches(name)) throw CipkError("第 ${idx + 1} 张名字不合规: $name")
            pos += nl
            if (len !in 1..ICON_LEN_MAX || len > blob.size - pos) throw CipkError("第 ${idx + 1} 张数据越界")
            out.add(name to blob.copyOfRange(pos, pos + len))
            pos += len
        }
        if (pos != blob.size) throw CipkError("容器尾部多出 ${blob.size - pos} 字节")
        if (out.map { it.first }.toSet().size != out.size) throw CipkError("图标名字重复")
        return out
    }

    private fun u32(v: Int): ByteArray = byteArrayOf(
        (v and 0xFF).toByte(),
        ((v ushr 8) and 0xFF).toByte(),
        ((v ushr 16) and 0xFF).toByte(),
        ((v ushr 24) and 0xFF).toByte(),
    )
}
