package com.chaos.bandpack.data.pack
import java.io.ByteArrayOutputStream
/** 9 Pro 容器的 16 位文件长度与独立记录表布局。 */
object NineShellBuilder {
    const val MAGIC = 0x1234A55A
    const val DEVICE_CODE = 0x10000
    const val PREVIEW_TAG = 0x410
    const val PREVIEW_HDR = 12
    const val REC_OFF = 0x148
    const val LUA_TABLE = 0x158
    const val PKG_OFF = 0x28
    const val PKG_LEN = 12
    const val NAME_OFF = 0x68
    const val NAME_MAX = 64
    const val THEME_OFF = 0xA8
    const val THEME_END = 0x148
    const val FILE_CNT_OFF = 0xD8
    const val THEME_NAME_OFF = 0x100
    const val THEME_NAME_MAX = 0x48
    const val REC_UID_BASE = 0x05000000
    const val BLOB_HDR_LEN = 20
    const val DEFAULT_THEME_NAME = "格式1"
    class Entry(val path: String, val data: ByteArray)
    class Parsed(val files: List<Pair<String, ByteArray>>, val pkg: String, val displayName: String,
                 val themeName: String, val preview: ByteArray, val fileRegion: Int)
    fun recordEnd(fileCount: Int) = LUA_TABLE + 16 * fileCount + 16
    fun checkPreview(preview: ByteArray) {
        require(preview.size >= 12 && ShellWriter.readU32(preview, 0) == PREVIEW_TAG)
        require(ShellWriter.readU32(preview, 8) == preview.size - 12)
        require(((preview[4].toInt() and 255) or ((preview[5].toInt() and 255) shl 8)) == 336)
        require(((preview[6].toInt() and 255) or ((preview[7].toInt() and 255) shl 8)) == 480)
    }
    fun build(files: List<Entry>, pkgName: String, displayName: String, preview: ByteArray,
              themeName: String = DEFAULT_THEME_NAME, deviceCode: Int = DEVICE_CODE): ByteArray {
        ShellWriter.checkPkg(pkgName); ShellWriter.checkPkgAgainst(pkgName); ShellWriter.checkName(displayName)
        require(deviceCode == DEVICE_CODE && files.size in 1..128)
        require(files.map { it.path }.toSet().size == files.size)
        checkPreview(preview)
        val end = LUA_TABLE + files.size * 16
        val previewAt = end + 16
        val head = ByteArray(previewAt)
        fun w(at: Int, value: Int) = ShellWriter.writeU32(head, at, value)
        w(0, MAGIC); w(4, DEVICE_CODE); w(0x10, 0x800); w(0x14, 0x10000); w(0x1C, 1)
        pkgName.toByteArray(Charsets.US_ASCII).copyInto(head, PKG_OFF)
        displayName.toByteArray(Charsets.UTF_8).copyInto(head, NAME_OFF)
        val theme = themeName.toByteArray(Charsets.UTF_8); require(theme.size < THEME_NAME_MAX)
        theme.copyInto(head, THEME_NAME_OFF)
        w(0x20, previewAt); w(0xA8, 0x80000000.toInt()); w(0xAC, previewAt); w(0xB0, 1); w(0xB4, REC_OFF)
        for (at in listOf(0xB8, 0xC0, 0xC8, 0xD0, 0xE0, 0xE8, 0xF0, 0xF8)) w(at + 4, end)
        w(FILE_CNT_OFF, files.size); w(0xDC, LUA_TABLE)
        w(REC_OFF + 8, end); w(REC_OFF + 12, 16); w(end, REC_UID_BASE)
        var pos = previewAt + preview.size
        val blobs = files.mapIndexed { i, e ->
            require(e.path.startsWith("_lua/_Lua/") && e.path.all { it.code in 32..126 })
            val name = e.path.toByteArray(Charsets.US_ASCII)
            require(name.size in 1..120 && e.data.size <= 65535)
            val blob = ByteArray(20 + name.size + e.data.size)
            blob[0] = e.data.size.toByte(); blob[1] = (e.data.size ushr 8).toByte(); blob[3] = name.size.toByte()
            name.copyInto(blob, 20); e.data.copyInto(blob, 20 + name.size)
            val at = LUA_TABLE + i * 16
            w(at, REC_UID_BASE or i); w(at + 8, pos); w(at + 12, blob.size); pos += blob.size
            blob
        }
        return ByteArrayOutputStream(pos).apply { write(head); write(preview); blobs.forEach { write(it) } }.toByteArray()
    }
    fun previewOf(raw: ByteArray): ByteArray {
        val at = ShellWriter.readU32(raw, 0x20)
        require(at >= REC_OFF && at <= raw.size - 12)
        val size = ShellWriter.readU32(raw, at + 8)
        require(size >= 0 && size <= raw.size - at - 12)
        return raw.copyOfRange(at, at + 12 + size).also { checkPreview(it) }
    }
    fun parse(raw: ByteArray): Parsed {
        require(raw.size in (LUA_TABLE + 32)..32_000_000 && ShellWriter.readU32(raw, 0) == MAGIC)
        require(ShellWriter.readU32(raw, 4) == DEVICE_CODE)
        val count = ShellWriter.readU32(raw, FILE_CNT_OFF)
        val table = ShellWriter.readU32(raw, 0xDC)
        require(count in 1..128 && table == LUA_TABLE)
        val end = table + 16 * count
        require(end + 16 <= raw.size && ShellWriter.readU32(raw, 0x20) == end + 16)
        require(ShellWriter.readU32(raw, REC_OFF + 8) == end && ShellWriter.readU32(raw, end) == REC_UID_BASE)
        val preview = previewOf(raw)
        var next = end + 16 + preview.size
        val region = next
        val files = (0 until count).map { i ->
            val at = table + i * 16
            require(ShellWriter.readU32(raw, at) == (REC_UID_BASE or i) && ShellWriter.readU32(raw, at + 4) == 0)
            val off = ShellWriter.readU32(raw, at + 8); val len = ShellWriter.readU32(raw, at + 12)
            require(off == next && off in 0..raw.size && len >= 21 && len <= raw.size - off)
            val size = (raw[off].toInt() and 255) or ((raw[off + 1].toInt() and 255) shl 8)
            val nameLen = raw[off + 3].toInt() and 255
            require(nameLen in 1..120 && raw[off + 2] == 0.toByte() && len == 20 + nameLen + size)
            require((4 until 20).all { raw[off + it] == 0.toByte() })
            val name = String(raw, off + 20, nameLen, Charsets.US_ASCII)
            require(name.startsWith("_lua/_Lua/") && name.all { it.code in 32..126 } && name.split('/').none { it == ".." || it.isEmpty() })
            next += len
            name to raw.copyOfRange(off + 20 + nameLen, next)
        }
        require(next == raw.size && files.map { it.first }.toSet().size == count)
        fun text(at: Int, max: Int, charset: java.nio.charset.Charset): String {
            val n = (0 until max).firstOrNull { raw[at + it] == 0.toByte() } ?: max
            return String(raw, at, n, charset)
        }
        return Parsed(files, String(raw, PKG_OFF, 12, Charsets.US_ASCII), text(NAME_OFF, NAME_MAX, Charsets.UTF_8),
            text(THEME_NAME_OFF, THEME_NAME_MAX, Charsets.UTF_8), preview, region)
    }
}
